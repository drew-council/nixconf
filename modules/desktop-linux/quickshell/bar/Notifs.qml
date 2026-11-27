pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The notification daemon: history, toasts, and do-not-disturb.
Singleton {
    id: root

    property bool dnd: false
    // Notifications currently shown as toasts, newest first.
    property var popups: []
    // Every notification not yet dismissed, newest first.
    readonly property var history: server.trackedNotifications.values.slice().reverse()

    function hidePopup(n) {
        popups = popups.filter(p => p !== n);
        if (n.transient)
            n.expire();
    }

    function clear() {
        for (const n of history)
            n.dismiss();
    }

    NotificationServer {
        id: server
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.popups = [n, ...root.popups];
            else if (n.transient)
                n.expire();
        }
    }
}
