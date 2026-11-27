import QtQuick
import Quickshell

// A titled panel hanging from the bar's right edge, lined up with the toasts.
// Clicking outside closes it.
PopupWindow {
    id: root

    // Any item in the bar; the panel hangs from that bar's window.
    required property Item owner
    property string title
    // Height the content wants; the panel caps it.
    property real contentHeight: 60
    default property alias content: body.data
    property alias actions: actionRow.data

    property real closedAt: 0

    // Clicking the owner to close the panel also dismisses the grab,
    // and that same click must not reopen it.
    function toggle() {
        if (!visible && Date.now() - closedAt < 250)
            return;
        visible = !visible;
    }

    anchor.window: owner.QsWindow.window
    anchor.rect.x: (anchor.window?.width ?? 0) - 8
    anchor.rect.y: anchor.window?.height ?? 0
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.margins.top: 8
    // The compositor hides a grabbing popup on any outside click.
    grabFocus: true
    onVisibleChanged: {
        if (!visible)
            closedAt = Date.now();
    }
    color: "transparent"
    implicitWidth: 400
    implicitHeight: Math.min(header.height + contentHeight + 32, 600)

    Rectangle {
        anchors.fill: parent
        color: Theme.base
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
                text: root.title
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }

            Row {
                id: actionRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
            }
        }

        Item {
            id: body
            anchors.top: header.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            x: 12
            width: parent.width - 24
        }
    }
}
