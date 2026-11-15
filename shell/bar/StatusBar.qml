import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// Top status bar. The visible, opaque bar is Theme.barHeight tall and is
// the only part that reserves space; the surface extends below it by an
// invisible strip so that the pull-down gesture has a usable touch height.
PanelWindow {
    id: win

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.edgeTouch
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Theme.barHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "flo-bar"

    Rectangle {
        id: bar
        width: parent.width
        height: Theme.barHeight
        color: Theme.barBg

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceS

            Label {
                text: Clock.time
                font.pixelSize: Theme.fontBar
                font.weight: Font.DemiBold
            }
            Label {
                text: Clock.shortDate
                font.pixelSize: Theme.fontBar
                color: Theme.textDim
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.spaceM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceM

            // Notification count.
            Row {
                visible: Notifications.count > 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "bell"
                    size: 18
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Notifications.count
                    font.pixelSize: Theme.fontBar
                }
            }

            Icon {
                visible: Bt.enabled
                anchors.verticalCenter: parent.verticalCenter
                name: "bluetooth"
                size: 18
                color: Bt.connectedCount > 0 ? Theme.accent : Theme.text
            }

            // Network: Wi-Fi or wired only (no modem on this device).
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                size: 18
                name: Network.active.kind === "wifi" ? "wifi" : Network.active.kind === "wired" ? "wired" : Network.wifiEnabled ? "offline" : "wifi-off"
                color: Network.connected ? Theme.text : Theme.textDim
            }

            Row {
                visible: Battery.available
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spaceXs

                Icon {
                    visible: Battery.charging
                    anchors.verticalCenter: parent.verticalCenter
                    name: "bolt"
                    size: 16
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
                    font.pixelSize: Theme.fontBar
                    color: Battery.low ? Theme.danger : Theme.text
                }
            }
        }
    }

    // Tap toggles the quick settings; a downward drag opens them, an upward
    // one closes them. The gesture is a discrete trigger, it does not track
    // the finger (finger-following motion belongs to the compositor).
    EdgeArea {
        anchors.fill: parent
        onTapped: Ui.toggleQuickSettings()
        onSwipedDown: Ui.openQuickSettings()
        onSwipedUp: Ui.quickSettingsOpen = false
    }
}
