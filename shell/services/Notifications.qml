pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs

// org.freedesktop.Notifications server.
// History = every notification still tracked by the server (dismissing one
// removes it). Popups = the short-lived subset shown on screen.
Singleton {
    id: root

    readonly property var history: server.trackedNotifications.values
    readonly property int count: history.length
    property var popups: []

    // Arrival times by notification id (Notification carries none).
    property var _times: ({})

    // Ids whose popup already played its entrance animation.
    property var _shown: ({})

    // Returns true the first time it is called for a notification.
    function markShown(n: Notification): bool {
        if (_shown[n.id])
            return false;
        _shown[n.id] = true;
        return true;
    }

    function timeOf(n: Notification): string {
        const t = _times[n.id];
        return t ? Qt.formatTime(t, "HH:mm") : "";
    }

    function dismiss(n: Notification): void {
        n.dismiss();
    }
    function clearAll(): void {
        const all = history.slice();
        for (let i = 0; i < all.length; i++)
            all[i].dismiss();
    }

    // Remove from the popup stack; the notification stays in the history
    // unless the sender marked it transient.
    function hidePopup(n: Notification): void {
        _drop(n);
        if (n.transient)
            n.expire();
    }
    function _drop(n: QtObject): void {
        const i = popups.indexOf(n);
        if (i < 0)
            return;
        const next = popups.slice();
        next.splice(i, 1);
        popups = next;
    }

    function invokeDefault(n: Notification): bool {
        for (let i = 0; i < n.actions.length; i++) {
            if (n.actions[i].identifier === "default") {
                n.actions[i].invoke();
                return true;
            }
        }
        return false;
    }

    // Opening the history replaces the popups.
    Connections {
        target: Ui
        function onQuickSettingsOpenChanged(): void {
            if (Ui.quickSettingsOpen)
                root.popups = [];
        }
    }

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        actionsSupported: true
        imageSupported: false
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            root._times[n.id] = new Date();
            n.closed.connect(() => {
                root._drop(n);
                delete root._times[n.id];
                delete root._shown[n.id];
            });
            if (Ui.quickSettingsOpen)
                return; // the history list is on screen
            delete root._shown[n.id]; // an updated notification animates again
            const next = root.popups.filter(p => p !== n);
            next.unshift(n);
            root.popups = next.slice(0, Theme.maxPopups);
        }
    }
}
