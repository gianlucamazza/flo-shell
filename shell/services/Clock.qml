pragma Singleton

import QtQuick
import Quickshell
import qs

// The only periodic wake-up in the shell: once per minute, aligned to the
// minute boundary by SystemClock.
Singleton {
    readonly property date now: clock.date
    readonly property string time: I18n.time(clock.date)
    readonly property string shortDate: I18n.shortDate(clock.date)
    readonly property string longDate: I18n.longDate(clock.date)

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
