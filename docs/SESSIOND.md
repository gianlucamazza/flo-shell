# flo-sessiond

Demone di sistema che dà al tablet le due politiche di reattività che aveva
Android: **spinta della CPU al tocco** e **congelamento delle app in
background**. Sorgenti in `sessiond/`, C17, solo libc (musl o glibc), nessuna
dipendenza da libsystemd. Vedi `PLAN.md`, Fase 4 e rischio R6.

Stato: implementato e provato sul portatile con alberi sysfs/cgroup finti.
**Non ancora provato sul tablet**: la procedura è in fondo.

## Progetto

Un solo processo, un solo thread, un ciclo `epoll_wait` senza timeout. Niente
timer periodici: a riposo il demone non si sveglia mai (verificato dal test
`idle`: zero risvegli tra due interrogazioni). Nessuna allocazione dinamica
propria: tutte le tabelle hanno dimensione fissa (16 client, 64 app, 32
inibizioni, 33 manopole di spinta).

```
 evdev "Elan Touchscreen" ─┐
 timerfd (spinta, freezer) ─┤          ┌─ scaling_min_freq di ogni policy
 inotify (/dev/input, app.slice) ─┼─ epoll ─┼─ cpu.uclamp.min (facoltativo)
 socket unix /run/flo-sessiond.sock ─┤          └─ cgroup.freeze delle app
 signalfd (TERM, INT) ─┘
```

### Spinta al tocco

Macchina a due stati.

- **A riposo**: il descrittore evdev è in epoll per `EPOLLIN`, nessun timer.
- **In spinta**: al primo evento leggibile il demone legge i valori correnti,
  li registra nel file di stato, scrive `boost_freq_khz` in
  `scaling_min_freq` di ogni policy, **toglie l'evdev da epoll** (maschera 0:
  arriva solo la disconnessione) e arma un timerfd alla scadenza. Finché il
  dito resta giù il demone si sveglia una volta per periodo di tenuta, non una
  volta per fotogramma a 100 Hz: allo scadere svuota la coda evdev e, se sono
  arrivati eventi, sposta la scadenza a *ultimo evento + tenuta* e riarma.
  Quando un intero periodo passa senza eventi ripristina i valori originali e
  rimette l'evdev in epoll.

Misurato nel test `boost_streaming`: 60 fotogrammi (240 eventi) in 0,6 s
costano 1 risveglio da input, 2 da timer e una sola scrittura per policy.

Scelte:

- **Tenuta 150 ms** (`boost_hold_ms`). Il segnale di carico PELT ha
  semivita 32 ms: dopo 150 ms (4,7 semivite) schedutil vede già il 96 % del
  carico reale e il pavimento non serve più; sono anche 9 fotogrammi a 60 Hz,
  cioè la risposta al tocco e l'avvio dell'animazione. Più lungo costa
  batteria senza guadagno, più corto (i 40–80 ms di Android) lascia scoperto
  l'inizio dell'animazione perché qui manca la spinta separata all'avvio
  delle app; per quella c'è il comando `boost <ms>`.
- **La tenuta conta dall'ultimo evento, non da quando il demone se ne
  accorge**: il demone chiede a evdev timbri `CLOCK_MONOTONIC`
  (`EVIOCSCLOCKID`) e usa quello dell'ultimo evento. Se il dispositivo non lo
  consente usa l'ora di arrivo (rilascio fino a una tenuta più tardi).
- **Qualsiasi evento conta**, anche il sollevamento del dito: il tocco breve
  agisce al rilascio, ed è lì che serve la CPU.
- **Valore originale letto a ogni spinta**, non all'avvio, così un pavimento
  cambiato da altri (termica, utente) viene rispettato. Una policy che è già
  a `boost_freq_khz` o sopra non viene toccata.
- **Ripristino incondizionato**: al rilascio non si rilegge il valore, perché
  il kernel può averlo limitato (`scaling_max_freq` termico) e un confronto
  lascerebbe il pavimento alzato.
- **CPU fuori linea**: se la riscrittura fallisce (su un kernel vero `EBUSY`,
  il kernel conserva il nostro pavimento per quando la CPU torna) la policy
  resta "in sospeso" e viene riprovata dopo 1, 2, 4 … 64 s. È l'unico timer
  ricorrente ed esiste solo in quello stato anomalo. Le policy vengono
  rielencate a ogni rilascio, mai sul percorso critico.
