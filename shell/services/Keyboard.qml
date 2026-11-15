pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// On-screen keyboard, behind one small interface: available, visible,
// show(), hide(), toggle(), stop().
//
// TEMPORARY BRIDGE (plan risk R3). The implementation runs wvkbd-mobintl as
// a child process and drives it with the signals documented by wvkbd 0.21
// (README and main.c): SIGUSR1 hides, SIGUSR2 shows. SIGRTMIN (toggle) is
// deliberately not used: its number differs between glibc (34) and musl
// (35), and the tablet runs musl. wvkbd is its own layer-shell surface with
// its own exclusive zone, so the compositor reserves the space and shell
// surfaces that respect exclusive zones shrink above it.
//
// The native keyboard (input-method-v2 through a C++ plugin) will replace
// the two Process objects below; nothing else in the shell may depend on
// wvkbd.
Singleton {
    id: root

    readonly property string command: Quickshell.env("FLO_KEYBOARD_CMD") || "wvkbd-mobintl"
    // True once the binary has been found on PATH.
    property bool available: false
    // Requested state. wvkbd does not report its own, so this is what the
    // shell last asked for.
    property bool visible: false
    readonly property bool running: proc.running
    // Space taken at the bottom of the screen while visible, logical px.
    readonly property int height: Device.landscape ? Theme.keyboardHeightLandscape : Theme.keyboardHeight
    readonly property int reserved: visible ? height : 0

    readonly property int sigHide: 10 // SIGUSR1 on Linux (arm, x86)
    readonly property int sigShow: 12 // SIGUSR2

    function _hex(c: color): string {
        return c.toString().substring(1);
    }

    function show(): void {
        if (!available) {
            console.info("flo-keyboard:", command, "not installed");
            return;
        }
        if (proc.running)
            proc.signal(sigShow);
        else
            proc.running = true; // started on first use, visible
        visible = true;
    }
    function hide(): void {
        if (proc.running)
            proc.signal(sigHide);
        visible = false;
    }
    function toggle(): void {
        if (visible)
            hide();
        else
            show();
    }
    function stop(): void {
        proc.running = false;
        visible = false;
    }

    Process {
        id: probe
        command: ["sh", "-c", "command -v \"$1\"", "sh", root.command]
        running: true
        onExited: code => root.available = code === 0
    }
    Process {
        id: proc
        // Opaque, theme-coloured, no effects. Heights are in surface
        // (logical) pixels for both orientations.
        // A keyboard left behind by a crashed shell is replaced, not doubled
        // (not in a dry run: a development machine may have its own).
        command: ["sh", "-c", (Session.dryRun ? "" : "pkill -x \"$(basename \"$1\")\" 2>/dev/null; ") + "exec \"$@\"", "sh", root.command, "-H", Theme.keyboardHeight, "-L", Theme.keyboardHeightLandscape, "--fn", Theme.keyboardFont, "--alpha", "255",
            "--bg", root._hex(Theme.barBg), "--fg", root._hex(Theme.surfaceAlt), "--fg-sp", root._hex(Theme.surface), "--press", root._hex(Theme.accent),
            "--press-sp", root._hex(Theme.accent), "--text", root._hex(Theme.text), "--text-sp", root._hex(Theme.text)]
        onExited: root.visible = false
    }
}
