import QtQuick
import Quickshell.Io

BarButton {
    id: root

    property string status: ""

    visible: status !== ""
    text: "󰖂"
    textColor: Theme.green
    tooltip: status

    Process {
        id: proc
        command: ["@tailscaleStatus@"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.status = text.trim() === "" ? "" : JSON.parse(text).tooltip;
                } catch (e) {
                    root.status = "";
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }
}
