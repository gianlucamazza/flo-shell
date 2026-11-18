# flo-shell

Shell touch disegnata dalla GPU per il Nexus 7 2013 (flo) su postmarketOS.
Vedi [docs/PLAN.md](docs/PLAN.md).

Codice della shell in `shell/` (avvio: `quickshell -p shell/`), greeter in
`greeter/`, sessione e pacchetto in `session/` e `Makefile`
(`make install DESTDIR=… PREFIX=/usr`). Struttura e prove annidate in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), prove da fare sul tablet in
[docs/TESTING.md](docs/TESTING.md).

## Portabilità

flo-shell usa Quickshell e Hyprland e include un piccolo demone di sessione.
Il codice non dipende direttamente dal SoC APQ8064, ma layout, greeter e
configurazioni sono progettati per il Nexus 7 (2013). Per altri dispositivi
Wayland servono adattamenti. Le prove Hyprland annidate su un computer sono
documentate in `dev/`.
