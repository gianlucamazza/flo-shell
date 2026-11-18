# Agent PR integration on flo

The three GitHub PRs [#1](https://github.com/gianlucamazza/flo-shell/pull/1),
[#2](https://github.com/gianlucamazza/flo-shell/pull/2) and
[#3](https://github.com/gianlucamazza/flo-shell/pull/3) are merged on the
published `main` branch, but the tablet package is based on the separate
`fix/portal-dialog-overlay` branch. This integration carries their features
onto that branch while preserving the proven backlight, greeter, lock, Lua,
home and portal changes.

`flo-shell` only displays and launches agents. The companion `flo-agents`
CLI owns configuration, SSH and local agent installation. Without that CLI,
the shell must show no agent controls or errors. No credentials or device
addresses are built into the package. The PRs' input and secret handling
must be retained: argument arrays for settings and stdin for API keys.

Acceptance: `make check` exercises the old tablet behavior and the PR tests;
`make install` stages the four agent files and both Hyprland formats. A
native tablet check must establish that the existing session, PIN, touch and
brightness controls still work. Agent launch and settings require a real
`flo-agents` CLI and configuration, so source integration alone does not
claim those flows work on the tablet.

The initial merge passed `make check`: 38 launcher helper checks, 105
configuration helper checks, 57 QML files scanned, six Hyprland launcher
tests, and the existing brightness and lock checks. Staging installed
`flo-agent-session`, `flo-agent-config`, `AgentSettings.qml`, and both
classic/Lua Hyprland configurations. A lint bug in PR #2 skipped all QML
files when the checkout path contained a directory called `build`; the
integration fixes the scan to inspect paths relative to the repository.

The companion CLI has since been imported into the project's resolution
branch, packaged separately as `flo-agents-0.1_git20261118-r0` and installed
on the tablet with `flo-shell-0.1_git20261118-r1`. With no agent config,
`flo-agent-config entries` returns only `Configure agents`. Native IPC
opened the launcher and settings panel and returned to Home; there were no
failed system or user units. Visual touch verification and an explicitly
configured remote or local agent session remain pending. No key, secret or
Crush binary was created during installation.

The integration is proposed in [PR #4](https://github.com/gianlucamazza/flo-shell/pull/4).
The published `main` branch was merged into the integration branch to clear
GitHub conflicts. `make check` passed again, and the PR is mergeable but
remains a draft until the native touch check is confirmed.
