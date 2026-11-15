import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// Multitasking overview: every open window as a card in a horizontal strip.
// Opaque full-screen surface between the bars (the home bar closes it);
// only the content fades and slides in. Window data and actions go through
// the Compositor adapter only.
PanelWindow {
    id: win

    readonly property bool open: Ui.overviewOpen
    property real progress: open ? 1 : 0

    Behavior on progress {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Theme.easing
        }
    }

    onOpenChanged: {
        if (!open)
            return;
        // Start on the focused window.
        const i = Compositor.windows.indexOf(Compositor.activeWindow);
        if (i >= 0)
            strip.positionViewAtIndex(i, ListView.Center);
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
    WlrLayershell.namespace: "flo-overview"

    Item {
        id: content

        readonly property bool land: width > height
        readonly property int pad: Theme.spaceL

        anchors.fill: parent
        opacity: win.progress
        transform: Translate {
            y: (1 - win.progress) * 28
        }

        Item {
            id: header

            width: parent.width
            height: Theme.touch

            Label {
                x: content.pad
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t("overview.title")
                font.pixelSize: Theme.fontTitle
                font.weight: Font.DemiBold
            }
            Pressable {
                visible: strip.count > 0
                anchors.right: parent.right
                anchors.rightMargin: Theme.spaceXs
                width: closeAllRow.width + 2 * Theme.spaceL
                height: parent.height
                onTapped: {
                    const all = Compositor.windows.slice();
                    for (let i = 0; i < all.length; i++)
                        Compositor.closeWindow(all[i]);
                }

                Row {
                    id: closeAllRow
                    anchors.centerIn: parent
                    spacing: Theme.spaceS

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "trash"
                        color: Theme.textDim
                        size: 20
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.t("overview.closeAll")
                        color: Theme.textDim
                    }
                }
            }
        }

        ListView {
            id: strip

            // Card body keeps the screen's aspect ratio.
            readonly property int cardHeight: Math.min(height, content.land ? height : Math.round(height * 0.78))
            readonly property int cardWidth: Math.max(240, Math.round((cardHeight - Theme.touch) * Device.width / Device.height))

            anchors.top: header.bottom
            anchors.bottom: hint.top
            anchors.bottomMargin: Theme.spaceS
            width: parent.width
            orientation: ListView.Horizontal
            spacing: content.pad
            leftMargin: content.pad
            rightMargin: content.pad
            boundsBehavior: Flickable.StopAtBounds
            model: Compositor.windows

            // The list sets the delegate's y itself: centre the card inside.
            delegate: Item {
                id: slot

                required property var modelData

                width: strip.cardWidth
                height: strip.height

                WindowCard {
                    window: slot.modelData
                    active: win.open
                    width: parent.width
                    height: strip.cardHeight
                    anchors.verticalCenter: parent.verticalCenter
                    onActivated: {
                        Compositor.focusWindow(slot.modelData);
                        Ui.overviewOpen = false;
                    }
                    onDismissed: Compositor.closeWindow(slot.modelData)
                }
            }
        }
        Label {
            visible: strip.count === 0
            anchors.centerIn: strip
            text: I18n.t("overview.empty")
            color: Theme.textDim
        }
        Label {
            id: hint
            visible: strip.count > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceM
            text: I18n.t("overview.hint")
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
        }
    }
}
