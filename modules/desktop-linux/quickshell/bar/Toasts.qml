import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Wayland

// New notifications, stacked under the bar on the focused monitor.
PanelWindow {
    id: root

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    visible: Notifs.popups.length > 0
    anchors {
        top: true
        right: true
    }
    margins {
        top: 8
        right: 8
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    color: "transparent"
    implicitWidth: 380
    implicitHeight: Math.max(1, column.implicitHeight)

    Column {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            // ScriptModel keeps existing toasts, and their timers, when one is added.
            model: ScriptModel {
                values: Notifs.popups.slice(0, 5)
            }

            NotificationCard {
                id: toast
                required property Notification modelData
                notification: modelData
                width: column.width
                onActivated: Notifs.hidePopup(modelData)

                Timer {
                    running: !toast.hovered && !toast.critical
                    // expireTimeout is in milliseconds, despite the docs saying seconds.
                    interval: toast.modelData.expireTimeout > 0 ? toast.modelData.expireTimeout : 6000
                    onTriggered: Notifs.hidePopup(toast.modelData)
                }

                Connections {
                    target: toast.modelData
                    function onClosed() {
                        Notifs.hidePopup(toast.modelData);
                    }
                }
            }
        }
    }
}
