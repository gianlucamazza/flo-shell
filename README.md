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
- `scripts/` – `flo-agent-session` and `flo-agent-config`, helpers for remote agents and local Crush
- `dev/` – nested Hyprland and fake greetd helpers for testing on a desktop
- `docs/` – architecture, plan, testing on the tablet

## Install

```sh
make install DESTDIR=/tmp/pkg PREFIX=/usr
meson setup build/sessiond sessiond && meson compile -C build/sessiond
```

See `docs/TESTING.md` for checks to run on the device.

The tablet integration preserves the backlight, greeter, lock, Home,
Hyprland Lua and portal-dialog fixes. Its source and native test limits
are recorded in [`docs/AGENT-PR-INTEGRATION.md`](docs/AGENT-PR-INTEGRATION.md).

## Agents (remote and local)

flo-shell does not implement SSH or mosh and never writes the agent
config. A companion CLI, `flo-agents`
(in [nexus7-flo-linux](https://github.com/gianlucamazza/nexus7-flo-linux)),
is the only writer. The touch panel talks to it through
`flo-agent-config` (`config get` / `config set` / `check` / `key` /
`local` / `secret`), always as argv, never as a shell string built
from the fields. The API key is an exception: `secret set api_key`
reads it from stdin only.

When `flo-agents` is on PATH but not yet configured, the launcher shows
a single **Configure agents** entry that opens the settings panel
(host, user, port, mosh/ssh, per-agent commands, default, tmux, device
key, and a **Local agent (Crush)** section). When configured, it keeps
the milestone 1 tool entries (Claude Code / Codex / Grok Build), Crush
when `list` prints `crush` (label **Crush (local)**, generic icon, no
logo), plus **Agent settings**. Tapping a tool opens the session
terminal with `flo-agent-session` → `flo-agents launch <tool>`. A
nonzero remote exit posts “Agent session dropped”; a nonzero Crush
exit posts “Agent session ended with error”. A clean exit does not
notify. If the CLI is missing, the launcher shows no agent rows and
writes nothing to the log.

Crush is installed from the panel (`flo-agents local install`; the
download is about 28 MB). RAM use of Crush on the tablet has not been
measured; this document does not give a figure. Provider, base URL
(openai-compat / ollama / llamacpp) and model are saved with
`config set`. The API key field is masked and write-only: the value is
piped to `secret set api_key` and then cleared; the panel shows
`Key set ••••abcd` from `secret status`. ollama and llamacpp can skip
the key.

The panel is created the first time it is opened. The CLI runs only on
open, save, test, Create key, install/uninstall and secret
set/unset: no polling, no extra daemon. Text fields use the same
on-screen keyboard path as the launcher search box (`wvkbd` today).
The public device key can be copied with `wl-copy` when that tool is
on PATH; the private key is never shown.

The list is read once when the launcher opens. Extra memory is a
one-shot process and the lazy settings surface.

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
