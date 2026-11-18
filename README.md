# flo-shell

A GPU-drawn touch shell for the Nexus 7 (2013) (`flo`) running
postmarketOS (renamed [Nura](https://nura.eco) in September 2026): home screen, launcher, status
bar, quick settings, notifications, lock screen and greeter, built with
[Quickshell](https://quickshell.org) on Hyprland, plus `flo-sessiond`, a small
C daemon for session and app lifecycle.

Part of [nexus7-flo-linux](https://github.com/gianlucamazza/nexus7-flo-linux).
Not an official Nura or Hyprland project. Hardware status of the tablet:
[HARDWARE.md](https://github.com/gianlucamazza/nexus7-flo-linux/blob/main/docs/HARDWARE.md),
roadmap: [ROADMAP.md](https://github.com/gianlucamazza/nexus7-flo-linux/blob/main/docs/ROADMAP.md).

## Layout

- `shell/` – the shell (`quickshell -p shell/`)
- `greeter/` – greetd greeter (shares components with the shell)
- `session/` – Hyprland, greetd and PAM configuration, session scripts
- `sessiond/` – `flo-sessiond` (C, meson) and its tests
- `dev/` – nested Hyprland and fake greetd helpers for testing on a desktop
- `docs/` – architecture, plan, testing on the tablet

## Install

```sh
make install DESTDIR=/tmp/pkg PREFIX=/usr
meson setup build/sessiond sessiond && meson compile -C build/sessiond
```

See `docs/TESTING.md` for checks to run on the device.

## Licence

MIT, see `LICENSE`.

The original Italian README is [`README.it.md`](README.it.md).

## Branches

- `main` – the shell as published
- `fix/lock-before-dpms`, `fix/greeter-invisible-cursor` – fixes under test
  on the tablet, not merged yet
