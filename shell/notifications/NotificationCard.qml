import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs
import qs.services
import qs.components

// One notification, used by both the popup stack and the history list.
Item {
    id: root

    required property Notification notification
    property bool popup: false
    property color background: Theme.surfaceAlt
    property real radius: Theme.radius

    signal activated

    implicitHeight: Math.max(Theme.touch, column.height + 2 * Theme.spaceM)

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: area.pressed ? Theme.pressed : root.background
    }
    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: {
            Notifications.invokeDefault(root.notification);
            root.activated();
        }
    }

    Column {
        id: column

        x: Theme.spaceL
        y: Theme.spaceM
        width: parent.width - Theme.spaceL - dismissButton.width
        spacing: 2

        Label {
            width: parent.width
            text: {
                const app = root.notification.appName;
                const time = Notifications.timeOf(root.notification);
                return app !== "" && time !== "" ? app + " · " + time : app + time;
            }
            color: root.notification.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.textDim
            font.pixelSize: Theme.fontSmall
        }
        Label {
            width: parent.width
            text: root.notification.summary
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
        Label {
            width: parent.width
            visible: text !== ""
            text: root.notification.body
            color: Theme.textDim
            wrapMode: Text.Wrap
            maximumLineCount: root.popup ? 2 : 4
        }

        // Explicit actions ("default" is the tap on the card itself).
        Flow {
            width: parent.width
            topPadding: visible ? Theme.spaceS : 0
            spacing: Theme.spaceS
            visible: actionRepeater.count > 0

            Repeater {
                id: actionRepeater
                model: root.notification.actions.filter(a => a.identifier !== "default")

                Pressable {
                    id: actionButton

                    required property NotificationAction modelData

                    width: Math.max(Theme.touch + Theme.spaceXl, actionLabel.implicitWidth + 2 * Theme.spaceL)
                    height: Theme.touchMin
                    accessibleName: modelData.text
                    background: Theme.bg
                    onTapped: {
                        modelData.invoke();
                        root.activated();
                    }

                    Label {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: actionButton.modelData.text
                        color: Theme.accent
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    IconButton {
        id: dismissButton
        anchors.right: parent.right
        width: Theme.touch
        height: Theme.touch
        icon: "close"
        iconColor: Theme.textDim
        onTapped: Notifications.dismiss(root.notification)
    }
}
