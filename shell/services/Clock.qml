pragma Singleton

import QtQuick
import Quickshell

// The only periodic wake-up in the shell: once per minute, aligned to the
// minute boundary by SystemClock.
Singleton {
    readonly property date now: clock.date
    readonly property string time: Qt.formatDateTime(clock.date, "HH:mm")
    readonly property string shortDate: Qt.locale().toString(clock.date, "ddd d MMM")
    readonly property string longDate: Qt.locale().toString(clock.date, "dddd d MMMM")

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
