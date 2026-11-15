# flo-shell — architettura (Fasi 2 e 3)

Configurazione Quickshell in `shell/`, un solo processo. Avvio:
`quickshell -p shell/` (installata: `flo-shell run`). Il greeter è una
seconda configurazione, `greeter/`. Il piano resta in [PLAN.md](PLAN.md); le
prove da fare sul tablet sono in [TESTING.md](TESTING.md).

## Struttura dei file

```
shell/
  shell.qml            ingresso: barre, caricamento pigro dei pannelli, IPC
  Device.qml           costanti fisiche del tablet e orientamento corrente
  Theme.qml            colori, spaziature, bersagli tattili, durate
  I18n.qml             testi (italiano, inglese) e formato di date e ore
  services/            stato di sistema, tutti singleton a eventi
    Compositor.qml     UNICO punto di contatto con il compositore
    compositor/        HyprlandBackend.qml, WlrBackend.qml
    Network.qml        stato rete; network/NetworkingBackend.qml caricato a run time
    Audio.qml          volume (PipeWire)
    Brightness.qml     retroilluminazione (sysfs + brightnessctl o logind)
    Battery.qml        UPower
    Bt.qml             BlueZ
    Notifications.qml  server org.freedesktop.Notifications, storico, popup
    Apps.qml           indice delle applicazioni e ricerca
    Session.qml        blocco, tasto di accensione, inattività, spegni/riavvia/sospendi
    RotationLock.qml   rotazione manuale 0/90/180/270 tramite l'adattatore
    Keyboard.qml       tastiera a schermo (ponte verso wvkbd)
    Clock.qml          l'unico risveglio periodico (un tick al minuto)
    Ui.qml             stato dei pannelli e dell'OSD
  components/          Pressable, IconButton, LevelSlider, ToggleTile, Icon,
                       EdgeArea, KeyGrid (tastiera QWERTY interna)…
  bar/ home/ launcher/ quicksettings/ notifications/ osd/ power/
  overview/            Overview, WindowCard, Thumbnail
  lock/                Lock (sessione bloccata), LockScreen, AuthPad, Auth
    auth/              PamAuth, GreetdAuth, DryAuth
greeter/
  shell.qml, Greeter.qml   ingresso e schermata di accesso per greetd
  Device.qml Theme.qml I18n.qml components lock services
                       collegamenti simbolici verso ../shell
session/
  hyprland.conf        configurazione del tablet (sintassi classica)
  greeter-hyprland.conf  compositore minimo per il greeter
  flo-session.in       avvio della sessione → /usr/bin/flo-session
  flo-shell.in         avvio/IPC della shell → /usr/bin/flo-shell
  flo-shell.desktop    voce in /usr/share/wayland-sessions
  pam/flo-shell        servizio PAM del blocco schermo
  greetd/config.toml   esempio di configurazione di greetd
dev/
  run-nested.sh        esecuzione annidata per lo sviluppo
  hyprland-nested.conf / .lua   configurazione del compositore annidato
  pam-check.sh, fake-greetd.py, fake-wvkbd.sh   controparti finte per le prove
Makefile               install / uninstall / check
```

Superfici (tutte layer-shell, tutte opache tranne le due strisce tattili):

| Superficie | Livello | Note |
|---|---|---|
| Barra di stato | top | 30 px visibili e riservati, superficie di 48 px |
| Barra home | top | 20 px visibili e riservati, superficie di 48 px |
| Launcher, impostazioni rapide | overlay | create al primo uso, poi tenute in memoria |
| Menu di alimentazione | overlay | a tutto schermo, copre anche le barre |
| Panoramica | overlay | tra le due barre, creata al primo uso |
| Blocco schermo | ext-session-lock-v1 | non è layer-shell: copre tutto, creata al primo blocco |
| Tastiera (wvkbd) | top, processo esterno | riserva da sé la propria altezza |
| Popup notifiche | overlay | esiste solo finché c'è un popup |
| OSD | overlay | creato al primo uso |

Le superfici compaiono già opache; si anima solo il contenuto (traslazione e
opacità). Le dimensioni delle superfici cambiano a scatti, mai animate.

## Contratto dell'adattatore del compositore

Tutto il codice che dipende dal compositore sta in `services/Compositor.qml`
e in `services/compositor/`. Il resto della shell usa solo il singleton
`Compositor` e protocolli standard.

