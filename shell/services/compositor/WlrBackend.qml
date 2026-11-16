import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Generic backend for wlroots compositors (labwc, sway, phoc):
// wlr-foreign-toplevel-management only. That protocol has no notion of
// workspaces. Rotation goes through wlr-randr when it is installed; touch
// input then follows the output only if the compositor maps it itself.
QtObject {
    id: root

    readonly property var windows: ToplevelManager.toplevels.values
    readonly property var activeWindow: ToplevelManager.activeToplevel
    readonly property var workspaces: []
    readonly property int activeWorkspaceId: -1
    readonly property bool supportsWorkspaces: false
    readonly property bool supportsBack: false
    readonly property bool supportsAppSwitch: false
    readonly property bool supportsDisplayPower: false
    readonly property bool supportsThumbnails: false
    property bool supportsRotation: false
    property int _transform: 0

    function title(w: var): string {
        return w.title;
    }
    function appId(w: var): string {
        return w.appId;
    }
    function captureSource(w: var): var {
        return null;
    }
    // wlr-foreign-toplevel-management carries no process id.
    readonly property bool supportsPid: false
    function pidOf(w: var, cb: var): void {
        cb(-1);
    }
    function focus(w: var): void {
        w.activate();
    }
    function close(w: var): void {
        w.close();
    }
    function focusWorkspace(id: int): void {
    }
    function goBack(): void {
    }
    function setDisplayPower(on: bool): void {
    }

    // wlr-randr cannot be asked cheaply for the current transform: the
    // backend assumes the session starts unrotated and tracks its own calls.
    function transformOf(screen: var): int {
        return _transform;
    }
    function setTransform(screen: var, t: int): void {
        if (!supportsRotation || !screen)
            return;
        _randr.command = ["wlr-randr", "--output", screen.name, "--transform", ["normal", "90", "180", "270"][t]];
        _randr.running = true;
        _transform = t;
    }

    property Process _probe: Process {
        command: ["sh", "-c", "command -v wlr-randr"]
        running: true
        onExited: code => root.supportsRotation = code === 0
    }
    property Process _randr: Process {}
}
