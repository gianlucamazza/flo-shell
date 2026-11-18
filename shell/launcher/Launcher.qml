import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.components

// Full-screen application grid. The surface is opaque; only its content
// fades/slides in. Search and the open-windows strip sit at the bottom
// (portrait thumb zone) or bottom-right (landscape, right thumb).
PanelWindow {
    id: win

    readonly property bool open: Ui.launcherOpen
    property real progress: open ? 1 : 0
    readonly property var results: {
        // Read tools so this binding re-runs after the one-shot list.
        const _agents = agents.tools;
        return agents.matching(search.text).concat(Apps.search(search.text));
    }
    // True when the search field asked for the on-screen keyboard, so that
    // closing the launcher only hides a keyboard it raised itself.
    property bool raisedKeyboard: false

    Agents {
        id: agents
    }

    Behavior on progress {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Theme.easing
        }
    }

    function launch(entry: var): void {
        if (entry && entry.isSettings) {
            Ui.openAgentSettings();
            return;
        }
        if (entry && entry.isAgent) {
            Sessiond.launching();
            agents.launch(entry.tool);
        } else {
            Apps.launch(entry);
        }
        Ui.launcherOpen = false;
    }

    Component.onCompleted: {
        if (open)
            agents.refresh();
    }
    onOpenChanged: {
        if (open) {
            agents.refresh();
        } else {
            search.text = "";
            search.focus = false;
            if (win.raisedKeyboard)
                Keyboard.hide();
            win.raisedKeyboard = false;
        }
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Normal
    visible: open || progress > 0
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flo-launcher"
    // OnDemand, not Exclusive: an exclusive layer makes Hyprland withhold
    // pointer/touch input from the bars, so the home bar could not close it.
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Item {
        id: content

        readonly property bool land: width > height
        readonly property int m: Theme.spaceM

        anchors.fill: parent
        opacity: win.progress
        transform: Translate {
            y: (1 - win.progress) * 28
        }

        GridView {
            id: grid

            readonly property int columns: Theme.launcherColumns

            x: Math.floor((content.width - cellWidth * columns) / 2)
            width: cellWidth * columns
            height: (strip.visible && !content.land ? strip.y : searchBox.y) - Theme.spaceS
            cellWidth: Math.floor(content.width / columns)
            cellHeight: 116
            topMargin: Theme.spaceS
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Plain array model: ScriptModel's incremental diff dropped rows
            // when going from a filtered list back to the full one.
            model: win.results

            delegate: Pressable {
                id: cell

                required property var modelData
                // modelData is null for an instant while the model shrinks.
                readonly property bool isAgent: !!(modelData && modelData.isAgent)
                readonly property bool isSettings: !!(modelData && modelData.isSettings)
                readonly property string name: modelData ? modelData.name : ""
                readonly property string iconSource: (!modelData || isAgent) ? "" : Apps.iconSource(modelData)

                width: grid.cellWidth
                height: grid.cellHeight
                onTapped: win.launch(modelData)

                IconImage {
                    id: icon
                    visible: cell.iconSource !== ""
                    y: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitSize: Theme.appIconSize
                    asynchronous: true
                    source: cell.iconSource
                }
                // Generic bolt for agent rows (remote tools and Crush): no vendor logos.
                Rectangle {
                    visible: cell.isAgent
                    y: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.appIconSize
                    height: Theme.appIconSize
                    radius: Theme.radius
                    color: Theme.surfaceAlt

                    Icon {
                        anchors.centerIn: parent
                        name: cell.isSettings ? "settings" : "bolt"
                        size: 28
                        color: Theme.accent
                    }
                }
                // Fallback when the icon theme has no match.
                Rectangle {
                    visible: cell.iconSource === "" && !cell.isAgent
                    y: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.appIconSize
                    height: Theme.appIconSize
                    radius: Theme.radius
                    color: Theme.surfaceAlt

                    Label {
                        anchors.centerIn: parent
                        text: cell.name.charAt(0).toUpperCase()
                        font.pixelSize: Theme.fontTitle + 4
                        font.weight: Font.DemiBold
                    }
                }
                Label {
                    y: 14 + Theme.appIconSize + Theme.spaceS
                    x: Theme.spaceXs
                    width: parent.width - 2 * Theme.spaceXs
                    horizontalAlignment: Text.AlignHCenter
                    text: cell.name
                    font.pixelSize: Theme.fontSmall
                }
            }
        }

        Label {
            visible: win.results.length === 0
            anchors.centerIn: grid
            text: I18n.t("launcher.empty")
            color: Theme.textDim
        }

        // Open windows: quick switch/close without leaving the launcher (the
        // full view is overview/Overview.qml). Compositor adapter only.
        ListView {
            id: strip

            visible: count > 0
            x: content.m
            y: content.land ? searchBox.y : searchBox.y - height - Theme.spaceS
            width: content.land ? searchBox.x - 2 * content.m : content.width - 2 * content.m
            height: Theme.touch
            orientation: ListView.Horizontal
            spacing: Theme.spaceS
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Compositor.windows

            delegate: Pressable {
                id: chip

                required property var modelData

                width: 220
                height: strip.height
                background: Theme.surfaceAlt
                onTapped: {
                    Compositor.focusWindow(modelData);
                    Ui.launcherOpen = false;
                }

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spaceL
                    anchors.right: closeButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Compositor.windowTitle(chip.modelData) || Compositor.windowAppId(chip.modelData)
                }
                IconButton {
                    id: closeButton
                    anchors.right: parent.right
                    width: Theme.touch
                    height: parent.height
                    icon: "close"
                    iconColor: Theme.textDim
                    onTapped: Compositor.closeWindow(chip.modelData)
                }
            }
        }

        Rectangle {
            id: searchBox

            width: content.land ? Theme.sideSheetWidth - 2 * content.m : content.width - 2 * content.m
            height: Theme.touch
            x: content.width - width - content.m
            y: content.height - height - content.m
            radius: height / 2
            color: Theme.surfaceAlt
            border.width: search.focus ? 2 : 0
            border.color: Theme.accent

            Icon {
                id: searchIcon
                x: Theme.spaceL + 2
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                color: Theme.textDim
            }
            Label {
                visible: search.text === "" && search.preeditText === ""
                anchors.left: search.left
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t("launcher.search")
                color: Theme.textDim
            }
            TextInput {
                id: search
                anchors.left: searchIcon.right
                anchors.leftMargin: Theme.spaceM
                anchors.right: clearButton.left
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onAccepted: {
                    if (win.results.length > 0)
                        win.launch(win.results[0]);
                }
                Keys.onEscapePressed: Ui.launcherOpen = false
            }
            // The whole pill focuses the field and raises the on-screen
            // keyboard (no auto-focus on open: the keyboard would come up
            // every time). The keyboard's exclusive zone shrinks this
            // surface, which moves the field above the keys.
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: clearButton.width
                onClicked: {
                    search.forceActiveFocus();
                    if (Keyboard.available && !Keyboard.visible) {
                        Keyboard.show();
                        win.raisedKeyboard = true;
                    }
                }
            }
            IconButton {
                id: clearButton
                anchors.right: parent.right
                width: Theme.touch
                height: parent.height
                radius: height / 2
                visible: search.text !== ""
                icon: "close"
                iconColor: Theme.textDim
                onTapped: search.text = ""
            }
        }
    }
}
