# flo-shell — architettura (Fase 2, nucleo della shell)

Configurazione Quickshell in `shell/`, un solo processo. Avvio:
`quickshell -p shell/`. Il piano resta in [PLAN.md](PLAN.md).

## Struttura dei file

```
shell/
  shell.qml            ingresso: barre, caricamento pigro dei pannelli, IPC
  Device.qml           costanti fisiche del tablet e orientamento corrente
  Theme.qml            colori, spaziature, bersagli tattili, durate
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
    Session.qml        spegni, riavvia, sospendi, blocca (logind)
    RotationLock.qml   STUB: solo il flag, la rotazione arriva con flo-sessiond
    Clock.qml          l'unico risveglio periodico (un tick al minuto)
    Ui.qml             stato dei pannelli e dell'OSD
  components/          Pressable, IconButton, LevelSlider, ToggleTile, Icon, EdgeArea…
  bar/ home/ launcher/ quicksettings/ notifications/ osd/ power/
dev/
  run-nested.sh        esecuzione annidata per lo sviluppo
```

Superfici (tutte layer-shell, tutte opache tranne le due strisce tattili):

| Superficie | Livello | Note |
|---|---|---|
| Barra di stato | top | 30 px visibili e riservati, superficie di 48 px |
| Barra home | top | 20 px visibili e riservati, superficie di 48 px |
| Launcher, impostazioni rapide | overlay | create al primo uso, poi tenute in memoria |
| Menu di alimentazione | overlay | a tutto schermo, copre anche le barre |
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
| `supportsBack`, `supportsAppSwitch` | oggi `false` in entrambi i backend |

`Compositor` espone gli stessi dati più `windowTitle()`, `windowAppId()`,
`focusWindow()`, `closeWindow()`, `closeActiveWindow()`, `focusWorkspace()`.

**Aggancio per i gesti.** `Compositor.goBack()` e
`Compositor.showAppSwitcher()` esistono ma non fanno nulla finché un backend
non dichiara `supportsBack` / `supportsAppSwitch` e implementa le due
funzioni. I gesti che seguono il dito restano nel compositore (decisione 4
del piano): la shell li richiama solo da inneschi discreti (IPC, pulsanti).

Su Hyprland con configurazione Lua i dispatcher sono espressioni Lua: il
backend sceglie la forma in base a `Hyprland.usingLua`.

## IPC

`quickshell ipc -p shell call flo <funzione>`, pensato per i tasti fisici
legati nel compositore e per i test:
`home`, `launcher`, `quickSettings`, `powerMenu`, `closeAll`, `back`,
`appSwitcher`, `workspace <id>`, `volume <±percento>`, `mute`,
`brightness <±percento>`, `osd <volume|brightness>`, `state`.

I tasti volume possono modificare il volume con qualsiasi mezzo (wpctl, IPC
qui sopra): l'OSD compare per l'evento di PipeWire, non per il tasto.

## Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `FLO_DRY_RUN=1` | le azioni di alimentazione vengono solo scritte nel log |
| `FLO_BACKLIGHT_DIR` | cartella finta con `brightness` e `max_brightness` |
| `FLO_COMPOSITOR` | forza il backend dell'adattatore |

## Esecuzione annidata per lo sviluppo

```
dev/run-nested.sh            # 600x960
dev/run-nested.sh landscape  # 960x600
```

Lo script avvia un Hyprland annidato, vi crea un'uscita headless della
dimensione del tablet, spegne l'uscita-finestra e lancia la shell su un bus
D-Bus di sessione privato (senza servizi attivabili), con `FLO_DRY_RUN=1` e
retroilluminazione finta. Non disegna nulla sul desktop: stampa i comandi
per catturare lo schermo con `grim`, chiamare l'IPC, inviare notifiche e
ruotare l'uscita. Richiede un Hyprland che legga la configurazione Lua.

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
  che è aperto. Sulla barra di stato tocco o scorrimento verso il basso
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

## Limiti noti

- Gli scorrimenti sulle barre scattano al rilascio del dito, non a metà
  gesto: vedi il commento in `components/EdgeArea.qml`.
- Il campo di ricerca è in basso: con la tastiera a schermo (Fase 3) andrà
  spostato o fatto salire.
- Le finestre aperte nel launcher sono un ripiego fino alla vista
  multitasking della Fase 3.
- Non verificato: aggiornamento dell'ora subito dopo una ripresa dalla
  sospensione (il tick è allineato al minuto, quindi al più tardi dovrebbe
  correggersi al minuto successivo).
- I timer a colpo singolo per la scomparsa dell'OSD e dei popup vengono
  armati da un evento; a riposo non ce ne sono di attivi.
