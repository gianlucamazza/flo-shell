import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// Feedback is armed by launch events; no continuously animated spinner.
PanelWindow {
    anchors { bottom: true; left: true; right: true }
    margins { bottom: Theme.homeBarHeight + Theme.spaceS; left: Theme.spaceL; right: Theme.spaceL }
    implicitHeight: Math.max(Theme.touch, message.implicitHeight + 2 * Theme.spaceM)
    exclusionMode: ExclusionMode.Ignore
    visible: Ui.feedback !== "" && !Session.locked
    color: Theme.surfaceAlt
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flo-launch-feedback"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    Label {
        id: message
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.spaceL
        text: Ui.feedback
        wrapMode: Text.Wrap
        maximumLineCount: 2
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text
    }
}
