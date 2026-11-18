# flo-shell — prove sul tablet

Elenco di ciò che va provato a mano sul Nexus 7, perché sul portatile è
stato verificato solo in un compositore annidato, senza tocco (IPC e
catture dello schermo) e con controparti finte. Ogni voce dice cosa toccare
e cosa deve succedere. Architettura e variabili sono in
[ARCHITECTURE.md](ARCHITECTURE.md).

Legenda: **[mai provato]** = nessuna esecuzione reale possibile sul
portatile; **[solo IPC]** = la logica è stata eseguita, il gesto no.

## 0. Prima di cominciare

1. Tenere aperta una sessione SSH: è la via d'uscita se lo schermo resta
   bloccato o nero.
2. Installare: `make install DESTDIR=… PREFIX=/usr` (pacchetto) e
   controllare che esistano `/usr/bin/flo-shell`, `/usr/bin/flo-session`,
   `/usr/share/wayland-sessions/flo-shell.desktop`, `/etc/pam.d/flo-shell`.
3. **Prima sessione con autenticazione finta.** Avviare con
   `FLO_AUTH=dry flo-session` (da una console o da SSH con il seat giusto).
   Il blocco accetta `1234` e mostra la scritta gialla "Prova:
   autenticazione finta". Passare a PAM solo dopo aver visto funzionare il
   tastierino al tocco (sezione 3).
4. Vie d'uscita via SSH:
   - shell bloccata o da riavviare: `pkill -x quickshell` (`flo-shell run`
     la riavvia; se era bloccata torna bloccata);
   - blocco impossibile da togliere (PAM non configurato): terminare la
     sessione, ad esempio `doas rc-service greetd restart`;
   - schermo nero: premere il tasto di accensione; altrimenti
     `hyprctl --instance 0 dispatch dpms on`.
5. Per prove lunghe o automatiche via SSH: `flo-shell msg idleInhibit true`
   evita il blocco e lo spegnimento per inattività (non sblocca nulla);
   `flo-shell msg idleInhibit false` alla fine. Lo stato è in
   `flo-shell msg state` (`idleInhibited`).

## 1. Avvio della sessione **[mai provato]**

| Cosa fare | Cosa deve succedere |
|---|---|
| Avviare `flo-session` | Hyprland parte senza riquadro di errore di configurazione in alto; compaiono barra di stato e barra home; nessuna animazione |
| `hyprctl monitors` | `DSI-1` a 1200×1920, scala 2 |
| `hyprctl getoption general:layout` | `monocle`. Se Hyprland 0.54.3 non lo conosce (riquadro rosso di errore): mettere `layout = dwindle` in `~/.config/flo-shell/hyprland.conf` e segnalarlo; le finestre si affiancheranno invece di sovrapporsi |
| Aprire due applicazioni dal launcher | ognuna occupa tutto lo spazio tra le barre; la seconda copre la prima |
| `flo-shell msg state` da SSH | JSON con `"compositor":"hyprland"`, `"rotationSupported":true` |
| `pkill -x quickshell` | la shell ricompare entro un paio di secondi |
| Modificare un file della shell mentre gira (ricaricamento a caldo) | nessuna riga `Unable to assign [undefined]` da `Clock.qml` |
| Log: `journalctl`/output di greetd | nessuna riga `WARN`/`ERROR` di QML |

## 2. Gesti sulle barre **[solo IPC]**

| Cosa fare | Cosa deve succedere |
|---|---|
| Tocco sulla barra home | si apre il launcher; secondo tocco: si chiude |
| Scorrimento corto verso l'alto dalla barra home (1–2 cm) | launcher |
| Scorrimento lungo verso l'alto (oltre 3 cm), poi rilascio | panoramica delle finestre. Se si apre sempre il launcher, il tocco non viene seguito fuori dalla striscia: annotarlo |
| Scorrimento verso il basso dalla barra di stato | impostazioni rapide |
| Scorrimento con un dito dal bordo sinistro o destro dello schermo | cambio di area di lavoro che segue il dito (gesto di Hyprland, `workspace_swipe_touch`) |
| Dopo ogni gesto, toccare un altro punto | il tocco successivo non viene "mangiato" |

## 3. Blocco schermo **[solo IPC e tastiera virtuale]**

Con `FLO_AUTH=dry` (codice `1234`):

