pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Battery state from UPower (D-Bus property changes, no polling).
Singleton {
    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool available: device !== null && device.ready && device.isPresent
    readonly property int percent: available ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: available && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: available && device.state === UPowerDeviceState.FullyCharged
    readonly property bool plugged: !UPower.onBattery
    readonly property bool low: available && !charging && percent <= 15
}
