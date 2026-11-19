import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// Power menu: full-screen opaque surface. Actions sit in the bottom third
// in portrait and along the right edge in landscape. Power off and reboot
// need a second tap to confirm.
PanelWindow {
    id: win

    readonly property bool open: Ui.powerMenuOpen
    property real progress: open ? 1 : 0
    property string armed: ""

    readonly property var actions: [
        { key: "lock", label: I18n.t("power.lock"), icon: "lock", confirm: false },
        { key: "suspend", label: I18n.t("power.suspend"), icon: "moon", confirm: false },
        { key: "reboot", label: I18n.t("power.reboot"), icon: "reboot", confirm: true },
        { key: "poweroff", label: I18n.t("power.off"), icon: "power", confirm: true }
    ]

    Behavior on progress {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Theme.easing
        }
    }

    function trigger(action: var): void {
        if (action.confirm && armed !== action.key) {
            armed = action.key;
            return;
        }
        Ui.powerMenuOpen = false;
        if (action.key === "lock")
            Session.lock();
        else if (action.key === "suspend")
            Session.suspend();
        else if (action.key === "reboot")
            Session.reboot();
        else if (action.key === "poweroff")
            Session.powerOff();
    }

    onOpenChanged: armed = ""

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    visible: open || progress > 0
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flo-power"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Item {
        id: content
        Keys.onEscapePressed: Ui.back()

        readonly property bool land: width > height
        readonly property int pad: Theme.spaceXl

        anchors.fill: parent
        opacity: win.progress
        transform: Translate {
            y: (1 - win.progress) * 28
        }

        Column {
            // Portrait: above the buttons. Landscape: centred in the free
            // area left of the button column.
            x: content.land ? Math.round((buttons.x - width) / 2) : content.pad
            y: content.land ? Math.round((content.height - height) / 2) : buttons.y - height - content.pad
            spacing: Theme.spaceXs

            Label {
                text: I18n.t("power.title")
                font.pixelSize: Theme.fontDisplay
                font.weight: Font.DemiBold
            }
            Label {
                text: win.armed !== "" ? I18n.t("power.confirmHint") : Battery.available ? I18n.t("power.battery", Battery.percent) + (Battery.charging ? I18n.t("power.charging") : "") : ""
                color: win.armed !== "" ? Theme.warn : Theme.textDim
            }
        }

        Column {
            id: buttons

            width: content.land ? Theme.sideSheetWidth - 2 * content.pad : content.width - 2 * content.pad
            x: content.width - width - content.pad
            y: content.land ? Math.round((content.height - height) / 2) : content.height - height - content.pad - Theme.homeBarHeight
            spacing: Theme.spaceM

            Grid {
                id: tiles

                columns: content.land ? 1 : 2
                spacing: Theme.spaceM
                width: parent.width

                Repeater {
                    model: win.actions

                    Pressable {
                        id: tile

                        required property var modelData
                        readonly property bool isArmed: win.armed === modelData.key
                        readonly property color fg: isArmed ? Theme.accentText : Theme.text

                        width: Math.floor((tiles.width - (tiles.columns - 1) * tiles.spacing) / tiles.columns)
                        height: content.land ? 76 : 112
                        background: isArmed ? Theme.danger : Theme.surfaceAlt
                        pressedColor: isArmed ? Qt.darker(Theme.danger, 1.2) : Theme.pressed
                        onTapped: win.trigger(modelData)
                        accessibleName: isArmed ? I18n.t("power.confirm") + " " + modelData.label : modelData.label

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spaceM

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: tile.modelData.icon
                                color: tile.fg
                                size: 28
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tile.isArmed ? I18n.t("power.confirm") : tile.modelData.label
                                color: tile.fg
                                font.pixelSize: Theme.fontTitle
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }

            Pressable {
                width: parent.width
                height: Theme.touch
                background: Theme.surface
                onTapped: Ui.powerMenuOpen = false
                accessibleName: I18n.t("common.cancel")

                Label {
                    anchors.centerIn: parent
                    text: I18n.t("common.cancel")
                    color: Theme.textDim
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
