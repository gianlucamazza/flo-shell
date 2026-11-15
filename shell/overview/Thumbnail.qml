import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Low-resolution still of a window.
//
// ScreencopyView captures at the window's full resolution (4.6 MB of
// texture per full-screen window on the tablet). To keep only a small copy,
// one frame is captured each time the overview opens, the view is grabbed
// into an image at most Theme.thumbnailSize on its long side, and the
// capture is dropped again. Costs one GPU read-back per window per opening.
Item {
    id: root

    property var source: null
    property bool active: false
    readonly property int status: image.status

    property var _grab: null

    function refresh(): void {
        if (active && source)
            view.captureSource = source;
    }
    onActiveChanged: refresh()
    onSourceChanged: refresh()
    Component.onCompleted: refresh()

    Image {
        id: image
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignTop
        cache: false
        source: root._grab ? root._grab.url : ""
    }
    ScreencopyView {
        id: view

        // Rendered only for the frame that is being grabbed.
        anchors.fill: parent
        opacity: hasContent ? 1 : 0
        live: false
        onHasContentChanged: {
            if (!hasContent)
                return;
            const s = sourceSize;
            if (s.width <= 0 || s.height <= 0)
                return;
            const k = Theme.thumbnailSize / Math.max(s.width, s.height);
            view.grabToImage(result => {
                root._grab = result;
                view.captureSource = null;
            }, Qt.size(Math.max(1, Math.round(s.width * k)), Math.max(1, Math.round(s.height * k))));
        }
    }
}
