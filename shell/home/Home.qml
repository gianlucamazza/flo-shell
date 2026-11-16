import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// Stable home above preserved app windows, below shell overlays.
PanelWindow {
    id: win
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    visible: Ui.homeOpen && !Session.locked
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "flo-desktop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    Flickable {
        id: scroll
        anchors.fill: parent
        contentHeight: body.height + 2 * body.y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: body
            width: Math.min(scroll.width - 2 * Theme.spaceXl, 760)
            x: Math.round((scroll.width - width) / 2)
            y: Math.max(Theme.spaceXl, Math.min(80, scroll.height * 0.1))
            spacing: Theme.spaceXl
            Column {
                width: parent.width
                spacing: Theme.spaceS
                Label { text: Clock.time; font.pixelSize: Theme.fontClock; font.weight: Font.DemiBold }
                Label { width: parent.width; text: Clock.longDate; color: Theme.textDim; wrapMode: Text.Wrap }
            }
            Label { text: I18n.t("home.shortcuts"); font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold }
            Grid {
                id: shortcuts
                width: parent.width
                columns: Math.max(1, Math.min(4, Math.floor(width / (128 * Theme.textScale))))
                Repeater {
                    model: Apps.shortcuts
                    AppTile {
                        required property DesktopEntry modelData
                        entry: modelData
                        width: shortcuts.width / shortcuts.columns
                        height: implicitHeight
                        onTapped: Apps.launch(entry)
                    }
                }
            }
            Pressable {
                width: parent.width
                height: Theme.touch
                background: Theme.accent
                pressedColor: Qt.darker(Theme.accent, 1.2)
                accessibleName: I18n.t("home.allApps")
                onTapped: Ui.openLauncher()
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spaceM
                    Icon { name: "apps"; color: Theme.accentText; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: I18n.t("home.allApps"); color: Theme.accentText; font.weight: Font.DemiBold }
                }
            }
            Pressable {
                width: parent.width
                height: Theme.touch
                background: Theme.surfaceAlt
                accessibleName: I18n.t("qs.controls")
                onTapped: Ui.openQuickSettings()
                Label { anchors.centerIn: parent; text: I18n.t("qs.controls"); font.weight: Font.DemiBold }
            }
        }
    }
}