- **Dispositivo che sparisce**: descrittore chiuso, watch inotify sulla
  directory finché il nodo ricompare, poi il watch viene tolto.
- **Modo uclamp** (`boost_mode = uclamp` o `both`): invece del pavimento di
  frequenza alza `cpu.uclamp.min` di un cgroup (`uclamp_cgroup`). Agisce solo
  quando girano i task di quel cgroup, quindi costa meno; richiede il
  controller `cpu` abilitato lì. Da confrontare sul tablet.

Ripristino in uscita:

| Caso | Meccanismo |
|---|---|
| `SIGTERM`, `SIGINT` | uscita ordinata: ripristino, scongelamento, socket rimosso |
| `SIGSEGV`, `SIGBUS`, `SIGFPE`, `SIGILL`, `SIGABRT` | gestore su pila alternativa, solo `openat`/`write`/`close` su tabelle statiche, poi il segnale viene rilanciato (il core dump resta) |
| `SIGKILL`, OOM, spegnimento | file di stato `/run/flo-sessiond/state`, scritto *prima* di toccare sysfs: l'avvio successivo ripristina |

### Freezer

Un client (la shell) possiede la politica e dichiara quali cgroup sono in
primo piano. Ogni altra app sotto `freezer_root` viene congelata
(`cgroup.freeze = 1`) dopo `freezer_grace_ms` (10 s) in background. Il cambio
di primo piano scongela **prima di rispondere `OK`**.

Che cosa è un'app: solo i figli diretti di `freezer_root` il cui nome
corrisponde a `freezer_match` (predefinito `app-*.scope app-*.service`).
Conta perché in `app.slice` finiscono anche i servizi utente senza `Slice=`
(`pipewire.service`, portali): non corrispondendo, non vengono mai toccati.
Dal nome si ricava l'id desktop secondo la convenzione systemd
(`app-<id>-<casuale>.scope`, `app-<id>@<istanza>.service`, con `\x2d`
decodificato) e lo si confronta con `freezer_deny` (vince sempre) e
`freezer_allow` (se non vuota, solo quelle).

Tutto si scongela (*fail-open*) quando: il proprietario si disconnette, la
politica viene spenta, lo schermo si blocca (`lock on`), il demone esce o va
in crash, e di nuovo all'avvio successivo (scansione della radice).

Le app nuove o terminate sono viste con inotify sulla radice; la radice viene
riaperta a ogni scansione perché systemd rimuove `app.slice` quando l'ultima
app esce.

### Sicurezza dei percorsi

I percorsi dei client passano un controllo sintattico (relativi, ASCII
stampabile senza spazi, nessun componente vuoto, `.` o `..`, al più 4
componenti) e poi ogni accesso avviene **dal descrittore della radice, un
componente alla volta con `O_NOFOLLOW`**, mai componendo stringhe. Un
collegamento simbolico dentro la radice non viene seguito, né come directory
né come `cgroup.freeze`. Il demone non crea mai file.

## Protocollo

Socket unix di tipo stream. Un comando per riga, terminato da `\n`. Solo ASCII
stampabile (0x20–0x7E): NUL, tab, CR o byte ≥ 0x80 chiudono la connessione.
Riga massima 512 byte compreso `\n`; oltre: `ERR line-too-long` e chiusura.
Ogni comando riceve zero o più righe di dati e poi **una** riga che inizia
con `OK` o `ERR <codice> <testo>`. I comandi si possono accodare.

**Lo stato appartiene alla connessione**: proprietà della politica, primo
piano e inibizioni spariscono quando il client si disconnette.

