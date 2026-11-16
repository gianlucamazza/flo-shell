import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Hyprland backend: window and workspace state from the Hyprland IPC socket.
//
// The tablet runs a classic (hyprlang) configuration; a development machine
// may run a Lua one, where dispatchers and keywords are Lua expressions.
// Both forms are kept side by side and chosen with Hyprland.usingLua.
QtObject {
    id: root

    readonly property var windows: Hyprland.toplevels.values
    readonly property var activeWindow: Hyprland.activeToplevel
    readonly property var workspaces: Hyprland.workspaces.values.map(ws => ({ id: ws.id, name: ws.name, active: ws.focused }))
    readonly property int activeWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    readonly property bool supportsWorkspaces: true
    readonly property bool lua: Hyprland.usingLua === true

    // The overview is drawn by the shell (see Compositor.showAppSwitcher).
    readonly property bool supportsAppSwitch: false
    // "Back" is a synthetic XF86Back key press: classic configuration only.
    readonly property bool supportsBack: !lua
    readonly property bool supportsDisplayPower: !lua
    readonly property bool supportsRotation: true
    // hyprland-toplevel-export-v1, used by ScreencopyView.
    readonly property bool supportsThumbnails: true

    function title(w: var): string {
        return w.title;
    }
    function appId(w: var): string {
        if (w.wayland)
            return w.wayland.appId;
        return w.lastIpcObject["class"] || "";
    }
    function captureSource(w: var): var {
        return w.wayland;
    }
    // Process id of a window, from `hyprctl -j clients` (the Hyprland module
    // has no pid). Requests made while a query runs wait for the next one,
    // so a window created in between is always found.
    property var _pidBatch: []
    property var _pidWaiting: []
    function pidOf(w: var, cb: var): void {
        _pidWaiting.push({ address: String(w.address).replace(/^0x/, ""), cb: cb });
        _pidRun();
    }
    function _pidRun(): void {
        if (_clients.running || _pidBatch.length > 0 || _pidWaiting.length === 0)
            return;
        _pidBatch = _pidWaiting;
        _pidWaiting = [];
        _clients.running = true;
    }
    function _pidDone(text: string): void {
        const pids = {};
        try {
            const list = JSON.parse(text);
            for (let i = 0; i < list.length; i++)
                pids[String(list[i].address).replace(/^0x/, "")] = list[i].pid;
        } catch (e) {
            console.warn("flo-compositor: cannot parse hyprctl clients:", e);
        }
        const batch = _pidBatch;
        _pidBatch = [];
        for (let i = 0; i < batch.length; i++) {
            const pid = pids[batch[i].address];
            batch[i].cb(typeof pid === "number" && pid > 0 ? pid : -1);
        }
        _pidRun();
    }
    property Process _clients: Process {
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: root._pidDone(text)
        }
        onRunningChanged: root._pidRun()
    }

    function _dispatch(classic: string, lua: string): void {
        Hyprland.dispatch(root.lua ? lua : classic);
    }

    function focus(w: var): void {
        if (w.wayland)
            w.wayland.activate();
        else
            _dispatch("focuswindow address:0x" + w.address, "hl.dsp.focus({ window = \"address:0x" + w.address + "\" })");
    }
    function close(w: var): void {
        if (w.wayland)
            w.wayland.close();
        else
            _dispatch("closewindow address:0x" + w.address, "hl.dsp.window.close({ window = \"address:0x" + w.address + "\" })");
    }
    function focusWorkspace(id: int): void {
        _dispatch("workspace " + id, "hl.dsp.focus({ workspace = " + id + " })");
    }

    function goBack(): void {
        Hyprland.dispatch("sendshortcut , XF86Back, activewindow");
    }
    function setDisplayPower(on: bool): void {
        Hyprland.dispatch("dpms " + (on ? "on" : "off"));
    }

    // ---- Rotation ---------------------------------------------------------
    // Monitor state as reported by `hyprctl -j monitors`, fetched once at
    // start and again after every change. (The Hyprland module's own
    // monitor objects came back empty for the headless output used in
    // development, so the adapter asks for itself.)
    property var _monitors: []

    function _monitor(screen: var): var {
        if (!screen)
            return null;
        for (let i = 0; i < _monitors.length; i++) {
            if (_monitors[i].name === screen.name)
                return _monitors[i];
        }
        return null;
    }
    // wl_output transform of a screen: 0, 1 (90), 2 (180), 3 (270).
    function transformOf(screen: var): int {
        const m = _monitor(screen);
        return m ? m.transform : 0;
    }
    // Re-applies the monitor rule with the same mode, position and scale and
    // a new transform, and rotates touch input to match.
    function setTransform(screen: var, t: int): void {
        const m = _monitor(screen);
        if (!m) {
            console.warn("flo-compositor: no monitor data for the shell screen yet");
            _query.running = true;
            return;
        }
        const mode = m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2);
        const pos = m.x + "x" + m.y;
        if (root.lua)
            _ctl.command = ["hyprctl", "eval", "hl.monitor({ output = \"" + m.name + "\", mode = \"" + mode + "\", position = \"" + pos + "\", scale = " + m.scale + ", transform = " + t + " })"
                + " hl.config({ input = { touchdevice = { transform = " + t + " } } })"];
        else
            _ctl.command = ["hyprctl", "--batch", "keyword monitor " + m.name + "," + mode + "," + pos + "," + m.scale + ",transform," + t
                + " ; keyword input:touchdevice:transform " + t];
        _ctl.running = true;
    }

    property Process _ctl: Process {
        onExited: root._query.running = true
    }
    property Process _query: Process {
        command: ["hyprctl", "-j", "monitors"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._monitors = JSON.parse(text);
                } catch (e) {
                    console.warn("flo-compositor: cannot parse hyprctl monitors:", e);
                }
            }
        }
    }
}