| Cosa fare | Cosa deve succedere |
|---|---|
| Impostazioni rapide → Alimentazione → Blocca | schermata di blocco: ora, data, batteria in alto a destra; nessuna barra visibile |
| Inviare una notifica prima di bloccare (`notify-send`) | in alto a sinistra "1 notifica", senza testo della notifica |
| Toccare `9` `9` e il tasto di conferma | pallini che compaiono a ogni tocco, poi "Codice errato" in rosso e campo vuoto |
| Toccare `1` `2` `3` `4` e conferma | la sessione si sblocca e torna com'era |
| Tasto ⌫ | toglie un pallino |
| Tasto `abc` | compare la tastiera QWERTY a tutta larghezza; l'occhio mostra il testo; `123` in basso torna al tastierino |
| Maiuscole, `123`, `#+=` sulla tastiera | cambiano i tasti; ogni tasto è largo almeno quanto un dito (60 px in verticale) |
| Ruotare (sezione 6) e bloccare in orizzontale | orologio a sinistra, tastierino a destra; con `abc` la tastiera occupa tutta la larghezza |
| Tasto di accensione, pressione breve, da sbloccato | blocca e spegne il pannello |
| Tasto di accensione, pressione breve, da bloccato | accende il pannello; un'altra pressione lo spegne |
| Tasto di accensione tenuto premuto, da sbloccato | menu di alimentazione, e al rilascio **non** si blocca |
| Lasciare il tablet fermo 2 minuti | si blocca e il pannello si spegne (non durante un video) |
| Da bloccato: `pkill -x quickshell` via SSH | schermo del compositore "lock morto" per un istante, poi di nuovo la schermata di blocco; mai il contenuto della sessione |
| Sospendi dal menu di alimentazione | si blocca, poi sospende; al risveglio c'è la schermata di blocco con l'ora giusta |

Poi con PAM (senza `FLO_AUTH`) **[mai provato con il PAM vero]**:

| Cosa fare | Cosa deve succedere |
|---|---|
| Bloccare, inserire il PIN/password dell'utente | sblocca |
| Inserire un codice sbagliato | "Codice errato" dopo il ritardo di PAM (circa 2 s) |
| Se resta su "Errore di autenticazione" | manca `/etc/pam.d/flo-shell`, o `base-auth` non esiste su questo sistema, o `unix_chkpwd` non può leggere la password: vedere `journalctl -t quickshell` e uscire con la via d'uscita della sezione 0 |

## 4. Greeter **[provato solo con greetd finto]**

Configurare greetd come in `/usr/share/doc/flo-shell/greetd-config.toml`
tenendo una seconda via di accesso (SSH).

| Cosa fare | Cosa deve succedere |
|---|---|
| Riavviare greetd | Hyprland minimo, poi la schermata di accesso: ora, utente evidenziato, tastierino |
| Schermata di accesso con Hyprland installato | **nessuna** scelta di sessione: `hyprland.desktop` e `hyprland-uwsm.desktop` non compaiono, c'è solo flo-shell e quindi niente pulsanti |
| `FLO_GREETER_SESSIONS=flo-shell,phosh` davanti al comando del greeter in `/etc/greetd/config.toml`, riavviare greetd | compaiono i pulsanti flo-shell e Phosh; il tocco cambia la selezione. Con `*` compaiono tutte le sessioni tranne quelle con `Hidden=true`/`NoDisplay=true` |
| Più utenti | compaiono come pulsanti; il tocco cambia la selezione |
| Codice sbagliato | "Codice errato", si può riprovare |
| Codice giusto | "Avvio della sessione…", il greeter sparisce e parte la sessione scelta |
| Schermo nero al posto del greeter | l'utente `greetd` non ha accesso a video/input/seat: controllare gruppi e seatd/elogind; log in `/var/log/greetd*` o `journalctl -u greetd` |
| Nel log di Quickshell compare `Received unexpected greetd response` dopo un codice sbagliato | visto anche con il greetd finto: viene da Quickshell (risposta al `cancel_session`), non blocca nulla. Annotare se succede con greetd vero |

## 5. Panoramica **[solo IPC; tocco e trascinamento mai provati]**

| Cosa fare | Cosa deve succedere |
|---|---|
| Aprire 3 applicazioni, scorrimento lungo dalla barra home | schede con icona e titolo, la finestra attiva al centro con bordo azzurro |
| Scorrere la striscia in orizzontale | scorre fluida; le schede non si spostano in verticale |
| Tocco su una scheda | quella finestra va in primo piano, la panoramica si chiude |
| Trascinare una scheda verso l'alto per più di 2 cm e rilasciare | la scheda vola via e la finestra si chiude |
| Trascinarla poco e rilasciare | torna al suo posto |
| Tocco sulla X di una scheda | chiude quella finestra |
| "Chiudi tutto" | chiude tutte le finestre; resta "Nessuna app aperta" |
| Tocco sulla barra home | chiude la panoramica |
| `FLO_THUMBNAILS=1` nell'ambiente della sessione, riaprire la panoramica | anteprime sfocate ma riconoscibili delle finestre, anche di quelle coperte. Se la shell si blocca, la GPU va in errore (`dmesg`) o le schede restano grigie: lasciare le anteprime spente e annotarlo (rischio R1) |

