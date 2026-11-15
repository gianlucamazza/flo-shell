import QtQuick
import Quickshell
import Quickshell.Hyprland

// Hyprland backend: window and workspace state from the Hyprland IPC socket.
QtObject {
    readonly property var windows: Hyprland.toplevels.values
    readonly property var activeWindow: Hyprland.activeToplevel
    readonly property var workspaces: Hyprland.workspaces.values.map(ws => ({ id: ws.id, name: ws.name, active: ws.focused }))
    readonly property int activeWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    readonly property bool supportsWorkspaces: true
    readonly property bool supportsBack: false
    readonly property bool supportsAppSwitch: false

    function title(w: var): string {
        return w.title;
    }
    function appId(w: var): string {
        if (w.wayland)
            return w.wayland.appId;
        return w.lastIpcObject["class"] || "";
    }
    // Recent Hyprland can run with a Lua configuration, in which case
    // dispatchers are Lua expressions instead of the classic "name args".
    function _dispatch(classic: string, lua: string): void {
        Hyprland.dispatch(Hyprland.usingLua === true ? lua : classic);
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
}