Scelta del backend: `hyprland` se è impostata `HYPRLAND_INSTANCE_SIGNATURE`,
altrimenti `wlr` (wlr-foreign-toplevel-management tramite `ToplevelManager`).
`FLO_COMPOSITOR=wlr|hyprland` forza la scelta. Se il backend Hyprland non si
carica si ripiega su `wlr`.

Un backend è un `QtObject` con:

| Membro | Significato |
|---|---|
| `windows` | lista di maniglie opache delle finestre |
| `activeWindow` | maniglia attiva o `null` |
| `workspaces` | `[{ id, name, active }]` (vuota su `wlr`) |
| `activeWorkspaceId` | `-1` se ignoto |
| `supportsWorkspaces` | `false` su `wlr` |
| `title(w)`, `appId(w)` | testo per l'interfaccia |
| `focus(w)`, `close(w)`, `focusWorkspace(id)` | azioni |
| `supportsBack`, `goBack()` | "indietro" all'applicazione attiva |
| `supportsAppSwitch`, `showAppSwitcher()` | selettore nativo del compositore (nessuno oggi) |
| `supportsRotation`, `transformOf(screen)`, `setTransform(screen, t)` | rotazione, `t` = 0..3 come `wl_output` |
| `supportsDisplayPower`, `setDisplayPower(on)` | pannello acceso/spento |
| `supportsThumbnails`, `captureSource(w)` | sorgente per `ScreencopyView` o `null` |

`Compositor` espone gli stessi dati più `windowTitle()`, `windowAppId()`,
`focusWindow()`, `closeWindow()`, `closeActiveWindow()`, `focusWorkspace()`,
`screenTransform()`, `setScreenTransform()`, `setDisplayPower()`,
`windowCaptureSource()`.

| Capacità | Hyprland | wlr |
|---|---|---|
| Rotazione | regola `monitor … ,transform,N` + `input:touchdevice:transform` | `wlr-randr --transform` se installato, altrimenti `supportsRotation = false`; il tocco segue solo se lo mappa il compositore |
| Indietro | `sendshortcut , XF86Back, activewindow` (solo configurazione classica) | no |
| Pannello | `dpms on/off` (solo configurazione classica) | no |
| Anteprime | `hyprland-toplevel-export-v1` | no |

**Panoramica.** `Compositor.showAppSwitcher()` usa il selettore del backend
se esiste; altrimenti emette `appSwitcherRequested`, a cui `shell.qml`
risponde aprendo o chiudendo `overview/Overview.qml`.

**Indietro.** `Compositor.goBack()` invia il tasto `XF86Back` alla finestra
attiva. È un tentativo: funziona con le applicazioni che gestiscono quel
tasto (GTK4/libadwaita per la navigazione, Qt come `Qt.Key_Back`, i
browser); le altre lo ignorano e la shell non può saperlo. `Ui.back()`
(IPC `back`) chiude prima un eventuale pannello della shell. Non esiste
ancora un gesto dal bordo: seguirebbe il dito, quindi spetta al compositore
(decisione 4 del piano).