| Comando | Risposta | Note |
|---|---|---|
| `ping` | `OK` | |
| `version` | `OK flo-sessiond <versione> protocol 1` | |
| `status` | righe `chiave=valore`, poi `OK` | contatori, app, inibizioni |
| `boost [<ms>]` | `OK <ms applicati>` | senza argomento: `boost_hold_ms`; limitato a `boost_request_max_ms` |
| `freeze-policy on` | `OK` | la connessione diventa proprietaria; `ERR busy` se lo è un'altra |
| `freeze-policy off` | `OK` | chiunque: scongela tutto e libera la proprietà |
| `foreground <percorso>…` | `OK` | solo proprietario; da 1 a 4 percorsi relativi a `freezer_root`; il cgroup può non esistere ancora |
| `foreground -` | `OK` | nessuna app in primo piano (schermata iniziale) |
| `lock on\|off` | `OK` | solo proprietario; con `on` tutto scongelato e niente congelamenti |
| `inhibit <percorso> <motivo>` | `OK <token>` | chiunque; l'app resta scongelata; il motivo è testo libero fino a fine riga |
| `uninhibit <token>` | `OK` | valido solo sulla connessione che l'ha ottenuto |
| `thaw <percorso>` | `OK` | scongela subito un'app; la grazia riparte |
| `thaw-all` | `OK <quante>` | chiunque; scongela tutto; le grazie ripartono |

Di un percorso con più componenti conta il primo (l'unità figlia diretta
della radice).

Codici d'errore: `syntax`, `unknown-command`, `invalid-path`, `invalid-input`,
`line-too-long`, `not-owner`, `busy`, `disabled`, `limit`, `no-such-token`,
`not-found`, `failed`.

Limiti: 16 connessioni (se sono tutte occupate viene chiusa la più vecchia
che non detiene nulla; se tutte detengono qualcosa la nuova riceve `ERR busy`),
8 inibizioni per connessione, 32 in tutto, 64 app seguite (le eccedenti non
vengono congelate).

### floctl

```
floctl [-s SOCKET] COMANDO [ARG…]        # un comando, una connessione
floctl inhibit PERCORSO MOTIVO… [-- PROGRAMMA ARG…]
floctl -i                                 # comandi da stdin, una connessione
```

