import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

// Bottom home bar: the device has no hardware home/back keys. A thin opaque
// bar reserves Theme.homeBarHeight; the surface reaches further up with an
// invisible strip so that the tap / swipe-up target is Theme.edgeTouch tall.
PanelWindow {
    id: win

    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: Theme.edgeTouch
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Theme.homeBarHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "flo-home"

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Theme.homeBarHeight
        color: Theme.barBg

        Rectangle {
            anchors.centerIn: parent
            width: 132
            height: 5
            radius: 2.5
            color: area.pressed ? Theme.accent : Theme.textDim
        }
    }

    MouseArea {
        id: area

        property real startY: 0
        property bool fired: false

        anchors.fill: parent
        onPressed: mouse => {
            startY = mouse.y;
            fired = false;
        }
        onPositionChanged: mouse => {
            if (!fired && startY - mouse.y > Theme.swipeThreshold) {
                fired = true;
                Ui.openLauncher();
            }
        }
        onReleased: {
            if (!fired)
                Ui.home();
        }
    }
}
