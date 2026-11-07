import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
    id: root

    required property QsWindow barWindow

    spacing: 10

    Repeater {
        model: SystemTray.items

        Item {
            id: item

            required property SystemTrayItem modelData

            implicitWidth: 16
            implicitHeight: Theme.barHeight

            function openMenu() {
                const pos = item.mapToItem(null, 0, item.height);
                modelData.display(root.barWindow, pos.x, pos.y);
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                color: Theme.red
                visible: item.modelData.status === Status.NeedsAttention
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: 16
                source: item.modelData.icon
                opacity: item.modelData.status === Status.Passive ? 0.6 : 1
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: event => {
                    if (event.button === Qt.MiddleButton)
                        item.modelData.secondaryActivate();
                    else if (event.button === Qt.RightButton || item.modelData.onlyMenu)
                        item.openMenu();
                    else
                        item.modelData.activate();
                }
                onWheel: event => item.modelData.scroll(event.angleDelta.y, false)
            }

            Tooltip {
                target: item
                text: item.modelData.tooltipTitle || item.modelData.title
                shown: mouse.containsMouse
            }
        }
    }
}
