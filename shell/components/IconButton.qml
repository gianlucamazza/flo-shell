import QtQuick
import qs

// Square icon-only button, one touch target in size.
Pressable {
    id: root

    property string icon
    property color iconColor: Theme.text
    property real iconSize: Theme.iconSize

    Icon {
        anchors.centerIn: parent
        name: root.icon
        color: root.iconColor
        size: root.iconSize
    }
}
