pragma Singleton

import QtQuick
import Quickshell

// Physical facts about the target device (Nexus 7 2013 "flo").
// Components must read sizes and capabilities from here (through Theme),
// never hard-code them.
Singleton {
    id: root

    readonly property string model: "Nexus 7 2013 (flo)"

    // Panel: 7.02" IPS, 1200x1920, 323 ppi, used at integer scale 2.
    readonly property int nativeShort: 1200
    readonly property int nativeLong: 1920
    readonly property real ppi: 323
    readonly property int scale: 2
    readonly property int logicalShort: nativeShort / scale // 600
    readonly property int logicalLong: nativeLong / scale   // 960
    readonly property real logicalDpi: ppi / scale          // ~161
    readonly property real pxPerMm: logicalDpi / 25.4       // ~6.36

    // Capabilities.
    readonly property bool hasModem: false        // Wi-Fi model: no mobile-signal UI
    readonly property bool hasHardwareHome: false // navigation is on screen
    readonly property bool hasHardwareBack: false
    readonly property bool hasVolumeKeys: true
    readonly property bool hasCharger: true
    readonly property int batteryMah: 3950

    // Live output state. Falls back to the portrait logical size before the
    // compositor has announced an output.
    readonly property ShellScreen screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    readonly property int width: screen ? screen.width : logicalShort
    readonly property int height: screen ? screen.height : logicalLong
    readonly property bool landscape: width > height

    // Millimetres to logical pixels.
    function mm(v: real): int {
        return Math.round(v * pxPerMm);
    }
}
