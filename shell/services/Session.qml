pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Session state and power actions.
//
// Power actions go through logind (system bus). FLO_DRY_RUN=1 logs them
// instead of running them, for development on a workstation.
//
// Locking: `locked` drives the session lock in lock/Lock.qml
// (ext-session-lock-v1). A marker file records that the session is locked,
// so that a shell restarted after a crash locks again at once instead of
// leaving the compositor on its "lock client died" screen for good.
Singleton {
    id: root

    readonly property bool dryRun: (Quickshell.env("FLO_DRY_RUN") || "") === "1"

    property bool locked: false
    property bool lockLoaded: false
    // What the shell believes about the panel: it only changes through
    // setDisplay(), the compositor may also wake it on a key press.
    property bool displayOn: true

    // Seconds without input before locking; 0 disables. FLO_IDLE_LOCK
    // overrides the default.
    readonly property int idleSeconds: {
        const v = Quickshell.env("FLO_IDLE_LOCK");
        return v !== null && v !== undefined && v !== "" ? Math.max(0, parseInt(v) || 0) : 120;
    }

    // Set by the `idleInhibit` IPC call (automated tests): no idle lock or
    // panel blanking while true. It never unlocks a locked session.
    property bool idleInhibited: false

    readonly property string stateDir: Quickshell.env("FLO_STATE_DIR") || Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string markerPath: stateDir + "/flo-shell.locked"

    function _logind(method: string): void {
        _run(method, ["sh", "-c", "busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \"$1\" b true 2>/dev/null"
            + " || dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 \"org.freedesktop.login1.Manager.$1\" boolean:true", "sh", method]);
    }

    function _run(name: string, cmd: list<string>): void {
        if (dryRun) {
            console.info("flo-session: dry-run", name, "->", cmd.slice(2).join(" "));
            return;
        }
        runner.command = cmd;
        runner.running = true;
    }

    function powerOff(): void { _logind("PowerOff"); }
    function reboot(): void { _logind("Reboot"); }
    function suspend(): void {
        lock();
        _logind("Suspend");
    }

    function lock(): void {
        if (locked)
            return;
        lockLoaded = true;
        locked = true;
        marker.setText("locked\n");
    }
    // Called by the lock screen after a successful authentication.
    function unlock(): void {
        if (!locked)
            return;
        locked = false;
        setDisplay(true);
        cleaner.running = true;
    }

    function setDisplay(on: bool): void {
        if (displayOn === on)
            return;
        displayOn = on;
        if (dryRun)
            console.info("flo-session: dry-run display", on ? "on" : "off");
        else
            Compositor.setDisplayPower(on);
    }

    // Power key, short press (bound on key release in the compositor):
    // lock and blank; when already locked, toggle the panel.
    property real _longPressAt: 0
    function powerKey(): void {
        // The release that ends a long press is not a short press.
        if (Date.now() - _longPressAt < 1500)
            return;
        if (!locked) {
            lock();
            setDisplay(false);
        } else {
            setDisplay(!displayOn);
        }
    }
    // Power key held: power menu (not reachable while locked, the lock
    // surface covers every other surface).
    function powerKeyLong(): bool {
        _longPressAt = Date.now();
        setDisplay(true);
        return !locked;
    }
    function idle(): void {
        if (idleInhibited)
            return;
        lock();
        setDisplay(false);
    }

    Process {
        id: runner
    }
    FileView {
        id: marker
        path: root.markerPath
        printErrors: false
        onLoaded: {
            console.info("flo-session: lock marker found, locking again");
            root.lock();
        }
    }
    Process {
        id: cleaner
        command: ["rm", "-f", root.markerPath]
    }
}
