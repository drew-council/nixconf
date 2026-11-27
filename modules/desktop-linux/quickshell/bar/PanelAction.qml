import QtQuick

// Clickable text in a panel header.
Text {
    id: root

    property bool active: false
    property color hoverColor: Theme.accent

    signal clicked

    color: mouse.containsMouse ? hoverColor : active ? Theme.accent : Theme.overlay1
    font.family: Theme.font
    font.pixelSize: Theme.fontSize

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
