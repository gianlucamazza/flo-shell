# flo-shell — piano di progetto

Shell touch moderna, disegnata interamente dalla GPU, per il Nexus 7 2013
("flo", APQ8064, Adreno 320) su postmarketOS con kernel mainline.
Nome di lavoro: `flo-shell`. Stato: pianificazione (2026-11-15).

Il lavoro su kernel, Mesa e avvio resta nel progetto `nexus7-omarchy`;
questo progetto parte da lì e ne dipende (vedi Fase 0).

## Obiettivo

Reattività percepita pari ad Android AOSP sullo stesso hardware:

- 60 fotogrammi al secondo stabili su shell, transizioni e scorrimento;
- risposta al tocco entro due fotogrammi (≤ 33 ms dal tocco al primo pixel);
- nessun processo in background che consumi CPU a schermo fermo;
- esperienza coerente con Omarchy (stessa tecnologia, stessi temi).

## Vincoli misurati

| Vincolo | Valore | Conseguenza |
|---|---|---|
| GPU | Adreno 320, GLES 3.0, niente Vulkan (da confermare al gate G0) | solo renderer GLES; niente sfocature, ombre, strati traslucidi a tutto schermo |
| Schermo | 1200×1920, scala intera 2× | riempimento limitato: superfici opache, poco overdraw |
| CPU | 4 core Krait, 1512 MHz | un solo processo di shell, nessun polling |
| RAM | 2 GB, zram zstd | pochi processi residenti; app in background congelate |
| Touch | 100 Hz, 1 interrupt per fotogramma | già sano, nessun lavoro lato driver |
| Architettura | armv7 (32 bit) | ogni componente va verificato o compilato per armv7 |

## Architettura

```
 app (Qt Quick / GTK4-ngl / web)        <- GPU
 ───────────────────────────────────────
 flo-shell  (Quickshell + QML + plugin C++)   un processo, GPU
   barra · launcher · notifiche · impostazioni rapide · OSD
   multitasking · blocco schermo · greeter · tastiera a schermo
 ───────────────────────────────────────
 compositore Wayland (Hyprland, ripiego wlroots)   GPU, scanout diretto
 ───────────────────────────────────────
 flo-sessiond (demone di sistema, piccolo)
   spinta CPU al tocco · congelamento app in background · rotazione
 ───────────────────────────────────────
 kernel mainline + Mesa freedreno (progetto nexus7-omarchy)
```

### Decisioni

1. **Runtime della shell: Quickshell (Qt Quick/QML).** È lo stesso runtime
   della shell di Omarchy sul portatile (quickshell 0.3.x), è disegnato dalla
   GPU con scena a ritenzione, e copre già layer-shell, notifiche, MPRIS,
   UPower, PipeWire, blocco sessione e greetd. Non è pacchettizzato per armv7
   in Alpine: va creato il pacchetto (Qt 6.11 e layer-shell-qt ci sono).
2. **Compositore: Hyprland come prima scelta, wlroots come ripiego.**
   Hyprland 0.54.3 è pacchettizzato per armv7 in Alpine edge e dà coerenza con
   Omarchy. Resta da verificare che parta con GLES 3.0 (gate G1). La shell
   parla al compositore attraverso un solo modulo adattatore, così il ripiego
   (phoc, labwc o sway) non richiede riscritture.
3. **Nessun compositore scritto da zero.** Non porta prestazioni in più
   rispetto a uno esistente con scanout diretto e damage tracking.
4. **I gesti che seguono il dito stanno nel compositore**, non nella shell
   (cambio app, ritorno a casa): è l'unico modo per averli sincronizzati al
   refresh. Su Hyprland: gesti touch nativi più plugin; da validare al gate G1.
5. **Politiche di sistema fuori dalla shell**, in `flo-sessiond`: funzionano
   anche se la shell si riavvia e hanno un'interfaccia stretta e privilegi
   minimi.
6. **Phosh resta installato** come sessione alternativa fino alla Fase 5.

### Regole di progetto della UI

- Animare solo trasformazioni e opacità; mai il layout durante un'animazione.
- Superfici opache; nessun effetto a tutto schermo; angoli e ombre come
  texture pre-renderizzate, non shader.
- App a schermo intero in scanout diretto; barra come piano separato dove
  il controller video lo consente.
- Nessun timer di polling: solo eventi (D-Bus, inotify, socket).
- Bersagli tattili ≥ 48 px logici; tutto raggiungibile senza tastiera.
- Budget: 8 ms di CPU e 8 ms di GPU per fotogramma, misurati in CI sul tablet.

## Componenti

