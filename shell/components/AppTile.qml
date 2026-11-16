import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.services

Pressable {
    id: root
    property DesktopEntry entry: null
    readonly property string name: entry ? entry.name : ""
    readonly property string source: entry ? Apps.iconSource(entry) : ""
    implicitHeight: Theme.appIconSize + 3 * Theme.spaceM + 2 * Theme.fontSmall * 1.3
    accessibleName: name
    enabled: entry !== null
    IconImage {
        visible: root.source !== ""
        source: root.source
        asynchronous: true
        implicitSize: Theme.appIconSize
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.spaceM
    }
    Rectangle {
        visible: root.source === ""
        width: Theme.appIconSize
        height: width
        radius: Theme.radius
        color: Theme.surfaceAlt
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.spaceM
        Label { anchors.centerIn: parent; text: root.name.charAt(0).toUpperCase(); font.pixelSize: Theme.fontTitle }
    }
    Label {
        x: Theme.spaceS
        y: Theme.spaceM + Theme.appIconSize + Theme.spaceS
        width: parent.width - 2 * Theme.spaceS
        text: root.name
        font.pixelSize: Theme.fontSmall
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        maximumLineCount: 2
        Accessible.ignored: true
    }
}
