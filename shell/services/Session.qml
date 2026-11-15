pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Power actions through logind (system bus). FLO_DRY_RUN=1 logs the command
// instead of running it, for development on a workstation.
Singleton {
    id: root

    readonly property bool dryRun: (Quickshell.env("FLO_DRY_RUN") || "") === "1"

    // Emitted when a lock is requested. STUB: the lock screen
    // (ext-session-lock-v1) arrives in phase 3; until then this only asks
    // logind to signal Lock on the session.
    signal lockRequested

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
    function suspend(): void { _logind("Suspend"); }
    function lock(): void {
        root.lockRequested();
        _run("Lock", ["sh", "-c", "loginctl lock-session"]);
    }

    Process {
        id: runner
    }
}
