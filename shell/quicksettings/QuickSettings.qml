import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs
import qs.services
import qs.components
import qs.notifications

// Quick settings + notification history.
// Portrait: full-width sheet, controls in the bottom third (thumb zone),
// history above. Landscape: side sheet on the right edge (right thumb),
// Theme.sideSheetWidth wide, with compact icon-only tiles.
// The surface is opaque; only its content slides/fades in.
PanelWindow {
    id: win

    readonly property bool open: Ui.quickSettingsOpen
    readonly property bool side: Device.landscape
    property real progress: open ? 1 : 0

    Behavior on progress {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Theme.easing
        }
    }

    anchors {
        top: true
        bottom: true
        right: true
        left: !win.side
    }
    implicitWidth: Theme.sideSheetWidth
    exclusionMode: ExclusionMode.Normal
    visible: open || progress > 0
    color: Theme.surface
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flo-quicksettings"

    Item {
        id: content

        readonly property int pad: Theme.spaceL

        anchors.fill: parent
        opacity: win.progress
        transform: Translate {
            x: win.side ? (1 - win.progress) * 32 : 0
            y: win.side ? 0 : (win.progress - 1) * 32
        }

        // ---- Header ------------------------------------------------------
        Item {
            id: header

            width: parent.width
            height: win.side ? Theme.touch : 76

            Label {
                id: bigClock
                visible: !win.side
                x: content.pad
                anchors.verticalCenter: parent.verticalCenter
                text: Clock.time
                font.pixelSize: Theme.fontDisplay
                font.weight: Font.DemiBold
            }
            Label {
                anchors.left: win.side ? parent.left : bigClock.right
                anchors.leftMargin: win.side ? content.pad : Theme.spaceM
                anchors.right: closeButton.left
                anchors.verticalCenter: parent.verticalCenter
                text: Clock.longDate
                color: Theme.textDim
            }
            IconButton {
                id: closeButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.spaceXs
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                onTapped: Ui.quickSettingsOpen = false
            }
        }

        // ---- Notification history ---------------------------------------
        Item {
            id: historyHeader

            anchors.top: header.bottom
            width: parent.width
            height: Theme.touch

            Label {
                x: content.pad
                anchors.verticalCenter: parent.verticalCenter
                text: Notifications.count > 0 ? I18n.t("qs.notificationsCount", Notifications.count) : I18n.t("qs.notifications")
                font.weight: Font.DemiBold
            }
            Pressable {
                visible: Notifications.count > 0
                anchors.right: parent.right
                anchors.rightMargin: Theme.spaceXs
                width: clearRow.width + 2 * Theme.spaceL
                height: parent.height
                onTapped: Notifications.clearAll()

                Row {
                    id: clearRow
                    anchors.centerIn: parent
                    spacing: Theme.spaceS

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "trash"
                        color: Theme.textDim
                        size: 20
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.t("qs.clearAll")
                        color: Theme.textDim
                    }
                }
            }
        }

        ListView {
            id: history

            anchors.top: historyHeader.bottom
            anchors.bottom: controls.top
            anchors.bottomMargin: Theme.spaceM
            x: content.pad
            width: parent.width - 2 * content.pad
            spacing: Theme.spaceS
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Newest first.
            model: Notifications.history.slice().reverse()

            delegate: NotificationCard {
                required property Notification modelData

                notification: modelData
                width: history.width
            }
        }
        Label {
            visible: Notifications.count === 0
            anchors.centerIn: history
            text: I18n.t("qs.none")
            color: Theme.textDim
        }

        // ---- Controls (thumb zone) --------------------------------------
        Column {
            id: controls

            x: content.pad
            width: parent.width - 2 * content.pad
            anchors.bottom: parent.bottom
            anchors.bottomMargin: content.pad
            spacing: Theme.spaceS

            Grid {
                id: tiles

                readonly property real tileWidth: Math.floor((width - (columns - 1) * spacing) / columns)

                width: parent.width
                columns: win.side ? 4 : 2
                spacing: Theme.spaceS

                ToggleTile {
                    width: tiles.tileWidth
                    compact: win.side
                    icon: Network.wifiEnabled ? "wifi" : "wifi-off"
                    label: "Wi-Fi"
                    detail: !Network.wifiEnabled ? I18n.t("qs.off") : Network.active.kind === "wifi" ? (Network.active.name || I18n.t("qs.connected")) : I18n.t("qs.notConnected")
                    active: Network.wifiEnabled
                    available: Network.available && Network.wifiHardwareEnabled
                    onTapped: Network.setWifiEnabled(!Network.wifiEnabled)
                }
                ToggleTile {
                    width: tiles.tileWidth
                    compact: win.side
                    icon: "bluetooth"
                    label: "Bluetooth"
                    detail: !Bt.available ? I18n.t("qs.unavailable") : !Bt.enabled ? I18n.t("qs.off") : Bt.connectedCount > 0 ? I18n.t("qs.connected") : I18n.t("qs.on")
                    active: Bt.enabled
                    available: Bt.available
                    onTapped: Bt.setEnabled(!Bt.enabled)
                }
                ToggleTile {
                    width: tiles.tileWidth
                    compact: win.side
                    // Manual rotation: the device has no usable sensor yet.
                    icon: "rotate"
                    label: I18n.t("qs.rotate")
                    detail: I18n.t(RotationLock.landscape ? "qs.landscape" : "qs.portrait") + (RotationLock.degrees >= 180 ? " " + RotationLock.degrees + "°" : "")
                    available: RotationLock.supported
                    onTapped: RotationLock.next()
                }
                ToggleTile {
                    width: tiles.tileWidth
                    compact: win.side
                    icon: "power"
                    label: I18n.t("qs.power")
                    detail: Battery.available ? Battery.percent + "%" + (Battery.charging ? I18n.t("qs.chargingShort") : "") : ""
                    onTapped: Ui.openPowerMenu()
                }
            }

            LevelSlider {
                width: parent.width
                icon: "sun"
                value: Brightness.value
                available: Brightness.available
                onMoved: v => Brightness.set(v)
            }
            LevelSlider {
                width: parent.width
                icon: Audio.muted ? "volume-mute" : "volume"
                value: Audio.muted ? 0 : Audio.volume
                available: Audio.available
                onMoved: v => Audio.setVolume(v)
                onIconTapped: Audio.toggleMute()
            }
        }
    }
}
