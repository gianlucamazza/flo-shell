pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Backlight control, isolated here so the mechanism can change per device.
//
// Read: sysfs, refreshed after writes as well as file notifications.
// Write: logind Session.SetBrightness when available; brightnessctl otherwise.
// The CLI being installed does not imply permission to write sysfs.
//
// FLO_BACKLIGHT_DIR points the service at a fake directory (files
// `brightness` and `max_brightness`) for development; writes then go
// straight to the file.
Singleton {
    id: root

    property string devicePath: ""
    property int max: 0
    property int raw: 0
    property string method: "" // "brightnessctl" | "logind" | "file"

    readonly property string deviceName: devicePath.substring(devicePath.lastIndexOf("/") + 1)
    readonly property bool available: devicePath !== "" && max > 0 && method !== ""
    readonly property real value: available ? raw / max : 0
    readonly property int minRaw: Math.max(1, Math.round(max * 0.02))

    // Emitted when the level changes after the initial read.
    signal levelChanged

    property int _pending: -1
    property bool _primed: false

    function _selectMethod(logindAvailable: bool, cliAvailable: bool): string {
        return logindAvailable ? "logind" : cliAvailable ? "brightnessctl" : "";
    }

    function set(v: real): void {
        if (!available)
            return;
        const target = Math.max(minRaw, Math.min(max, Math.round(v * max)));
        if (target === raw && _pending < 0)
            return;
        raw = target; // optimistic, confirmed by the file watcher
        _pending = target;
        _pump();
        root.levelChanged();
    }
    function step(delta: real): void {
        set(value + delta);
    }

    // At most one writer process at a time; the newest value wins.
    function _pump(): void {
        if (writer.running || _pending < 0)
            return;
        const t = String(_pending);
        _pending = -1;
        if (method === "brightnessctl")
            writer.command = ["brightnessctl", "-q", "-d", deviceName, "set", t];
        else if (method === "file")
            writer.command = ["sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "sh", t, devicePath + "/brightness"];
        else
            writer.command = ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", deviceName, t];
        writer.running = true;
    }

    Process {
        id: writer
        onExited: code => {
            if (code !== 0)
                console.warn("Backlight write failed (" + root.method + ", exit " + code + ")");
            root._pump();
            // sysfs need not emit an inotify event; failures emit none either.
            if (!writer.running && root._pending < 0)
                file.reload();
        }
    }

    // One-shot discovery at startup.
    Process {
        running: true
        command: ["sh", "-c", "d=\"${FLO_BACKLIGHT_DIR:-}\"; m=; l=0; c=0; "
            + "if [ -n \"$d\" ]; then m=file; else "
            + "for candidate in /sys/class/backlight/*; do [ -e \"$candidate/brightness\" ] && d=\"$candidate\" && break; done; "
            + "command -v busctl >/dev/null 2>&1 && busctl --system status org.freedesktop.login1 >/dev/null 2>&1 && l=1; "
            + "command -v brightnessctl >/dev/null 2>&1 && c=1; fi; "
            + "echo \"$d\"; cat \"$d/max_brightness\" 2>/dev/null || echo 0; echo \"$m\"; echo \"$l\"; echo \"$c\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                if (lines.length < 5 || lines[0] === "")
                    return;
                root.max = parseInt(lines[1]) || 0;
                root.method = lines[2] === "file" ? "file" : root._selectMethod(lines[3] === "1", lines[4] === "1");
                root.devicePath = lines[0];
            }
        }
    }

    FileView {
        id: file
        path: root.devicePath !== "" ? root.devicePath + "/brightness" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            // Keep the newest intent while an older write is still completing.
            if (writer.running || root._pending >= 0)
                return;
            const v = parseInt(file.text());
            if (isNaN(v))
                return;
            const external = root._primed && v !== root.raw && !writer.running && root._pending < 0;
            root.raw = v;
            root._primed = true;
            if (external)
                root.levelChanged();
        }
    }
}
