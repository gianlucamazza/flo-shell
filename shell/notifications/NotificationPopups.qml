import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs
import qs.services

// Popup stack: one small opaque surface holding up to Theme.maxPopups
// cards. Top-centre in portrait, top-right in landscape (right thumb).
// The surface height follows the stack in steps; it is never animated.
PanelWindow {
    id: win

    anchors {
        top: true
        right: Device.landscape
    }
    margins {
        top: Theme.spaceS
        right: Device.landscape ? Theme.spaceS : 0
    }
    exclusionMode: ExclusionMode.Normal
    implicitWidth: Device.landscape ? Theme.sideSheetWidth : Math.min(Device.width - 2 * Theme.spaceL, 520)
    implicitHeight: Math.max(1, stack.height + 2)
    visible: Notifications.popups.length > 0
    color: Theme.border
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flo-notifications"

    Column {
        id: stack

        x: 1
        y: 1
        width: parent.width - 2
        spacing: 1

        Repeater {
            model: Notifications.popups

            NotificationCard {
                id: card

                required property Notification modelData

                notification: modelData
                popup: true
                width: stack.width
                radius: 0
                background: Theme.surface
                onActivated: Notifications.hidePopup(modelData)

                // The stack is rebuilt whenever it changes; only a card that
                // has not been on screen yet animates in.
                Component.onCompleted: {
                    if (Notifications.markShown(modelData)) {
                        opacity = 0;
                        shift.y = -12;
                        appear.start();
                    }
                }

                transform: Translate {
                    id: shift
                }
                ParallelAnimation {
                    id: appear
                    NumberAnimation {
                        target: card
                        property: "opacity"
                        to: 1
                        duration: Theme.animNormal
                        easing.type: Theme.easing
                    }
                    NumberAnimation {
                        target: shift
                        property: "y"
                        to: 0
                        duration: Theme.animNormal
                        easing.type: Theme.easing
                    }
                }

                // One-shot expiry, re-armed when the stack changes. Critical
                // notifications stay until dismissed.
                Timer {
                    running: card.modelData.urgency !== NotificationUrgency.Critical
                    interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout * 1000 : Theme.popupTimeout
                    onTriggered: Notifications.hidePopup(card.modelData)
                }
            }
        }
    }
}
