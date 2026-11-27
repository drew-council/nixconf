import QtQuick
import Quickshell
import Quickshell.Io

// voxtype dictation state, shown only while recording or transcribing.
// Click stops recording, right click cancels it.
BarButton {
    id: root

    // Empty on hosts without voxtype.
    readonly property string voxtype: "@voxtype@"
    property string status: "idle"
    readonly property bool recording: status === "recording"

    visible: recording || status === "transcribing"
    text: recording ? "󰍬" : "󰔟"
    textColor: recording ? Theme.red : Theme.yellow
    tooltip: recording ? "Dictating: click to stop, right click to cancel" : "Transcribing"

    onClicked: button => {
        if (recording)
            Quickshell.execDetached([voxtype, "record", button === Qt.RightButton ? "cancel" : "toggle"]);
    }

    Process {
        id: proc
        running: root.voxtype !== ""
        command: [root.voxtype, "status", "--follow", "--format", "json"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.status = JSON.parse(line).alt ?? "idle";
                } catch (e) {}
            }
        }
        // The daemon may start after the bar, or restart.
        onExited: {
            root.status = "idle";
            restart.start();
        }
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: proc.running = true
    }
}
