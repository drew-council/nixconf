import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Bell with an unread count. Left click opens history, right click toggles do-not-disturb.
BarButton {
    id: root

    readonly property int count: Notifs.history.length
    // When the panel last closed. Clicking the bell to close it also
    // dismisses the grab, and that same click must not reopen it.
    property real closedAt: 0

    text: (Notifs.dnd ? "" : "") + (count > 0 ? ` <font color="${Theme.red}"><sup>${count}</sup></font>` : "")
    textFormat: Text.StyledText
    textColor: Notifs.dnd ? Theme.overlay1 : Theme.text
    tooltip: Notifs.dnd ? "Do not disturb" : ""

    onClicked: button => {
        if (button === Qt.LeftButton) {
            if (!panel.visible && Date.now() - closedAt < 250)
                return;
            panel.visible = !panel.visible;
            // The panel shows everything, so toasts would only duplicate it.
            if (panel.visible)
                Notifs.popups = [];
        }
        else if (button === Qt.RightButton)
            Notifs.dnd = !Notifs.dnd;
    }

    PopupWindow {
        id: panel

        // Hang from the bar's bottom-right corner, lined up with the toasts.
        anchor.window: root.QsWindow.window
        anchor.rect.x: (anchor.window?.width ?? 0) - 8
        anchor.rect.y: anchor.window?.height ?? 0
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.margins.top: 8
        // The compositor hides a grabbing popup on any outside click.
        grabFocus: true
        onVisibleChanged: {
            if (!visible)
                root.closedAt = Date.now();
        }
        color: "transparent"
        implicitWidth: 400
        implicitHeight: Math.min(header.height + Math.max(list.contentHeight, 60) + 32, 600)

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.94)
            border.color: Theme.accent
            border.width: 2
            radius: 12

            Item {
                id: header
                x: 14
                y: 10
                width: parent.width - 28
                height: 28

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        text: Notifs.dnd ? "" : ""
                        color: Notifs.dnd ? Theme.accent : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.dnd = !Notifs.dnd
                        }
                    }

                    Text {
                        visible: root.count > 0
                        text: "Clear"
                        color: clearMouse.containsMouse ? Theme.red : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize

                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.clear()
                        }
                    }
                }
            }

            ListView {
                id: list
                anchors.top: header.bottom
                anchors.topMargin: 8
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                x: 12
                width: parent.width - 24
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
}
