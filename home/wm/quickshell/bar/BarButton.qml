import QtQuick

// Text button with the accent top border on hover.
Item {
    id: root

    property alias text: label.text
    property alias textFormat: label.textFormat
    property alias font: label.font
    property color textColor: Theme.text
    property color background: "transparent"
    property bool highlighted: false
    property int padding: 4
    property string tooltip: ""
    property int tooltipFormat: Text.PlainText
    readonly property bool hovered: mouse.containsMouse

    signal clicked(int button)
    signal scrolled(int delta)

    implicitWidth: label.implicitWidth + padding * 2
    implicitHeight: Theme.barHeight

    Rectangle {
        anchors.fill: parent
        color: root.background
    }

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 2
        color: Theme.accent
        visible: root.highlighted || root.hovered
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: root.textColor
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => root.clicked(event.button)
        onWheel: event => root.scrolled(event.angleDelta.y)
    }

    property bool tooltipReady: false

    onHoveredChanged: tooltipReady = false

    Timer {
        interval: 500
        running: root.hovered && !root.tooltipReady
        onTriggered: root.tooltipReady = true
    }

    Tooltip {
        target: root
        text: root.tooltip
        textFormat: root.tooltipFormat
        shown: root.hovered && root.tooltipReady
    }
}
