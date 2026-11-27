import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

// One notification. Click runs its default action, middle click dismisses it.
Rectangle {
    id: root

    required property Notification notification
    readonly property bool hovered: hover.hovered
    readonly property bool critical: notification?.urgency === NotificationUrgency.Critical
    readonly property var actions: notification?.actions.filter(a => a.identifier !== "default") ?? []
    readonly property string iconSource: {
        let icon = notification?.image || notification?.appIcon || "";
        // Icon names arrive bare or as image://icon/<name>; resolve them so missing icons hide.
        if (icon.startsWith("image://icon/"))
            icon = icon.slice("image://icon/".length);
        if (icon === "" || icon.includes("/"))
            return icon;
        return Quickshell.iconPath(icon, true);
    }

    // Sent after a click, so toasts can hide.
    signal activated

    implicitHeight: content.implicitHeight + 24
    radius: 10
    color: Theme.mantle
    border.width: 1
    border.color: critical ? Theme.red : hovered ? Theme.accent : Theme.surface0

    // Text and buttons inside the card take hover from a MouseArea,
    // so the border and toast timer would flicker. HoverHandler is passive.
    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.MiddleButton) {
                root.notification.dismiss();
                return;
            }
            root.notification.actions.find(a => a.identifier === "default")?.invoke();
            root.activated();
        }
    }

    IconImage {
        id: icon
        x: 12
        y: 12
        implicitSize: 36
        visible: root.iconSource !== ""
        source: root.iconSource
    }

    Column {
        id: content
        x: icon.visible ? 60 : 14
        y: 12
        width: parent.width - x - 36
        spacing: 4

        Row {
            width: parent.width
            spacing: 8

            Text {
                id: summary
                width: Math.min(implicitWidth, parent.width - app.width - parent.spacing)
                elide: Text.ElideRight
                text: root.notification?.summary ?? ""
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                id: app
                anchors.baseline: summary.baseline
                text: root.notification?.appName ?? ""
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }

        Text {
            width: parent.width
            visible: text !== ""
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: root.notification?.body ?? ""
            color: Theme.subtext0
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            onLinkActivated: link => Qt.openUrlExternally(link)
        }

        Flow {
            width: parent.width
            visible: root.actions.length > 0
            topPadding: 4
            spacing: 6

            Repeater {
                model: root.actions

                Rectangle {
                    required property NotificationAction modelData
                    implicitWidth: actionLabel.implicitWidth + 16
                    implicitHeight: 24
                    radius: 6
                    color: actionMouse.containsMouse ? Theme.surface1 : Theme.surface0

                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: parent.modelData.text
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            parent.modelData.invoke();
                            root.activated();
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        visible: root.hovered
        text: ""
        color: closeMouse.containsMouse ? Theme.red : Theme.overlay1
        font.family: Theme.font
        font.pixelSize: 12

        MouseArea {
            id: closeMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.notification.dismiss()
        }
    }
}
