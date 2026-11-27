import QtQuick

// One clickable row in a panel list: glyph, label, detail, and a trailing status.
Rectangle {
    id: root

    property string glyph
    property string label
    property string detail
    property string status
    property bool active: false
    property bool busy: false

    signal clicked

    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? Theme.surface0 : "transparent"

    Text {
        id: icon
        x: 10
        width: 22
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        color: root.active ? Theme.accent : Theme.subtext0
        font.family: Theme.font
        font.pixelSize: 16
    }

    Row {
        anchors.left: icon.right
        anchors.leftMargin: 10
        anchors.right: trailing.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Text {
            id: name
            width: Math.min(implicitWidth, parent.width)
            elide: Text.ElideRight
            text: root.label
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.bold: root.active
        }

        Text {
            width: parent.width - name.width - parent.spacing
            anchors.baseline: name.baseline
            visible: root.detail !== "" && width > 30
            elide: Text.ElideRight
            text: root.detail
            color: Theme.overlay1
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }

    Text {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.busy ? "…" : root.status
        color: root.active ? Theme.green : Theme.overlay1
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