Esce con 0 (`OK`), 1 (`ERR`), 2 (uso o connessione). `inhibit` tiene aperta
la connessione finché il programma termina (e ne restituisce l'esito) o,
senza programma, finché `floctl` viene interrotto. `-i` serve per provare a
mano i comandi che richiedono la proprietà. Il socket si può dare anche con
`FLO_SESSIOND_SOCKET`.

## Configurazione

`/etc/flo-sessiond.conf`, righe `chiave = valore`, `#` per i commenti. Chiave
sconosciuta o valore non valido: il demone non parte. Il file può mancare.
`flo-sessiond -t [-c FILE]` controlla e stampa la configurazione effettiva;
`-o chiave=valore` sovrascrive una chiave (usato dai test).

| Chiave | Predefinito | Significato |
|---|---|---|
| `socket_path` | `/run/flo-sessiond.sock` | ignorato con l'attivazione via socket |
| `socket_group` | `flo-session` | nome o gid; vuoto: non cambiare gruppo |
| `socket_mode` | `0660` | |
| `state_file` | `/run/flo-sessiond/state` | vuoto: nessun recupero dopo `SIGKILL` |
| `log_level` | `info` | `error`, `warning`, `info`, `debug` |
| `boost_enabled` | `yes` | |
| `boost_mode` | `freq` | `freq`, `uclamp`, `both` |
| `boost_freq_khz` | `1026000` | |
| `boost_hold_ms` | `150` | 10–10000 |
| `boost_request_max_ms` | `3000` | tetto per `boost <ms>` |
| `cpufreq_root` | `/sys/devices/system/cpu/cpufreq` | |
| `uclamp_cgroup` | vuoto | directory con `cpu.uclamp.min` |
| `uclamp_min` | `68` | percentuale (≈ 1026/1512) |
| `input_device` | `auto` | `auto` o percorso del nodo |
| `input_dir` | `/dev/input` | |
| `input_name` | `Elan Touchscreen` | glob sul nome evdev |
| `input_timestamps` | `auto` | `auto`, `trust`, `ignore` |
| `freezer_enabled` | `yes` | |
| `freezer_root` | `/sys/fs/cgroup/user.slice/user-10000.slice/user@10000.service/app.slice` | |
| `freezer_grace_ms` | `10000` | |
| `freezer_match` | `app-*.scope app-*.service` | glob sui nomi delle unità |
| `freezer_allow` | vuoto | glob su id desktop o nome unità |
| `freezer_deny` | shell, compositore, portali, pipewire, tastiera, dbus, polkit, `xdg-*` | vedi `data/flo-sessiond.conf` |

## Modello di sicurezza

Il demone gira come root solo perché deve scrivere sysfs e cgroupfs. Che cosa
serve davvero:

- **cpufreq**: `scaling_min_freq` è `root:root 0644` e il kernel non controlla
  capability: basta essere il *proprietario*. Nessuna capability.
- **evdev**: `root:input 0660`, stessa cosa.
- **cgroup.freeze** sotto `user@UID.service`: il sottoalbero è delegato e i
  file appartengono all'utente. Root senza `CAP_DAC_OVERRIDE` non può
  scriverli: è **l'unica capability** tenuta. Senza freezer si può togliere
  (`CapabilityBoundingSet=` vuoto in un drop-in).
- **socket**: lo crea systemd (`flo-sessiond.socket`, `root:flo-session
  0660`), quindi il demone non scrive in `/run` né usa `chown`.

Unità (`data/flo-sessiond.service.in`): `ProtectSystem=strict`,
`ProtectKernelTunables=yes` con `ReadWritePaths=` limitato a
`/sys/devices/system/cpu/cpufreq` e `/sys/fs/cgroup/user.slice`,
`DevicePolicy=closed` + `DeviceAllow=char-input r` (`PrivateDevices`
nasconderebbe `/dev/input`), `NoNewPrivileges`, `PrivateNetwork`,
`RestrictAddressFamilies=AF_UNIX`, `SystemCallFilter=@system-service` meno
`@privileged @resources`, `MemoryDenyWriteExecute`, `ProtectHome`,
`PrivateTmp`, `MemoryMax=16M`, `TasksMax=4`. `ProtectControlGroups` resta
`no` perché renderebbe cgroupfs in sola lettura. `CAP_DAC_OVERRIDE` è meno
grave di quanto sembra: i montaggi in sola lettura valgono anche per lei.

Minacce considerate:

| Minaccia | Risposta |
|---|---|
| Client che esce dalla radice (`..`, assoluti, symlink) | controllo sintattico + `openat` per componente con `O_NOFOLLOW`; provato in `proto_negative` |
| Input malformato, righe infinite, NUL | buffer fisso di 512 byte, connessione chiusa; nessuna allocazione |
| Client che congela app altrui | serve il gruppo `flo-session`; solo il proprietario guida la politica; scongelare è sempre permesso a tutti |
| Membro del gruppo che esaurisce le connessioni | la più vecchia senza stato viene espulsa; il proprietario mai |
| Membro del gruppo che tiene la spinta o un'inibizione all'infinito | possibile: costa batteria, non integrità. `status` mostra chi (id connessione) e perché |
| File di stato manomesso | accettate solo le righe i cui percorsi sono manopole della configurazione corrente e i cui valori sono numeri validi; il file è `root 0600` in una directory `0700` |
| Shell bloccata o morta con app congelate | la disconnessione scongela tutto; se la shell resta viva ma ferma, le app restano congelate: `floctl thaw-all` |
| Demone ucciso | `Restart=always`; l'avvio ripristina frequenze e scongela |

Chi è nel gruppo `flo-session` può rallentare (congelare) le app
dell'utente e sprecare batteria; non può leggere né scrivere altro. Va
dato solo all'utente della sessione.

## Come lo usa la shell

1. Avvia le app in uno scope proprio:
   `systemd-run --user --scope --slice=app.slice --unit=app-<id>-<casuale> …`
   e ricorda il nome dell'unità.
2. All'avvio apre il socket e manda `freeze-policy on`, poi tiene la
   connessione aperta per tutta la vita della shell.
3. A ogni cambio di finestra attiva manda `foreground <unità>` (o più unità
   in schermo diviso, o `-` sulla schermata iniziale). Lo manda **prima** di
   mostrare l'app: la risposta `OK` arriva a scongelamento fatto.
4. Al blocco dello schermo `lock on`, allo sblocco `lock off`.
5. Lancio di un'app o transizione pesante: `boost 500`.
6. Chiusura di un'app in background: `thaw <unità>` prima di
   `systemctl --user stop`, altrimenti systemd aspetta il timeout prima di
   uccidere un processo che non può rispondere a `SIGTERM`.
7. Audio e download (rischio R6): la shell prende `inhibit <unità> <motivo>`
   quando MPRIS segnala riproduzione o PipeWire mostra un flusso attivo
   dell'app, e lo rilascia quando finisce. Un'app che sa di lavorare in
   background può avvolgersi da sola: `floctl inhibit <unità> download -- cmd`.
8. Se la connessione cade la shell riconnette e ripete i passi 2–3; nel
   frattempo tutto è scongelato.

Da verificare con il compositore: un client Wayland congelato non risponde ai
ping; su Hyprland va spento l'avviso di app bloccata
(`misc:enable_anr_dialog`).

## Compilazione e test

```sh
meson setup build sessiond && meson compile -C build && meson test -C build
meson setup build-asan sessiond -Db_sanitize=address,undefined -Db_lundef=false
meson test -C build-asan
```

25 test: 1 unitario (134 controlli sulle funzioni pure) e 24 di integrazione
che avviano il vero binario contro alberi cpufreq e cgroup finti in una
directory temporanea, con una FIFO al posto del nodo evdev. Non servono root
né dispositivi reali. `cpu_offline` viene saltato se eseguito come root.
Il test `crash_restore` manda `SIGSEGV` al demone: imposta `RLIMIT_CORE=1`,
quindi non lascia core dump (resta una riga nel log del kernel).

Opzioni di installazione: `-Dsocket_group=`, `-Dsystemdsystemunitdir=`,
`-Dinstall_config=false`.

## Prova sul tablet

Da eseguire come root via ssh, con la sessione utente (uid 10000) attiva.

### 1. Installazione

```sh
# compilato nel chroot armv7 di pmbootstrap o sul tablet (apk add meson gcc musl-dev linux-headers)
meson setup build sessiond --prefix=/usr --buildtype=release && meson install -C build
systemd-sysusers && adduser user flo-session       # poi rientrare nella sessione
flo-sessiond -t                                    # stampa la configurazione
systemctl daemon-reload && systemctl enable --now flo-sessiond.socket flo-sessiond.service
```

Atteso: `systemctl status flo-sessiond` attivo, nel journal
`input: using /dev/input/eventN (event timestamps)` e `ready`.
Se compare `arrival timestamps` il driver rifiuta `EVIOCSCLOCKID`: funziona
lo stesso, con rilascio meno preciso.

### 2. Sandbox

```sh
journalctl -u flo-sessiond -b | grep -Ei 'read-only|denied|cannot'
systemd-analyze security flo-sessiond | tail -1
floctl boost 2000; cat /sys/devices/system/cpu/cpufreq/policy*/scaling_min_freq
```

Atteso: nessun errore; quattro righe `1026000` (meno le CPU fuori linea) che
tornano a `384000` dopo 2 s. Se restano a `384000` e il journal con
`log_level = debug` mostra `Read-only file system`, `ReadWritePaths` non
prevale su `ProtectKernelTunables` con questa versione di systemd: creare un
drop-in con `ProtectKernelTunables=no` e segnalarlo qui. **Questo punto non è
verificabile sul portatile.**

### 3. Spinta al tocco

```sh
watch -n 0.1 'cat /sys/devices/system/cpu/cpufreq/policy*/scaling_min_freq'
```

Atteso: `384000` a riposo; `1026000` appena si tocca lo schermo e per tutto
il tempo in cui il dito si muove; ritorno a `384000` circa 150 ms dopo aver
sollevato il dito. Poi:

```sh
floctl status | grep -E 'boost\.|input\.'
```

Dopo uno scorrimento lungo di 5 s: `boost.count` +1, `boost.input_wakeups`
+1, `boost.timer_wakeups` circa +35 (non +500).

### 4. La spinta arriva entro un fotogramma?

Con ftrace si misura dal gestore dell'interruzione del touch al cambio di
limite e di frequenza:

```sh
cd /sys/kernel/tracing
echo 0 > tracing_on; echo > trace
echo 1 > events/power/cpu_frequency_limits/enable
echo 1 > events/power/cpu_frequency/enable
grep -i elan /proc/interrupts                      # numero N dell'IRQ
echo 'irq == N' > events/irq/irq_handler_entry/filter
echo 1 > events/irq/irq_handler_entry/enable
echo 1 > tracing_on; sleep 5; echo 0 > tracing_on  # un tocco singolo nei 5 s
grep -m1 -A12 irq_handler_entry trace
```

Atteso, dalla prima riga `irq_handler_entry` (T0):

- `cpu_frequency_limits: min=1026000 …` per ogni policy entro **2 ms** da T0;
- `cpu_frequency: state=1026000` (o superiore) per le CPU attive entro
  **16,6 ms** da T0, cioè un fotogramma a 60 Hz. L'evento manca per una CPU
  già a quella frequenza o inattiva: è normale.

Se il kernel non ha ftrace, la sola latenza del demone:

```sh
strace -r -p "$(pidof flo-sessiond)" -e trace=epoll_wait,read,openat,write 2>&1 | head -40
```

Atteso: dal ritorno di `epoll_wait` all'ultima `write` su `scaling_min_freq`
meno di 1 ms.

Costo a riposo: `floctl status | grep loop.wakeups` due volte a un minuto di
distanza senza toccare nulla: differenza 3 (connessione, comando e chiusura
di `floctl`), comunque non proporzionale al tempo trascorso.
`top -p "$(pidof flo-sessiond)"`: 0,0 %.

### 5. Freezer

Come utente della sessione, con due app avviate negli scope:

```sh
ls /sys/fs/cgroup/user.slice/user-10000.slice/user@10000.service/app.slice/
floctl -i <<'EOF'
freeze-policy on
foreground app-<A>.scope
status
EOF
```

`floctl -i` esce a fine input e quindi rilascia la politica; per tenerla,
usare un terminale interattivo (`floctl -i` e digitare). Con la politica
tenuta, da un altro terminale:

```sh
cat …/app.slice/app-<B>.scope/cgroup.freeze       # 0, poi 1 dopo 10 s
grep frozen …/app.slice/app-<B>.scope/cgroup.events
```

Atteso: `B` passa a `1` dopo 10 s, `cgroup.events` dice `frozen 1` e i suoi
processi restano a 0 % di CPU. `foreground app-<B>.scope`:
`B` torna a `0` subito, `A` si congela dopo 10 s. `pipewire.service`, la
shell e la tastiera restano sempre a `0`.

Fail-open: chiudere il `floctl -i` che tiene la politica (Ctrl-D): tutte le
app tornano a `0` subito. Lo stesso con `systemctl restart flo-sessiond` e
con `kill -9 "$(pidof flo-sessiond)"` (entro 1 s, al riavvio).

Inibizione: con musica in riproduzione in `B`,
`floctl inhibit app-<B>.scope musica` da un terzo terminale: `B` resta a `0`
e l'audio continua oltre i 10 s; Ctrl-C su quel `floctl` e dopo 10 s l'audio
si ferma. Riportando `B` in primo piano l'audio deve riprendere senza
errori: è la verifica del rischio R6.

### 6. Da annotare in `MEASUREMENTS.md`

Latenza T0→limite e T0→frequenza (mediana di 10 tocchi), risvegli durante uno
scorrimento di 5 s, consumo a riposo con e senza demone, confronto
`boost_mode = freq` / `uclamp`, memoria residente del demone.

## Limiti noti

- Compilato e provato solo su x86_64 (gcc e clang). Per armv7 è stato fatto
  solo un controllo sintattico per un bersaglio a 32 bit con `time_t` a 64
  bit, dove `struct input_event` è di 16 byte; il demone usa
  `input_event_sec`/`input_event_usec` e `sizeof`, senza ipotesi sul formato.
- Un solo utente: `freezer_root` contiene l'uid.
- Un solo dispositivo di input.
- Il demone scrive `cgroup.freeze` direttamente, senza passare da systemd:
  `systemctl --user status` non mostra le unità come congelate.
- Una spinta dura finché arrivano eventi: un pannello che genera tocchi
  fantasma tiene il pavimento alzato.
- `SIGHUP` non ricarica la configurazione: riavviare il servizio.
- Nessun watchdog systemd (richiederebbe un timer periodico).
- Priorità di memoria e rotazione da sensore (citate nel piano) non sono in
  questo demone.
