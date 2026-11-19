import QtQuick
import qs

// Quick settings tile: icon, label and one line of state.
Pressable {
    id: root

    property string icon
    property string label
    property string detail
    property bool active: false
    property bool checkable: false
    property bool available: true
    // Icon only, for narrow sheets. The tile stays a full touch target.
    property bool compact: false
    property color activeColor: Theme.accent

    readonly property color fg: active ? Theme.accentText : Theme.text

    implicitHeight: compact ? Theme.touch : Math.max(86, 3 * Theme.fontBody * 1.3 + 2 * Theme.spaceM)
    background: active ? activeColor : Theme.surfaceAlt
    pressedColor: active ? Qt.darker(activeColor, 1.2) : Theme.pressed
    opacity: available ? 1 : 0.45
    enabled: available
    accessibleName: label + (detail !== "" ? ", " + detail : "")
    Accessible.checkable: checkable
    Accessible.checked: checkable && active
    Accessible.onToggleAction: if (root.checkable && root.enabled) root.tapped()

    Icon {
        id: glyph
        x: root.compact ? Math.round((root.width - width) / 2) : Theme.spaceM
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        color: root.fg
    }
    Column {
        visible: !root.compact
        anchors.left: glyph.right
        anchors.leftMargin: Theme.spaceS + 2
        anchors.right: parent.right
        anchors.rightMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Label {
            width: parent.width
            text: root.label
            wrapMode: Text.Wrap
            maximumLineCount: 2
            color: root.fg
            font.weight: Font.DemiBold
        }
        Label {
            width: parent.width
            visible: text !== ""
            text: root.detail
            color: root.active ? Theme.accentText : Theme.textDim
            font.pixelSize: Theme.fontSmall
        }
    }
}
