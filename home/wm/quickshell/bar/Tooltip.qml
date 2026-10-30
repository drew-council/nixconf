import QtQuick
import Quickshell

PopupWindow {
    id: root

    required property Item target
    property string text: ""
    property int textFormat: Text.PlainText
    property bool shown: false

    anchor.item: target
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.bottom: -4

    visible: shown && text !== ""
    color: "transparent"
    implicitWidth: label.implicitWidth + 16
    implicitHeight: label.implicitHeight + 10

    Rectangle {
        anchors.fill: parent
        color: Theme.mantle
        border.color: Theme.surface0
        border.width: 1
        radius: 6

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            textFormat: root.textFormat
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
    }
}
