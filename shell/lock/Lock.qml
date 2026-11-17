import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

// Session lock (ext-session-lock-v1). The compositor hides everything else
// while `locked` is true and keeps the session locked if the shell dies:
// see Session.qml for how a restarted shell takes the lock back.
WlSessionLock {
    id: lock

    locked: Session.locked
    onSecureChanged: Session.lockSecure = secure
    Component.onCompleted: Session.lockSecure = secure
    Component.onDestruction: Session.lockSecure = false

    WlSessionLockSurface {
        color: Theme.bg

        LockScreen {
            anchors.fill: parent
            onUnlocked: Session.unlock()
        }
    }
}
