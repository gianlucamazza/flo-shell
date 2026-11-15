import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// Bottom home bar: the device has no hardware home/back keys. A thin opaque
// bar reserves Theme.homeBarHeight; the surface reaches further up with an
// invisible strip so that the touch target is Theme.edgeTouch tall.
//
//   tap             home (dismiss what is open, else launcher)
//   swipe up        launcher
//   long swipe up   overview of the open windows
//   right corner    on-screen keyboard toggle (when a keyboard is installed)
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
        Icon {
            visible: Keyboard.available
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width - keyboardButton.width / 2 - width / 2
            name: "keyboard"
            size: 18
            color: keyboardButton.pressed || Keyboard.visible ? Theme.accent : Theme.textDim
        }
    }

    EdgeArea {
        id: area
        anchors.fill: parent
        longThreshold: Theme.longSwipeThreshold
        onTapped: Ui.home()
        onSwipedUp: Ui.openLauncher()
        onSwipedUpLong: Compositor.showAppSwitcher()
    }

    // Keyboard toggle. The strip is only Theme.edgeTouch tall, so the target
    // is made wider than a regular one to compensate.
    MouseArea {
        id: keyboardButton
        visible: Keyboard.available
        anchors.right: parent.right
        width: Theme.touch + Theme.spaceL
        height: parent.height
        onClicked: Keyboard.toggle()
    }
}
