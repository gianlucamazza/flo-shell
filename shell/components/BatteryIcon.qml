import QtQuick
import qs

// Battery glyph built from rectangles so the fill can track the level.
Item {
    id: root

    property real level: 0 // 0..1
    property bool charging: false
    property bool low: false
    property color color: Theme.text

    implicitWidth: 28
    implicitHeight: 14

    Rectangle {
        id: body
        width: 25
        height: 14
        radius: 3.5
        color: "transparent"
        border.width: 1.5
        border.color: root.color

        Rectangle {
            x: 3
            y: 3
            width: Math.max(2, (parent.width - 6) * Math.max(0, Math.min(1, root.level)))
            height: parent.height - 6
            radius: 1
            color: root.charging ? Theme.ok : root.low ? Theme.danger : root.color
        }
    }
    Rectangle {
        x: 26
        anchors.verticalCenter: body.verticalCenter
        width: 2
        height: 6
        radius: 1
        color: root.color
    }
}