## 6. Rotazione **[provata annidata, senza tocco]**

| Cosa fare | Cosa deve succedere |
|---|---|
| Impostazioni rapide → Ruota | lo schermo ruota di 90°; le barre si ridispongono; le impostazioni rapide diventano il pannello laterale a destra |
| Toccare un pulsante dopo la rotazione | il tocco cade dove si vede il pulsante (trasformazione del touch). Se il tocco è ruotato rispetto all'immagine: annotare e provare `hyprctl keyword input:touchdevice:transform N` |
| Ruota altre tre volte | 180°, 270°, di nuovo 0°; il riquadro mostra "Verticale"/"Orizzontale" e i gradi oltre 90 |
| `flo-shell msg rotate 270` | orientamento scelto direttamente |
| Launcher, panoramica, blocco in orizzontale | 6 colonne nel launcher; tastierino a destra nel blocco |

## 7. Tastiera a schermo **[provata solo con un finto wvkbd]**

Serve il pacchetto `wvkbd`.

| Cosa fare | Cosa deve succedere |
|---|---|
| Guardare l'angolo destro della barra home | icona della tastiera (assente se `wvkbd-mobintl` non è installato) |
| Toccarla | compare la tastiera sopra la barra home, opaca, con i colori della shell; l'applicazione si accorcia e non resta coperta |
| Toccarla di nuovo | la tastiera sparisce e l'applicazione riprende lo spazio |
| Scrivere in un'applicazione (terminale, browser) | i caratteri arrivano; layout internazionale con lettere accentate |
| Launcher → toccare il campo di ricerca | la tastiera compare e il campo resta visibile sopra di essa. Se resta coperto: annotare (vedi "Limiti noti") |
| Chiudere il launcher | la tastiera aperta dal campo di ricerca si chiude |
| Ruotare con la tastiera aperta | la tastiera passa all'altezza orizzontale (220 px) |
| Bloccare con la tastiera aperta | la tastiera si chiude; nel blocco si usa quella interna |
| `pgrep -c wvkbd-mobintl` dopo vari usi e dopo `pkill -x quickshell` | sempre 0 o 1, mai due tastiere |

## 8. Tasti fisici **[mai provati]**

| Cosa fare | Cosa deve succedere |
|---|---|
| Volume su / giù | il volume cambia del 5 % e compare l'OSD; tenendo premuto ripete |
| Volume da bloccato | funziona ugualmente |
| `wev` o `hyprctl binds` | i tasti arrivano come `XF86PowerOff`, `XF86AudioRaiseVolume`, `XF86AudioLowerVolume`; se i nomi sono diversi correggere i `bind` |
| Pressione breve del tasto di accensione | **non** deve spegnere il tablet: se lo fa, l'inibitore `handle-power-key` di `flo-session` non ha effetto e va impostato `HandlePowerKey=ignore` in elogind |

## 9. Indietro **[mai provato: nel compositore annidato non c'è tastiera]**

| Cosa fare | Cosa deve succedere |
|---|---|
| Aprire un'applicazione GTK4/libadwaita con navigazione (Impostazioni, File), entrare in una sottopagina, `flo-shell msg back` | torna alla pagina precedente |
| Lo stesso in un browser | pagina precedente |
| `back` con un pannello della shell aperto | chiude il pannello e non invia nulla all'applicazione |
| Errore `sendshortcut: no kb` nel log | Hyprland non vede una tastiera: è ciò che succede nell'ambiente annidato; sul tablet i tasti fisici dovrebbero bastare, altrimenti annotarlo |

## 10. Lingua

| Cosa fare | Cosa deve succedere |
|---|---|
| Sistema in italiano (`LANG=it_IT.UTF-8`) | etichette in italiano e date come "dom 15 nov" |
| `FLO_LANG=en` nell'ambiente della sessione | tutto in inglese, date comprese |

## 11. Impostazioni rapide senza audio e Bluetooth

