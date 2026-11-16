import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.components

// One open window in the overview: header (icon, title, close) and a body
// that shows the application icon or, when Theme.overviewThumbnails is on
// and the compositor supports it, a still capture of the window.
//
// Tap focuses the window; dragging the card up beyond
// Theme.dismissThreshold (or tapping the X) closes it. Only the card's
// transform and opacity change while dragging.
Item {
    id: root

    required property var window
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: title || appId
    Accessible.onPressAction: root.activated()
    Keys.onReturnPressed: root.activated()
    Keys.onSpacePressed: root.activated()
    // True while the overview is on screen: captures are taken on opening.
    property bool active: false

    readonly property string title: Compositor.windowTitle(window)
    readonly property string appId: Compositor.windowAppId(window)
    readonly property DesktopEntry entry: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
    readonly property string iconSource: entry ? Apps.iconSource(entry) : appId !== "" ? Quickshell.iconPath(appId, true) : ""
    readonly property bool focused: Compositor.activeWindow === window
    readonly property int headerHeight: Theme.touch

    signal activated
    signal dismissed

    function dismiss(): void {
        if (!leave.running)
            leave.start();
    }

    Item {
        id: card

        width: parent.width
        height: parent.height
        opacity: 1 - Math.min(1, -shift.y / (root.height * 0.6))
        transform: Translate {
            id: shift
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.surface
            border.width: root.focused ? 2 : 1
            border.color: root.focused ? Theme.accent : Theme.border
        }

        // Body: icon, or the thumbnail over it once it is ready.
        Item {
            id: body

            x: Theme.spaceS
            y: root.headerHeight
            width: parent.width - 2 * Theme.spaceS
            height: parent.height - root.headerHeight - Theme.spaceS
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius - 4
                color: Theme.surfaceAlt
            }
            IconImage {
                visible: root.iconSource !== "" && !thumb.ready
                anchors.centerIn: parent
                implicitSize: Theme.appIconSize + 16
                asynchronous: true
                source: root.iconSource
            }
            Label {
                visible: root.iconSource === "" && !thumb.ready
                anchors.centerIn: parent
                text: (root.title || root.appId).charAt(0).toUpperCase()
                font.pixelSize: Theme.fontDisplay
                font.weight: Font.DemiBold
                color: Theme.textDim
            }
            Loader {
                id: thumb

                // True once a downscaled copy of the capture exists.
                readonly property bool ready: item !== null && item.status === Image.Ready

                anchors.fill: parent
                active: Theme.overviewThumbnails && Compositor.supportsThumbnails
                sourceComponent: Thumbnail {
                    source: Compositor.windowCaptureSource(root.window)
                    active: root.active
                }
            }
        }

        // Tap and vertical drag for the whole card. Declared before the
        // header controls so that the close button stays on top.
        Item {
            anchors.fill: parent

            TapHandler {
                onTapped: root.activated()
            }
            DragHandler {
                id: drag

                readonly property real travel: Math.min(0, centroid.scenePosition.y - centroid.scenePressPosition.y)

                target: null
                xAxis.enabled: false
                onTravelChanged: {
                    if (active)
                        shift.y = travel;
                }
                onActiveChanged: {
                    if (active)
                        return;
                    if (shift.y < -Theme.dismissThreshold)
                        leave.start();
                    else
                        settle.start();
                }
            }
        }

        IconImage {
            id: smallIcon
            visible: root.iconSource !== ""
            x: Theme.spaceM
            y: Math.round((root.headerHeight - height) / 2)
            implicitSize: 28
            asynchronous: true
            source: root.iconSource
        }
        Label {
            anchors.left: smallIcon.visible ? smallIcon.right : parent.left
            anchors.leftMargin: smallIcon.visible ? Theme.spaceS : Theme.spaceM
            anchors.right: closeButton.left
            y: Math.round((root.headerHeight - height) / 2)
            text: root.title || root.appId
            font.weight: Font.DemiBold
        }
        IconButton {
            id: closeButton
            anchors.right: parent.right
            width: Theme.touch
            height: root.headerHeight
            icon: "close"
            accessibleName: I18n.t("common.close") + ": " + root.title
            iconColor: Theme.textDim
            onTapped: root.dismiss()
        }
    }

    NumberAnimation {
        id: settle
        target: shift
        property: "y"
        to: 0
        duration: Theme.animFast
        easing.type: Theme.easing
    }
    // Fly out, ask the window to close, then come back: if the application
    // refuses (unsaved work), the card must not stay hidden.
    SequentialAnimation {
        id: leave

        NumberAnimation {
            target: shift
            property: "y"
            to: -root.height * 0.6
            duration: Theme.animNormal
            easing.type: Theme.easing
        }
        ScriptAction {
            script: root.dismissed()
        }
        PauseAnimation {
            duration: 600
        }
        NumberAnimation {
            target: shift
            property: "y"
            to: 0
            duration: Theme.animNormal
            easing.type: Theme.easing
        }
    }
}
