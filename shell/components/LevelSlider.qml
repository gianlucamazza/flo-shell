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
    property string label: icon === "sun" ? I18n.t("qs.brightness") : I18n.t("qs.volume")
    readonly property real minimumValue: 0
    readonly property real maximumValue: 1
    readonly property real stepSize: 0.05
    readonly property bool dragging: area.pressed
    readonly property real shown: area.pressed ? area.local : value

    signal moved(real value)
    signal iconTapped

    implicitHeight: Theme.touch + Theme.fontSmall + Theme.spaceXs
    opacity: available ? 1 : 0.4
    enabled: available
    activeFocusOnTab: available
    Accessible.role: Accessible.Slider
    Accessible.name: label
    Accessible.description: Math.round(shown * 100) + "%"
    Accessible.onIncreaseAction: root.moved(Math.min(1, root.value + root.stepSize))
    Accessible.onDecreaseAction: root.moved(Math.max(0, root.value - root.stepSize))
    Keys.onRightPressed: root.moved(Math.min(1, root.value + root.stepSize))
    Keys.onLeftPressed: root.moved(Math.max(0, root.value - root.stepSize))
    Label {
        text: root.label + " · " + Math.round(root.shown * 100) + "%"
        font.pixelSize: Theme.fontSmall
        color: Theme.textDim
    }
    Pressable {
        width: Theme.touchMin; height: Theme.touch
        anchors.left: parent.left; anchors.bottom: parent.bottom
        accessibleName: "− " + root.label
        onTapped: root.moved(Math.max(0, root.value - root.stepSize))
        Label { anchors.centerIn: parent; text: "−"; font.pixelSize: Theme.fontTitle }
    }
    Pressable {
        width: Theme.touchMin; height: Theme.touch
        anchors.right: parent.right; anchors.bottom: parent.bottom
        accessibleName: "+ " + root.label
        onTapped: root.moved(Math.min(1, root.value + root.stepSize))
        Label { anchors.centerIn: parent; text: "+"; font.pixelSize: Theme.fontTitle }
    }

    Rectangle {
        id: track
        x: Theme.touchMin + Theme.spaceXs
        y: parent.height - Theme.touch / 2 - height / 2
        width: parent.width - 2 * (Theme.touchMin + Theme.spaceXs)
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

        x: track.x
        y: parent.height - Theme.touch
        width: track.width
        height: Theme.touch
        enabled: root.available
        preventStealing: true
        onPressed: mouse => {
            local = root.value;
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
