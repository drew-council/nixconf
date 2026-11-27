import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Bell with an unread count. Left click opens history, right click toggles do-not-disturb.
BarButton {
    id: root

    readonly property int count: Notifs.history.length

    text: (Notifs.dnd ? "" : "") + (count > 0 ? ` <font color="${Theme.red}"><sup>${count}</sup></font>` : "")
    textFormat: Text.StyledText
    textColor: Notifs.dnd ? Theme.overlay1 : Theme.text
    tooltip: Notifs.dnd ? "Do not disturb" : ""

    onClicked: button => {
        if (button === Qt.LeftButton) {
            panel.toggle();
            // The panel shows everything, so toasts would only duplicate it.
            if (panel.visible)
                Notifs.popups = [];
        } else if (button === Qt.RightButton) {
            Notifs.dnd = !Notifs.dnd;
        }
    }

    BarPanel {
        id: panel
        owner: root
        title: "Notifications"
        contentHeight: Math.max(list.contentHeight, 60)

        actions: [
            PanelAction {
                text: Notifs.dnd ? "" : ""
                active: Notifs.dnd
                onClicked: Notifs.dnd = !Notifs.dnd
            },
            PanelAction {
                visible: root.count > 0
                text: "Clear"
                hoverColor: Theme.red
                onClicked: Notifs.clear()
            }
        ]

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel {
                values: Notifs.history
            }

            delegate: NotificationCard {
                required property Notification modelData
                notification: modelData
                width: list.width
            }

            Text {
                anchors.centerIn: parent
                visible: root.count === 0
                text: "No notifications"
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }
    }
}
