pragma Singleton

import QtQuick
import Quickshell

// Network state. This device has no modem (Device.hasModem === false): only
// Wi-Fi and wired/USB links are reported.
//
// The implementation lives in services/network/ and is loaded at run time,
// because Quickshell.Networking is missing from Quickshell < 0.3. If it
// cannot be loaded the shell still starts and reports "not available".
Singleton {
    id: root

    readonly property QtObject backend: loader.item

    readonly property bool available: backend ? backend.available : false
    readonly property bool wifiEnabled: backend ? backend.wifiEnabled : false
    readonly property bool wifiHardwareEnabled: backend ? backend.wifiHardwareEnabled : false

    // { kind: "wifi" | "wired" | "none", name: string, strength: 0..1 }
    readonly property var active: backend ? backend.active : ({ kind: "none", name: "", strength: 0 })
    readonly property bool connected: active.kind !== "none"

    function setWifiEnabled(on: bool): void {
        if (backend)
            backend.setWifiEnabled(on);
    }

    Loader {
        id: loader
        source: "network/NetworkingBackend.qml"
        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("flo-network: Quickshell.Networking not available, network state disabled");
        }
    }
}
