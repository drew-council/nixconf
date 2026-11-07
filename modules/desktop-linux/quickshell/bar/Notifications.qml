import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors `swaync-client -swb`, which prints a JSON status line on each change.
BarButton {
    id: root

    property string state: "none"
    property string summary: ""

    readonly property bool dnd: state.startsWith("dnd")
    readonly property bool pending: state.endsWith("notification")

    text: (dnd ? "" : "") + (pending ? `<font color="${Theme.red}"><sup></sup></font>` : "")
    textFormat: Text.StyledText
    tooltip: summary

    onClicked: button => {
        if (button === Qt.LeftButton)
            Quickshell.execDetached(["swaync-client", "-t", "-sw"]);
        else if (button === Qt.RightButton)
            Quickshell.execDetached(["swaync-client", "-d", "-sw"]);
    }

    Process {
        id: proc
        running: true
        command: ["swaync-client", "-swb"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const status = JSON.parse(line);
                    root.state = status.alt ?? "none";
                    root.summary = status.tooltip ?? "";
                } catch (e) {}
            }
        }
        // swaync may start after the bar.
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 2000
        onTriggered: proc.running = true
    }
}
