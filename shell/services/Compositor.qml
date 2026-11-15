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

    // ---- Gesture hooks (HOOK, not implemented) ----------------------------
    // Finger-following gestures (back, app switch) belong to the compositor
    // (plan decision 4). When a backend gains them it sets these flags and
    // implements the functions; the shell only calls them from discrete
    // triggers (buttons, IPC).
    readonly property bool supportsBack: backend ? backend.supportsBack === true : false
    readonly property bool supportsAppSwitch: backend ? backend.supportsAppSwitch === true : false
    function goBack(): void {
        if (supportsBack)
            backend.goBack();
        else
            console.info("flo-compositor: goBack() hook not implemented by backend", backendName);
    }
    function showAppSwitcher(): void {
        if (supportsAppSwitch)
            backend.showAppSwitcher();
        else
            console.info("flo-compositor: showAppSwitcher() hook not implemented by backend", backendName);
    }

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
