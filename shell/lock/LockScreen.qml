import QtQuick
import qs
import qs.services
import qs.components

// Lock screen content: clock, date, battery, the number of notifications
// (never their content) and the PIN / password pad.
// Portrait: clock on top, pad in the lower part (thumb zone).
// Landscape: clock on the left, pad on the right; with the text keyboard
// open the pad takes the whole width and the clock steps aside.
Rectangle {
    id: root

    readonly property bool land: width > height
    readonly property bool wide: land && !pad.textMode
    readonly property int margin: Theme.spaceXl

    signal unlocked

    color: Theme.bg

    Auth {
        id: auth
        backend: "pam"
        onSucceeded: root.unlocked()
    }

    Connections {
        target: Ui
        function onDevInput(text: string): void {
            pad.devType(text);
        }
    }

    // ---- Status line -----------------------------------------------------
    Row {
        x: root.margin
        y: Theme.spaceL
        spacing: Theme.spaceS
        visible: Notifications.count > 0

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "bell"
            size: 20
            color: Theme.textDim
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Notifications.count === 1 ? I18n.t("lock.notifications.one") : I18n.t("lock.notifications.many", Notifications.count)
            color: Theme.textDim
        }
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: root.margin
        y: Theme.spaceL
        spacing: Theme.spaceS
        visible: Battery.available

        Icon {
            visible: Battery.charging
            anchors.verticalCenter: parent.verticalCenter
            name: "bolt"
            size: 18
            color: Theme.ok
        }
        BatteryIcon {
            anchors.verticalCenter: parent.verticalCenter
            level: Battery.percent / 100
            charging: Battery.charging
            low: Battery.low
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Battery.percent + "%"
            color: Battery.low ? Theme.danger : Theme.textDim
        }
    }

    // ---- Clock -----------------------------------------------------------
    Column {
        id: clock

        visible: !(root.land && pad.textMode)
        x: root.wide ? Math.round((root.width / 2 - width) / 2) : Math.round((root.width - width) / 2)
        y: root.wide ? Math.round((root.height - height) / 2) : Math.max(Theme.touch, Math.round((pad.y - height) / 2))
        spacing: Theme.spaceXs

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Clock.time
            font.pixelSize: pad.textMode ? Theme.fontDisplay : Theme.fontClock
            font.weight: Font.DemiBold
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Clock.longDate
            color: Theme.textDim
        }
        Label {
            visible: auth.dry
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.t("lock.dryRun")
            color: Theme.warn
            font.pixelSize: Theme.fontSmall
        }
    }

    // ---- Pad -------------------------------------------------------------
    AuthPad {
        id: pad

        x: root.wide ? Math.round(root.width / 2) : 0
        width: root.wide ? Math.round(root.width / 2) : root.width
        y: root.wide ? Math.round((root.height - height) / 2) : root.height - height - Theme.spaceL
        prompt: I18n.t(textMode ? "lock.enterPassword" : "lock.enterPin")
        status: auth.status
        statusIsError: auth.statusIsError
        busy: auth.busy
        onSubmitted: secret => auth.submit(secret)
        onEdited: auth.clearStatus()
        Component.onCompleted: forceActiveFocus()
    }
}
