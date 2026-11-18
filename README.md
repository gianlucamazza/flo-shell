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
- `scripts/` – `flo-agent-session`, the launcher helper for remote agents
- `dev/` – nested Hyprland and fake greetd helpers for testing on a desktop
- `docs/` – architecture, plan, testing on the tablet

## Install

```sh
make install DESTDIR=/tmp/pkg PREFIX=/usr
meson setup build/sessiond sessiond && meson compile -C build/sessiond
```

See `docs/TESTING.md` for checks to run on the device.

## Agents (remote)

flo-shell does not implement SSH or mosh. A companion CLI, `flo-agents`
(in [nexus7-flo-linux](https://github.com/gianlucamazza/nexus7-flo-linux)),
opens those sessions on a 64-bit host. Configure it with `flo-agents setup`.

When `flo-agents` is on PATH and `flo-agents list` prints tool ids
(`claude`, `codex`, `grok`), the launcher shows one entry per tool:
Claude Code (remote), Codex (remote), Grok Build (remote). Tapping an
entry opens the session terminal already used by the shell, running
`flo-agent-session`, which calls `flo-agents launch <tool>`. A nonzero
exit posts a notification titled “Agent session dropped”; a clean exit
does not. If the CLI is missing or the list is empty, the launcher
shows no agent entries and writes nothing to the log.

The list is read once when the launcher opens. There is no extra
daemon, no polling, and the added memory is negligible (a one-shot
process and a few launcher rows).

## Portability

flo-shell is a Quickshell interface on Hyprland, plus a small session
daemon. It is not tied to the APQ8064 SoC, but it is written for the
Nexus 7 (2013) tablet: layout, greeter and session files are
flo-specific. It is not a drop-in shell for an arbitrary mainline
Wayland device. Nested Hyprland testing on a desktop is documented
under `dev/`.

## Licence

MIT, see `LICENSE`.

The original Italian README is [`README.it.md`](README.it.md).

## Branches

- `main` – the shell as published
- `fix/lock-before-dpms`, `fix/greeter-invisible-cursor` – fixes under test
  on the tablet, not merged yet