Lo stato dei monitor per la rotazione viene letto con `hyprctl -j monitors`
(una volta all'avvio e dopo ogni cambio): gli oggetti monitor del modulo
Hyprland di Quickshell restavano vuoti per l'uscita headless usata nelle
prove.

Su Hyprland con configurazione Lua (portatile di sviluppo) i dispatcher sono
espressioni Lua: il backend sceglie la forma in base a `Hyprland.usingLua`.
"Indietro" e l'accensione del pannello hanno solo la forma classica.

## IPC

`flo-shell msg <funzione> [argomenti]`, cioè
`quickshell ipc -p shell call flo <funzione>`; pensato per i tasti fisici
legati nel compositore e per le prove:

| Funzione | Effetto |
|---|---|
| `home`, `launcher`, `quickSettings`, `powerMenu`, `closeAll` | pannelli |
| `overview` (o `appSwitcher`) | apre/chiude la panoramica |
| `back` | chiude un pannello, altrimenti `Compositor.goBack()` |
| `lock` | blocca la sessione |
| `powerKey` | pressione breve: blocca e spegne il pannello; da bloccato, accende/spegne il pannello |
| `powerKeyLong` | pressione lunga: menu di alimentazione (non da bloccato) |
| `rotate <gradi>`, `rotateNext` | rotazione a 0/90/180/270, o la successiva |
| `keyboard on|off|toggle` | tastiera a schermo |
| `workspace <id>` | area di lavoro |
| `volume <±percento>`, `mute`, `brightness <±percento>`, `osd <volume\|brightness>` | livelli |
| `state` | stato in JSON |
| `authInput <testo\|ENTER\|abc>` | solo sviluppo (`FLO_DEV_INPUT=1`): scrive nel tastierino del blocco |

Il greeter ha un proprio bersaglio `flo` con `state`, `user <nome>`,
`session <indice>`, `authInput`.

I tasti volume possono modificare il volume con qualsiasi mezzo (wpctl, IPC
qui sopra): l'OSD compare per l'evento di PipeWire, non per il tasto.

## Blocco schermo

`lock/Lock.qml` è un `WlSessionLock` (`ext-session-lock-v1`) con una
`WlSessionLockSurface` opaca; viene creato al primo blocco. `Session.locked`
ne è lo stato: `Session.lock()` lo attiva (menu di alimentazione, tasto di
accensione, inattività, IPC), `Session.unlock()` lo toglie dopo
un'autenticazione riuscita.

- **Contenuto**: ora, data, batteria, numero di notifiche (mai il contenuto)
  e il tastierino `AuthPad`: numerico per il PIN, con il tasto `abc` che
  passa a un campo di testo con la tastiera interna `KeyGrid`. Sopra una
  sessione bloccata nessun client può mostrare una tastiera, quindi wvkbd
  qui non serve. Funziona anche una tastiera fisica.
- **Autenticazione** (`lock/Auth.qml`): backend scelto a run time tra `pam`
  (`PamContext`, servizio `flo-shell` in `/etc/pam.d`), `greetd` (greeter) e
  `dry` (finto: accetta `FLO_AUTH_DRY_SECRET`, predefinito `1234`).
  `FLO_AUTH` forza il backend. Il PIN è la password dell'utente: il
  tastierino la passa al primo prompt di PAM; un secondo prompt (cambio
  password, secondo fattore) interrompe il tentativo.
- **Inattività**: `IdleMonitor` (ext-idle-notify) blocca e spegne il pannello
  dopo `Session.idleSeconds` (120 s; `FLO_IDLE_LOCK=0` lo disattiva).
- **Tasto di accensione**: vedi `session/hyprland.conf`. La pressione breve
  è legata al rilascio; il rilascio che segue una pressione lunga viene
  ignorato dalla shell (finestra di 1,5 s).
- **Se la shell muore da bloccata** il compositore resta bloccato. La shell
  scrive `$XDG_RUNTIME_DIR/flo-shell.locked` quando blocca e lo cancella
  quando sblocca; `flo-shell run` la riavvia, e una shell che trova il file
  blocca di nuovo subito (serve `misc:allow_session_lock_restore = true`).
- **Limiti**: da bloccato non si raggiunge il menu di alimentazione (la
  superficie di blocco copre tutto): si sblocca prima, oppure si usa la
  pressione prolungata gestita dal firmware. Nessun conteggio dei tentativi
  o ritardo oltre a quelli di PAM.

## Greeter

`greeter/` è una configurazione Quickshell separata e piccola:
`quickshell -p greeter/` (installata: `flo-shell greeter`). I file condivisi
sono collegamenti simbolici verso `shell/`, quindi tastierino, tastiera e
tema sono gli stessi; dei servizi vengono istanziati solo `Clock` e
`Battery`. Usa il backend `greetd` di `Auth` (servizio `Greetd` di
Quickshell): crea la sessione per l'utente scelto, risponde al prompt, poi
`launch()` avvia il comando di sessione e Quickshell esce.

- Utenti: account con uid 1000–59999 e shell di login da `/etc/passwd`
  (`FLO_GREETER_USERS=a,b` sostituisce l'elenco, `FLO_GREETER_USER` sceglie
  quello iniziale).
- Sessioni: i file `*.desktop` in `/usr/share/wayland-sessions`
  (`FLO_GREETER_SESSIONS_DIR`); è preselezionata quella il cui `Exec` è
  `FLO_GREETER_SESSION` (predefinito `flo-session`), che è anche il comando
  usato se la cartella è vuota. Phosh resta quindi selezionabile. Il comando
  viene avviato come `/bin/sh -c "exec <Exec>"`.
- greetd lo avvia dentro un Hyprland minimo
  (`session/greeter-hyprland.conf`, esempio in `session/greetd/config.toml`).

## Panoramica (multitasking)

`overview/Overview.qml`: superficie opaca tra le due barre con una striscia
orizzontale di schede, una per finestra (`Compositor.windows`), centrata
sulla finestra attiva. Si apre con uno scorrimento lungo verso l'alto sulla
barra home (oltre `Theme.longSwipeThreshold`, 28 mm; uno scorrimento corto
apre il launcher) o con l'IPC `overview`.

- Tocco sulla scheda: porta la finestra in primo piano e chiude la vista.
- Scheda trascinata in alto oltre `Theme.dismissThreshold`, o tocco sulla X:
  chiude la finestra. Durante il trascinamento cambiano solo traslazione e
  opacità. Se l'applicazione rifiuta di chiudersi la scheda torna al suo
  posto.
- **Anteprime**: facoltative (`Theme.overviewThumbnails`, spente; si
  accendono con `FLO_THUMBNAILS=1`). `ScreencopyView` cattura sempre alla
  risoluzione piena della finestra, quindi `overview/Thumbnail.qml` cattura
  un solo fotogramma all'apertura, ne conserva una copia ridotta
  (`Theme.thumbnailSize`, 320 px sul lato lungo) con `grabToImage` e rilascia
  la cattura. Costo: una lettura dalla GPU per finestra a ogni apertura.
  Senza anteprime la scheda mostra l'icona dell'applicazione.

## Rotazione

Il tablet non ha sensori utilizzabili: la rotazione è manuale.
`services/RotationLock.qml` espone `transform` (0..3), `degrees`,
`supported`, `set(gradi)` e `next()`; il riquadro "Ruota" delle impostazioni
rapide chiama `next()` (0 → 90 → 180 → 270 → 0). Il lavoro è dell'adattatore.
`locked` è sempre `true`: quando `flo-sessiond` avrà la rotazione da sensore
(Fase 4) sarà lui a chiamare `set()`. `Device.landscape` segue la geometria
dello schermo, quindi tutte le disposizioni cambiano da sole. La scelta non
viene salvata: al riavvio della sessione si torna alla regola `monitor` del
file di configurazione.

## Tastiera a schermo

`services/Keyboard.qml` è l'unica interfaccia: `available`, `visible`,
`show()`, `hide()`, `toggle()`, `stop()`, `reserved`. Oggi è un **ponte
temporaneo** verso `wvkbd-mobintl` (rischio R3 del piano, ancora aperto: la
tastiera nativa con `input-method-v2` richiede un plugin C++ e sostituirà
solo questo file).

- wvkbd viene avviato al primo uso come processo figlio e poi comandato con
  i segnali documentati da wvkbd 0.21 (README e `main.c`): `SIGUSR1`
  nasconde, `SIGUSR2` mostra. `SIGRTMIN` (alterna) non viene usato: il suo
  numero cambia tra glibc (34) e musl (35).
- Lo spazio lo riserva wvkbd stesso (superficie layer-shell con zona
  esclusiva, alta `Theme.keyboardHeight` / `keyboardHeightLandscape`): le
  finestre e i pannelli che rispettano le zone esclusive si accorciano.
- Si apre dal pulsante nell'angolo destro della barra home (presente solo se
  il binario esiste) e dal campo di ricerca del launcher. Non compare da
  sola quando un'applicazione mette a fuoco un campo di testo: wvkbd lo
  saprebbe fare con `--auto`, ma allora la shell non ne conoscerebbe più lo
  stato; da decidere dopo le prove sul tablet.