| Cosa fare | Cosa deve succedere |
|---|---|
| Aprire le impostazioni rapide (oggi il tablet non ha scheda audio né Bluetooth) | nessuna riga del volume, nessun riquadro Bluetooth: Wi-Fi, Ruota, Alimentazione e luminosità soltanto; nessuno spazio vuoto tra i controlli |
| `wpctl status` | conferma: nessun sink in "Sinks" |
| Collegare un adattatore Bluetooth USB o una scheda audio (quando ci sarà), con il pannello aperto | il riquadro o la riga compaiono senza riavviare la shell |

## 12. Congelamento delle app (flo-sessiond) **[provato sul portatile con un albero cgroup finto]**

Preparazione (vedi SESSIOND.md, "Prova sul tablet", passo 1):
`flo-sessiond.socket` abilitato, l'utente nel gruppo `flo-session` (poi
rientrare nella sessione), in `/etc/flo-sessiond.conf`
`freezer_enabled = yes` e `freezer_root` con l'uid dell'utente (predefinito
10000). Per non aspettare 10 s si può mettere `freezer_grace_ms = 3000` e
riavviare il servizio. `A=/sys/fs/cgroup/user.slice/user-10000.slice/user@10000.service/app.slice`.

| Cosa fare | Cosa deve succedere |
|---|---|
| `flo-shell msg state` | `"appScopes":true`, `"sessiond":{"connected":true,"policy":true,…}`. Se `connected` è `false`: `ls -l /run/flo-sessiond.sock` (gruppo `flo-session`), `id` (l'utente è nel gruppo?), log della shell (`flo-sessiond: not available …`) |
| Aprire due app dal launcher (es. terminale e Impostazioni) | `ls $A` mostra due `app-<id>-<casuale>.scope`; `"foreground"` nello stato è lo scope della seconda |
| Lasciare in primo piano la seconda per più della grazia | `cat $A/app-<prima>*/cgroup.freeze` dà `1`, `grep frozen $A/app-<prima>*/cgroup.events` dà `frozen 1`; `top`: la prima a 0 % |
| Tornare alla prima (panoramica o launcher) | si ridisegna subito e risponde al tocco; il suo `cgroup.freeze` torna `0` subito, quello della seconda va a `1` dopo la grazia |
| Nessun avviso "l'applicazione non risponde" di Hyprland sulla app congelata | (`misc:enable_anr_dialog = false`) |
| Panoramica: chiudere la scheda dell'app congelata | la finestra si chiude entro un secondo, lo scope sparisce da `$A` |
| Bloccare lo schermo | `floctl status \| grep freezer.locked` dà `1` e tutti i `cgroup.freeze` sono `0`; sbloccando si torna a congelare dopo la grazia |
| `systemctl restart flo-sessiond` | tutto scongelato; entro pochi secondi `state` torna `connected`/`policy` `true` e il congelamento riprende |
| `pkill -x quickshell` | tutto scongelato subito (il demone perde il proprietario); la shell riavviata riprende la politica |
| App audio o download in background | viene congelata anche lei (nessuna inibizione automatica ancora): annotare quali app ne soffrono |
| `top` a schermo fermo | `quickshell` e `flo-sessiond` a 0 % anche con la politica attiva |

## 13. Agenti remoti (`flo-agents`) **[solo CLI finto in CI]**

Senza `flo-agents` sul PATH il launcher non mostra voci agente e il log
di Quickshell resta pulito. Con il CLI configurato:

| Cosa fare | Cosa deve succedere |
|---|---|
| `flo-agents list` stampa `claude` / `codex` / `grok` | all'apertura del launcher compaiono "Claude Code (remote)", "Codex (remote)", "Grok Build (remote)" con l'icona fulmine, senza loghi |
| Toccare una voce | si apre il terminale della sessione su `flo-agents launch <tool>` |
| Chiudere la sessione con successo (exit 0) | nessuna notifica |
| Far fallire il CLI (exit ≠ 0) | notifica titolo "Agent session dropped", corpo con lo strumento e il codice, senza host |
| `flo-agents` assente o lista vuota | nessuna voce agente |
| `top` a schermo fermo col launcher chiuso | nessun processo `flo-agents` o timer della shell |

Le prove automatiche sono `sh tests/test_flo_agents.sh` (CLI e `notify-send` finti).

## 14. Regole di progetto da ricontrollare a occhio

- Nessuna superficie traslucida, sfocata o con ombra; la striscia sopra la
  barra home e sotto la barra di stato è trasparente solo per ricevere il
  tocco.
- Le aperture di launcher, panoramica, impostazioni rapide e blocco non
  devono mostrare ridisposizioni durante l'animazione.
- A schermo fermo `top` non deve mostrare `quickshell` né `wvkbd` in
  attività.
