import QtQuick
import qs

// Square icon-only button, one touch target in size.
Pressable {
    id: root

    property string icon
    property color iconColor: Theme.text
    property real iconSize: Theme.iconSize
    accessibleName: icon === "close" ? I18n.t("common.close") : icon === "eye" ? I18n.t("lock.showPassword") : icon === "keyboard" ? I18n.t("nav.keyboard") : icon

    Icon {
        anchors.centerIn: parent
        name: root.icon
        color: root.iconColor
        size: root.iconSize
    }
}
