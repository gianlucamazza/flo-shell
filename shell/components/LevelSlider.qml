import QtQuick
import qs

// Thick horizontal slider, 0..1. The whole row (one touch target tall) is
// draggable. The fill is a childless rectangle, so resizing it while
// dragging does not relayout anything.
Item {
    id: root

    property real value: 0
    property string icon
    property bool available: true
    readonly property bool dragging: area.pressed
    readonly property real shown: area.pressed ? area.local : value

    signal moved(real value)
    signal iconTapped

    implicitHeight: Theme.touch
    opacity: available ? 1 : 0.4

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 44
        radius: height / 2
        color: Theme.surfaceAlt

        Rectangle {
            width: Math.max(parent.height, root.shown * parent.width)
            height: parent.height
            radius: height / 2
            color: Theme.accent
        }
        Icon {
            x: 11
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            color: Theme.accentText
            size: 22
        }
    }

    MouseArea {
        id: area

        property real local: 0

        function update(mx: real): void {
            local = Math.max(0, Math.min(1, mx / width));
            root.moved(local);
        }

        anchors.fill: parent
        enabled: root.available
        preventStealing: true
        onPressed: mouse => {
            // A tap on the icon end is a separate action (e.g. mute).
            if (mouse.x < Theme.touchMin)
                return;
            update(mouse.x);
        }
        onPositionChanged: mouse => {
            if (pressed)
                update(mouse.x);
        }
        onClicked: mouse => {
            if (mouse.x < Theme.touchMin)
                root.iconTapped();
        }
    }
}