- `FLO_KEYBOARD_CMD` sostituisce il comando.

## Lingua

`I18n.qml` contiene le tabelle italiana e inglese. La lingua è quella del
sistema (`LC_ALL`, `LC_MESSAGES`, `LANG` letti da Qt; `FLO_LANG=it|en` la
forza; le lingue senza tabella usano l'inglese) e date e ore sono formattate
con la stessa lingua, così etichette e date non si mescolano più. Uso:
`I18n.t("chiave")`, `I18n.t("chiave", valore)`.

## Sessione e installazione

- `flo-session` avvia Hyprland con `session/hyprland.conf` (o
  `~/.config/flo-shell/hyprland.conf` se esiste), dentro
  `dbus-run-session` se manca un bus e con un inibitore
  `handle-power-key` di logind/elogind, perché il tasto di accensione è
  gestito dalla shell.
- `session/hyprland.conf`: sintassi classica per Hyprland 0.54.x; `DSI-1` a
  scala 2, nessuna animazione, sfocatura, ombra o arrotondamento, layout
  `monocle` (una finestra alla volta), scorrimento touch tra aree di lavoro,
  tasti fisici verso l'IPC, `exec-once = flo-shell run`. **Hyprland 0.57
  non legge più questa sintassi**: andrà convertito in Lua prima di
  aggiornare oltre la 0.56.
- `flo-shell run` riavvia Quickshell se termina con errore (al massimo 5
  fallimenti rapidi di fila).
- `make install DESTDIR=… PREFIX=/usr` installa: la shell e il greeter in
  `/usr/share/flo-shell`, gli script in `/usr/bin`, la voce di sessione in
  `/usr/share/wayland-sessions`, il servizio PAM in `/etc/pam.d/flo-shell`
  (stack `base-auth` di Alpine) e l'esempio per greetd nella documentazione.
  `make check` controlla la sintassi degli script e, se c'è Hyprland, delle
  due configurazioni.

## Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `FLO_DRY_RUN=1` | azioni di alimentazione e accensione del pannello solo nel log |
| `FLO_BACKLIGHT_DIR` | cartella finta con `brightness` e `max_brightness` |
| `FLO_COMPOSITOR` | forza il backend dell'adattatore |
| `FLO_AUTH=pam\|greetd\|dry` | forza il backend di autenticazione |
| `FLO_AUTH_DRY_SECRET` | codice accettato dal backend `dry` (predefinito `1234`) |
| `FLO_PAM_CONFIG`, `FLO_PAM_CONFIG_DIR` | servizio PAM e cartella (predefiniti `flo-shell`, `/etc/pam.d`) |
| `FLO_IDLE_LOCK` | secondi di inattività prima del blocco, `0` = mai |
| `FLO_STATE_DIR` | cartella del file `flo-shell.locked` (predefinita `XDG_RUNTIME_DIR`) |
| `FLO_THUMBNAILS=1` | anteprime nella panoramica |
| `FLO_KEYBOARD_CMD` | comando della tastiera a schermo |
| `FLO_LANG=it\|en` | lingua dell'interfaccia |
| `FLO_DEV_INPUT=1` | abilita l'IPC `authInput` (solo sviluppo) |
| `FLO_GREETER_USER`, `FLO_GREETER_USERS`, `FLO_GREETER_SESSION`, `FLO_GREETER_SESSIONS_DIR` | greeter |
| `FLO_HYPRLAND_CONF`, `FLO_SHELL_DATA` | file di configurazione per `flo-session`, cartella dati per gli script |

## Esecuzione annidata per lo sviluppo

```
dev/run-nested.sh                      # shell, 600x960
dev/run-nested.sh landscape            # shell, 960x600
dev/run-nested.sh portrait greeter     # greeter
FLO_AUTH=pam dev/run-nested.sh         # blocco con il vero PamContext
FLO_AUTH=greetd dev/run-nested.sh portrait greeter   # greeter contro il finto greetd
```

Lo script avvia un Hyprland annidato, vi crea un'uscita headless della
dimensione del tablet, spegne l'uscita-finestra e lancia la shell su un bus
D-Bus di sessione privato (senza servizi attivabili). Non disegna nulla sul
desktop e stampa i comandi per catturare lo schermo con `grim`, chiamare
l'IPC, scrivere il PIN, aprire una finestra di prova. Nulla tocca la macchina
vera:

- alimentazione e pannello solo nel log (`FLO_DRY_RUN=1`),
  retroilluminazione finta, blocco per inattività spento;
- il blocco riguarda solo il compositore annidato;
- autenticazione finta (`FLO_AUTH=dry`, codice `1234`). Con `FLO_AUTH=pam`
  si prova il vero `PamContext` contro un servizio PAM usa e getta
  (`pam_exec` + `dev/pam-check.sh`) che conosce solo il codice di prova; con
  `FLO_AUTH=greetd` il greeter parla con `dev/fake-greetd.py`, che non avvia
  nulla;
- se `wvkbd-mobintl` non è installato lo sostituisce `dev/fake-wvkbd.sh`,
  che registra i segnali ricevuti in `$XDG_RUNTIME_DIR/flo-shell-dev/wvkbd.log`.

Il compositore annidato usa `dev/hyprland-nested.conf` (sintassi classica,
come sul tablet); `FLO_NESTED_CONF=lua` usa la variante Lua.
`FLO_NESTED_ROOT=<prefisso>/share/flo-shell` prova un albero installato.
Nel compositore annidato non si possono iniettare tocchi: per questo esiste
l'IPC `authInput`, e tutto ciò che richiede un dito è in TESTING.md.

Con un compositore wlroots (non provato qui, nessuno era installato):
`WLR_BACKENDS=headless labwc` e poi `WAYLAND_DISPLAY=… quickshell -p shell/`.

Volume, Wi-Fi e Bluetooth restano quelli veri della macchina: non toccare
quei controlli durante le prove.

## Scelte di progetto per il tablet

Il Nexus 7 2013 ha un pannello da 7,02" a 323 ppi usato a scala 2: 600×960
punti logici a circa 161 dpi, cioè 1 px logico ≈ 0,157 mm. Si tiene in
verticale con una o due mani e in orizzontale con due, con i pollici sui
bordi corti. Ha solo i tasti di accensione e volume. Non ha modem.

- **Misure fisiche.** `Device.qml` contiene le costanti; `Theme.qml` ne
  deriva le misure. Bersagli tattili da 60 px (9,4 mm), minimo 56 px (9 mm);
  testo corrente a 16 px, mai sotto 15 px. Nessun componente contiene misure
  proprie del dispositivo.
- **Barre sottili, aree tattili larghe.** La barra di stato occupa 30 px e la
  barra home 20 px, ma le loro superfici sono alte 48 px: la parte in più è
  trasparente e serve solo a ricevere il tocco. Costo: i 18 px sotto la barra
  e i 28 px sopra la barra home non arrivano all'applicazione.
- **Navigazione a schermo.** Senza tasto home, la barra in basso fa da home:
  tocco o scorrimento verso l'alto aprono il launcher, oppure chiudono ciò
  che è aperto; uno scorrimento lungo apre la panoramica; nell'angolo destro
  c'è il pulsante della tastiera. Sulla barra di stato tocco o scorrimento verso il basso
  aprono le impostazioni rapide.
- **Zone del pollice.** In verticale i controlli usati spesso stanno nel
  terzo inferiore: riquadri e cursori delle impostazioni rapide, campo di
  ricerca e finestre aperte del launcher, pulsanti di alimentazione. In
  orizzontale stanno sul bordo destro: le impostazioni rapide diventano un
  pannello laterale da 360 px con riquadri a sola icona, la ricerca va in
  basso a destra, i pulsanti di alimentazione in colonna a destra.
- **Disposizione per orientamento.** Griglia del launcher a 4 colonne in
  verticale e 6 in orizzontale; popup delle notifiche in alto al centro in
  verticale e in alto a destra in orizzontale.
- **Niente rete mobile.** La barra mostra solo Wi-Fi o cavo.
- **Carica.** Barra, riquadro e menu di alimentazione mostrano lo stato di
  carica.
- **Azioni irreversibili.** Spegni e Riavvia chiedono un secondo tocco.
- **Tastierino.** Tasti del PIN larghi 113 px e alti 70; tastiera interna con
  tasti da 60×56 px in verticale e 96×56 in orizzontale, dove occupa tutta la
  larghezza e l'orologio si fa da parte.

## Limiti noti

- Gli scorrimenti sulle barre scattano al rilascio del dito, non a metà
  gesto: vedi il commento in `components/EdgeArea.qml`.
- Il pulsante della tastiera sulla barra home è alto 48 px (l'altezza della
  striscia tattile), sotto il minimo di 56: è largo 76 px per compensare.
- Il campo di ricerca del launcher è in basso: con la tastiera aperta sale
  solo se il compositore accorcia la superficie del launcher per la zona
  esclusiva di wvkbd. Da verificare sul tablet.
- Le finestre aperte nel launcher restano come scorciatoia accanto alla
  panoramica.
- "Indietro" è un tentativo (vedi sopra) e non ha ancora un gesto.
- La rotazione non viene ricordata tra una sessione e l'altra.
- Non verificato: aggiornamento dell'ora subito dopo una ripresa dalla
  sospensione (il tick è allineato al minuto, quindi al più tardi dovrebbe
  correggersi al minuto successivo).
- I timer a colpo singolo per la scomparsa dell'OSD e dei popup vengono
  armati da un evento; a riposo non ce ne sono di attivi. Il blocco per
  inattività usa `ext-idle-notify`, non un timer della shell.