| Componente | Contenuto | Note |
|---|---|---|
| Barra di stato | ora, rete, batteria, notifiche | piano opaco, aggiornamenti a eventi |
| Impostazioni rapide | Wi-Fi, Bluetooth, luminosità, volume, rotazione, modalità aereo | pannello a discesa |
| Launcher | griglia app, ricerca | indicizzazione `.desktop` una sola volta |
| Notifiche | server `org.freedesktop.Notifications`, storico | |
| Multitasking | panoramica app, chiusura con gesto | anteprime via screencopy, a bassa risoluzione |
| OSD | volume, luminosità | |
| Menu di alimentazione | spegni, riavvia, sospendi | via logind |
| Blocco schermo | `ext-session-lock-v1`, PIN | PAM |
| Greeter | accesso con greetd | stessa base QML del blocco |
| Tastiera a schermo | layout italiano, `input-method-v2` | rischio R3 |
| Agente polkit, portali | permessi, selettore file, screenshot | `xdg-desktop-portal` |
| `flo-sessiond` | spinta al tocco, freezer cgroup, rotazione da sensore | Rust o C++, da decidere in Fase 4 |

## Fasi e gate

**Fase 0 — Fondamenta (in corso, progetto nexus7-omarchy).**
Kernel r13 (cache L2 1134 MHz, tick 300 Hz), r14 (correzioni GPU A320 dal
ramo della comunità), r15 (ricarica, pannello), Mesa 26.3.0 per armv7.

- **Gate G0 — la GPU regge?** Sul tablet: `glmark2-es2-wayland`, una scena
  Qt Quick di prova (lista a scorrimento + transizione a tutto schermo),
  un'app GTK4 con renderer GPU. Criterio: scena Qt Quick ≥ 55 fps, nessun
  blocco GPU in 30 minuti. Se fallisce, il limite è hardware o driver e il
  progetto si ferma qui finché non è risolto.

**Fase 1 — Prove di fattibilità.**
Hyprland sul tablet in sessione separata; pacchetto Quickshell armv7; barra
minima a schermo; gesto touch di cambio area di lavoro.

- **Gate G1 — quale compositore?** Hyprland se parte su GLES 3.0, regge
  60 fps a riposo e durante un gesto, e resta sotto 150 MB. Altrimenti
  ripiego wlroots, deciso con gli stessi numeri.

**Fase 2 — Nucleo della shell.** Barra, launcher, notifiche, impostazioni
rapide, OSD, menu di alimentazione. Sessione avviabile dal greeter accanto
a Phosh.

**Fase 3 — Uso al tocco completo.** Gesti di sistema, multitasking,
tastiera a schermo, rotazione, blocco schermo, greeter.

**Fase 4 — Politiche di sistema.** `flo-sessiond`: spinta CPU al tocco,
congelamento delle app non visibili con lista di eccezioni, priorità
memoria. Portali e agente polkit. Sospensione e risveglio.

- **Gate G4 — parità con Android?** Misura degli obiettivi in cima a questo
  documento, più consumo a riposo.

**Fase 5 — Rifinitura e consegna.** Temi Omarchy, pacchetti pmaports
locali (`flo-shell`, `quickshell`, sessione), documentazione, sessione
predefinita. Phosh rimosso solo su decisione esplicita.

## Misura

- Tempi di fotogramma dal compositore; tracce `perf`/ftrace per i casi lenti.
- Latenza tocco→pixel con ripresa video ad alta velocità o LED sul touch.
- Registratore di uso già esistente (`uitrace`), alleggerito.
- Ogni fase si chiude con i numeri registrati in `docs/MEASUREMENTS.md`.

## Rischi

| # | Rischio | Mitigazione |
|---|---|---|
| R1 | Blocchi GPU del driver a3xx anche con Mesa 26.3.0 | gate G0; segnalazione a monte; variabili di debug come ripiego |
| R2 | Hyprland richiede più di GLES 3.0 | gate G1; adattatore compositore; ripiego wlroots |
| R3 | Tastiera a schermo: Quickshell non espone `input-method-v2` | plugin C++ dedicato; `wvkbd` solo come ponte temporaneo |
| R4 | Quickshell non compila o non regge su armv7 | prova in Fase 1; alternativa: shell C++/Qt Quick con layer-shell-qt, stesso QML |
| R5 | Gesti che seguono il dito non fluidi | implementarli nel compositore (plugin), non nella shell |
| R6 | Congelare app rompe musica, download, notifiche | lista di eccezioni, scongelamento su evento |

## Fuori ambito

Telefonia, fotocamera, contenitori Android, un toolkit grafico proprio.
