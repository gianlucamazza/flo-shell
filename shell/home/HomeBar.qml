import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// Visible navigation; every action works without a gesture.
PanelWindow {
    id: win
    anchors { bottom: true; left: true; right: true }
    implicitHeight: Theme.homeBarHeight
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Theme.homeBarHeight
    color: Theme.barBg
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "flo-home"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    Row {
        anchors.centerIn: parent
        spacing: Theme.spaceS
        Repeater {
            model: [
                { icon: "back", label: I18n.t("nav.back"), action: "back" },
                { icon: "home", label: I18n.t("nav.home"), action: "home" },
                { icon: "windows", label: I18n.t("nav.overview"), action: "overview" }
            ]
            Pressable {
                id: nav
                required property var modelData
                width: Math.min(128, (win.width - (Keyboard.available ? Theme.touch : 0) - 4 * Theme.spaceS) / 3)
                height: Theme.touch
                accessibleName: modelData.label
                background: modelData.action === "home" && Ui.homeOpen ? Theme.surfaceAlt : "transparent"
                onTapped: {
                    if (modelData.action === "home") Ui.home();
                    else if (modelData.action === "back") Ui.back();
                    else Ui.toggleOverview();
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 1
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: nav.modelData.icon; size: 23 }
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: nav.modelData.label; font.pixelSize: Theme.fontSmall; Accessible.ignored: true }
                }
                DragHandler {
                    target: null
                    xAxis.enabled: false
                    onActiveChanged: {
                        if (active) return;
                        const travel = centroid.scenePressPosition.y - centroid.scenePosition.y;
                        if (travel > Theme.longSwipeThreshold) Ui.openOverview();
                        else if (travel > Theme.swipeThreshold) Ui.openLauncher();
                    }
                }
            }
        }
        IconButton {
            visible: Keyboard.available
            width: Theme.touch
            height: Theme.touch
            icon: "keyboard"
            accessibleName: I18n.t("nav.keyboard")
            iconColor: Keyboard.visible ? Theme.accent : Theme.textDim
            onTapped: Keyboard.toggle()
        }
    }
}
