pragma Singleton

import QtQuick
import Quickshell
import qs

// The only periodic wake-up in the shell: once per minute, aligned to the
// minute boundary by SystemClock.
Singleton {
    // While a hot reload tears the old tree down, the SystemClock and I18n
    // can already be gone and these bindings see undefined (Qt 6.11 warned
    // "Unable to assign [undefined]" on every reload): fall back instead.
    readonly property date now: clock?.date ?? new Date()
    readonly property string time: I18n.time(now) ?? ""
    readonly property string shortDate: I18n.shortDate(now) ?? ""
    readonly property string longDate: I18n.longDate(now) ?? ""

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
