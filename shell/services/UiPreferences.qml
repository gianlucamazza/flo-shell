pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Per-user settings. Development uses its private runtime directory.
Singleton {
    id: root
    property real textScale: 1
    property bool reducedMotion: false
    readonly property bool writable: (Quickshell.env("GREETD_SOCK") || "") === ""
    readonly property string directory: (Quickshell.env("FLO_DRY_RUN") === "1"
        ? Quickshell.env("FLO_DEV_RUN") || Quickshell.env("XDG_RUNTIME_DIR")
        : (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/flo-shell")
    property bool ready: false
    function setTextScale(value: real): void {
        textScale = Math.max(1, Math.min(1.5, value));
        save();
    }
    function nextTextScale(): void { setTextScale(textScale < 1.2 ? 1.25 : textScale < 1.4 ? 1.5 : 1); }
    function toggleMotion(): void { reducedMotion = !reducedMotion; save(); }
    function save(): void {
        if (writable && ready)
            store.setText(JSON.stringify({ textScale: textScale, reducedMotion: reducedMotion }) + "\n");
    }
    Process {
        command: ["mkdir", "-p", root.directory]
        running: root.writable
        onExited: code => {
            if (code === 0) {
                store.path = root.directory + "/ui.json";
                root.ready = true;
            }
        }
    }
    FileView {
        id: store
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                const n = Number(data.textScale);
                root.textScale = isFinite(n) ? Math.max(1, Math.min(1.5, n)) : 1;
                root.reducedMotion = data.reducedMotion === true;
            } catch (e) { console.warn("flo-ui: invalid preferences; using defaults"); }
        }
    }
}
