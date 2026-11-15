import QtQuick
import Quickshell
import Quickshell.Wayland

// Generic backend for wlroots compositors (labwc, sway, phoc):
// wlr-foreign-toplevel-management only. That protocol has no notion of
// workspaces.
QtObject {
    readonly property var windows: ToplevelManager.toplevels.values
    readonly property var activeWindow: ToplevelManager.activeToplevel
    readonly property var workspaces: []
    readonly property int activeWorkspaceId: -1
    readonly property bool supportsWorkspaces: false
    readonly property bool supportsBack: false
    readonly property bool supportsAppSwitch: false

    function title(w: var): string {
        return w.title;
    }
    function appId(w: var): string {
        return w.appId;
    }
    function focus(w: var): void {
        w.activate();
    }
    function close(w: var): void {
        w.close();
    }
    function focusWorkspace(id: int): void {
    }
}
