import QtQuick
import qs

// Hit area for the screen-edge bars: a tap or a discrete vertical swipe
// (it does not follow the finger; that kind of gesture belongs to the
// compositor).
//
// By default the swipe is reported when the finger lifts. With `eager` it
// is reported as soon as the travel exceeds Theme.swipeThreshold, which
// feels faster but maps a new surface under a pressed pointer: Hyprland
// then moves pointer focus away and the release never arrives here, which
// swallows the next tap. Whether wl_touch behaves better has to be
// checked on the device before turning this on.
MouseArea {
    id: root

    property bool eager: false
    property real startY: 0
    property bool fired: false

    signal tapped
    signal swipedUp
    // Reported instead of swipedUp when the finger travelled further than
    // longThreshold (0 disables). The pointer is grabbed while pressed, so
    // the travel continues outside the strip.
    signal swipedUpLong
    property real longThreshold: 0
    signal swipedDown

    function direction(y: real): int {
        if (startY - y > Theme.swipeThreshold)
            return -1;
        if (y - startY > Theme.swipeThreshold)
            return 1;
        return 0;
    }
    function report(dir: int, y: real): void {
        if (dir < 0 && longThreshold > 0 && startY - y > longThreshold)
            root.swipedUpLong();
        else if (dir < 0)
            root.swipedUp();
        else
            root.swipedDown();
    }

    onPressed: mouse => {
        startY = mouse.y;
        fired = false;
    }
    onPositionChanged: mouse => {
        if (!eager || !pressed || fired)
            return;
        const dir = direction(mouse.y);
        // An eager upward swipe would fire before it can become a long one.
        if (dir !== 0 && !(dir < 0 && longThreshold > 0)) {
            fired = true;
            report(dir, mouse.y);
        }
    }
    onReleased: mouse => {
        if (fired)
            return;
        const dir = direction(mouse.y);
        if (dir !== 0)
            report(dir, mouse.y);
        else
            root.tapped();
    }
}
