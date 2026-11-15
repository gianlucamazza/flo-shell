pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth adapter power state through BlueZ.
Singleton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: available && adapter.enabled
    readonly property int connectedCount: {
        let n = 0;
        const devs = Bluetooth.devices.values;
        for (let i = 0; i < devs.length; i++)
            if (devs[i].connected)
                n++;
        return n;
    }

    function setEnabled(on: bool): void {
        if (available)
            adapter.enabled = on;
    }
}
