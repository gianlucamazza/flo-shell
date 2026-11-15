import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// Volume / brightness indicator: a small opaque, non-interactive surface
// above the home bar.
PanelWindow {
    id: win

    readonly property bool isVolume: Ui.osdKind === "volume"
    readonly property real level: isVolume ? (Audio.muted ? 0 : Audio.volume) : Brightness.value

    anchors.bottom: true
    margins.bottom: Theme.spaceXl
    exclusionMode: ExclusionMode.Normal
    implicitWidth: 320
    implicitHeight: Theme.touch
    visible: Ui.osdVisible
    color: Theme.border
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flo-osd"

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: Theme.surfaceAlt

        Icon {
            id: glyph
            x: Theme.spaceL
            anchors.verticalCenter: parent.verticalCenter
            name: win.isVolume ? (Audio.muted ? "volume-mute" : "volume") : "sun"
        }
        Rectangle {
            id: track
            anchors.left: glyph.right
            anchors.leftMargin: Theme.spaceM
            anchors.right: percent.left
            anchors.rightMargin: Theme.spaceS
            anchors.verticalCenter: parent.verticalCenter
            height: 8
            radius: 4
            color: Theme.pressed

            Rectangle {
                width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, win.level)))
                height: parent.height
                radius: 4
                color: Theme.accent
            }
        }
        Label {
            id: percent
            anchors.right: parent.right
            anchors.rightMargin: Theme.spaceL
            anchors.verticalCenter: parent.verticalCenter
            width: 46
            horizontalAlignment: Text.AlignRight
            text: Math.round(win.level * 100) + "%"
        }
    }
}
