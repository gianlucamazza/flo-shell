import QtQuick
import Quickshell
import Quickshell.Networking

// Network state from Quickshell.Networking (NetworkManager). That module
// only exists in Quickshell >= 0.3, hence the separate, lazily loaded file.
QtObject {
    readonly property bool available: Networking.backend !== NetworkBackendType.None
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wifiHardwareEnabled: Networking.wifiHardwareEnabled

    // { kind: "wifi" | "wired" | "none", name: string, strength: 0..1 }
    readonly property var active: {
        let wifi = null;
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (!d.connected)
                continue;
            if (d.type === DeviceType.Wired)
                return { kind: "wired", name: d.name, strength: 1 };
            if (d.type === DeviceType.Wifi && wifi === null) {
                const nets = d.networks.values;
                for (let j = 0; j < nets.length; j++) {
                    if (nets[j].connected) {
                        wifi = { kind: "wifi", name: nets[j].name, strength: nets[j].signalStrength };
                        break;
                    }
                }
                if (wifi === null)
                    wifi = { kind: "wifi", name: "", strength: 1 };
            }
        }
        return wifi !== null ? wifi : { kind: "none", name: "", strength: 0 };
    }

    function setWifiEnabled(on: bool): void {
        Networking.wifiEnabled = on;
    }
}
