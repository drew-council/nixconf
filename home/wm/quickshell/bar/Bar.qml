import QtQuick
import Quickshell
import Quickshell.Hyprland

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.barBackground

    Row {
        id: left
        anchors.left: parent.left
        height: parent.height
        spacing: 4

        BarButton {
            text: ""
            textColor: Theme.blue
            font.pixelSize: 16
            padding: 8
            tooltip: "Open application launcher"
            onClicked: Quickshell.execDetached(["fuzzel"])
        }

        Workspaces {}
    }

    Text {
        // Quickshell only learns the active window from focus events, so fall
        // back to the client list until the first one arrives.
        readonly property var window: Hyprland.activeToplevel
            ?? Hyprland.toplevels.values.find(t => t.lastIpcObject?.focusHistoryID === 0)
            ?? null
        readonly property real maxWidth: bar.width - 2 * Math.max(left.width, right.width) - 16

        anchors.centerIn: parent
        width: Math.min(implicitWidth, maxWidth)
        elide: Text.ElideRight
        text: window && window.workspace === Hyprland.focusedWorkspace ? window.title : ""
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 14
        font.bold: true
    }

    Row {
        id: right
        anchors.right: parent.right
        height: parent.height
        spacing: 4

        BarButton {
            text: "󰍹"
            tooltip: "Switch monitor profile"
            onClicked: Quickshell.execDetached(["hypr-monitor-profile"])
        }

        Audio {}

        Battery {}

        Tailscale {}

        Tray {
            anchors.verticalCenter: parent.verticalCenter
            barWindow: bar
        }

        Notifications {}

        Clock {}

        PowerMenu {}
    }
}
