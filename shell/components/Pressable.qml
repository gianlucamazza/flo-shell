import QtQuick
import qs

// Base touch target. Content sits above the hit area, so nested targets
// (e.g. a close button inside a chip) receive their own taps.
// Press feedback is an immediate colour swap (no
// animation, so the first frame after the touch already shows it).
Item {
    id: root

    property color background: "transparent"
    property color pressedColor: Theme.pressed
    property real radius: Theme.radius
    readonly property alias pressed: area.pressed
    default property alias contentData: holder.data

    signal tapped

    implicitWidth: Theme.touch
    implicitHeight: Theme.touch

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: area.pressed ? root.pressedColor : root.background
    }
    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: root.tapped()
    }
    Item {
        id: holder
        anchors.fill: parent
    }
}
