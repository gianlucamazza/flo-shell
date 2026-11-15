pragma Singleton

import QtQuick
import Quickshell

// The ONLY place where the shell talks to a specific compositor.
//
// A backend is a QtObject in services/compositor/ exposing:
//   property var  windows            opaque window handles
//   property var  activeWindow       handle or null
//   property var  workspaces         [{ id: int, name: string, active: bool }]
//   property int  activeWorkspaceId  -1 when unknown
//   property bool supportsWorkspaces
//   function title(w): string        function appId(w): string
//   function focus(w)                function close(w)
//   function focusWorkspace(id)
//   property bool supportsBack / supportsAppSwitch / supportsRotation /
//                 supportsDisplayPower / supportsThumbnails
//   function goBack()                function setDisplayPower(on)
//   function transformOf(screen): int   function setTransform(screen, t)
//   function captureSource(w): var
//
// Everything else in the shell uses this singleton and standard protocols.
Singleton {
    id: root

    // "hyprland" | "wlr". FLO_COMPOSITOR overrides the detection.
    readonly property string backendName: {
        const forced = Quickshell.env("FLO_COMPOSITOR") || "";
        if (forced !== "")
            return forced;
        return (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== "" ? "hyprland" : "wlr";
    }
    readonly property QtObject backend: loader.item

    readonly property var windows: backend ? backend.windows : []
    readonly property var activeWindow: backend ? backend.activeWindow : null
    readonly property var workspaces: backend ? backend.workspaces : []
    readonly property int activeWorkspaceId: backend ? backend.activeWorkspaceId : -1
    readonly property bool supportsWorkspaces: backend ? backend.supportsWorkspaces : false

    function windowTitle(w: var): string { return backend && w ? backend.title(w) : ""; }
    function windowAppId(w: var): string { return backend && w ? backend.appId(w) : ""; }
    function focusWindow(w: var): void { if (backend && w) backend.focus(w); }
    function closeWindow(w: var): void { if (backend && w) backend.close(w); }
    function closeActiveWindow(): void { closeWindow(activeWindow); }
    function focusWorkspace(id: int): void { if (backend) backend.focusWorkspace(id); }

    // ---- Navigation ------------------------------------------------------
    // Finger-following gestures belong to the compositor (plan decision 4);
    // the shell only reacts to discrete triggers (buttons, IPC, key binds).

    // Asks for the multitasking overview. A backend with a native switcher
    // sets supportsAppSwitch and implements showAppSwitcher(); otherwise the
    // request is forwarded to the shell's own overview (see shell.qml).
    signal appSwitcherRequested
    readonly property bool supportsAppSwitch: backend ? backend.supportsAppSwitch === true : false
    function showAppSwitcher(): void {
        if (supportsAppSwitch)
            backend.showAppSwitcher();
        else
            root.appSwitcherRequested();
    }

    // Best effort: sends the XF86Back key to the focused window. Whether
    // anything happens depends on the application (see ARCHITECTURE.md).
    readonly property bool supportsBack: backend ? backend.supportsBack === true : false
    function goBack(): void {
        if (supportsBack && activeWindow)
            backend.goBack();
        else
            console.info("flo-compositor: goBack() has nothing to act on (backend " + backendName + ")");
    }

    // ---- Output ----------------------------------------------------------
    readonly property bool supportsRotation: backend ? backend.supportsRotation === true : false
    readonly property bool supportsDisplayPower: backend ? backend.supportsDisplayPower === true : false
    readonly property bool supportsThumbnails: backend ? backend.supportsThumbnails === true : false

    // wl_output transform (0..3 = 0, 90, 180, 270 degrees) of a screen.
    function screenTransform(screen: var): int { return backend ? backend.transformOf(screen) : 0; }
    function setScreenTransform(screen: var, t: int): void {
        if (supportsRotation)
            backend.setTransform(screen, t);
    }
    function setDisplayPower(on: bool): void {
        if (supportsDisplayPower)
            backend.setDisplayPower(on);
    }
    // Object accepted by ScreencopyView.captureSource, or null.
    function windowCaptureSource(w: var): var { return backend && w && supportsThumbnails ? backend.captureSource(w) : null; }

    Loader {
        id: loader
        source: root.backendName === "hyprland" ? "compositor/HyprlandBackend.qml" : "compositor/WlrBackend.qml"
        onStatusChanged: {
            // e.g. Quickshell built without the Hyprland module.
            if (status === Loader.Error && source.toString().endsWith("HyprlandBackend.qml")) {
                console.warn("flo-compositor: Hyprland backend failed to load, falling back to wlr");
                source = "compositor/WlrBackend.qml";
            }
        }
    }
}
