import QtQuick
import Quickshell
import Quickshell.Hyprland

BarButton {
    id: root

    readonly property var actions: [
        { label: "Suspend", command: ["systemctl", "suspend"] },
        { label: "Hibernate", command: ["systemctl", "hibernate"] },
        { label: "Shutdown", command: ["poweroff"] },
        null,
        { label: "Reboot", command: ["reboot"] },
    ]

    text: "⏻"
    padding: 8
    onClicked: menu.visible = !menu.visible

    PopupWindow {
        id: menu

        anchor.item: root
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        color: "transparent"
        implicitWidth: 140
        implicitHeight: entries.implicitHeight + 8

        Rectangle {
            anchors.fill: parent
            color: Theme.mantle
            border.color: Theme.surface0
            border.width: 1
            radius: 6

            Column {
                id: entries
                anchors.fill: parent
                anchors.margins: 4

                Repeater {
                    model: root.actions

                    Loader {
                        required property var modelData
                        width: entries.width
                        sourceComponent: modelData ? entry : separator

                        Component {
                            id: entry

                            Rectangle {
                                implicitHeight: 26
                                radius: 4
                                color: hover.containsMouse ? Theme.surface0 : "transparent"

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 8
                                    text: modelData.label
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize
                                }

                                MouseArea {
                                    id: hover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        menu.visible = false;
                                        Quickshell.execDetached(modelData.command);
                                    }
                                }
                            }
                        }

                        Component {
                            id: separator

                            Item {
                                implicitHeight: 9

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 8
                                    height: 1
                                    color: Theme.surface0
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: menu.visible
        windows: [menu]
        onCleared: menu.visible = false
    }
}
