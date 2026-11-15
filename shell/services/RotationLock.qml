pragma Singleton

import QtQuick
import Quickshell
import qs

// Manual screen rotation. The tablet's sensors are not usable yet, so the
// orientation is chosen by hand (quick settings tile, IPC) and stays locked
// to that choice: `locked` is always true here. When flo-sessiond gains
// sensor-driven rotation (phase 4) it will clear the lock and drive
// set() itself; the name of this singleton is kept for that reason.
//
// The work is done by the Compositor adapter: monitor transform plus the
// matching touch-device transform.
Singleton {
    id: root

    readonly property bool supported: Compositor.supportsRotation
    readonly property bool locked: true

    // 0..3 as in wl_output: 0, 90, 180, 270 degrees.
    readonly property int transform: Compositor.backend ? Compositor.screenTransform(Device.screen) : 0
    readonly property int degrees: transform * 90
    readonly property bool landscape: Device.landscape

    function set(degrees: int): void {
        const t = Math.round((((degrees % 360) + 360) % 360) / 90) % 4;
        if (!supported) {
            console.info("flo-rotation: not supported by compositor backend", Compositor.backendName);
            return;
        }
        Compositor.setScreenTransform(Device.screen, t);
    }
    // Quick settings tile: 0 -> 90 -> 180 -> 270 -> 0.
    function next(): void {
        set((transform + 1) % 4 * 90);
    }
}
