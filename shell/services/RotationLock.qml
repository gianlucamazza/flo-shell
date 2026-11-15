pragma Singleton

import QtQuick
import Quickshell

// STUB. Rotation follows the accelerometer inside flo-sessiond (phase 4);
// this only holds the lock flag that the daemon will read. Nothing rotates.
Singleton {
    readonly property bool stub: true
    property bool locked: true

    function toggle(): void {
        locked = !locked;
        console.info("flo-rotation: stub, locked =", locked);
    }
}
