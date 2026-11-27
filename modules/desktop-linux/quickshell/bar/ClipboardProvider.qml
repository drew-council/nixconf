import Quickshell
import Quickshell.Io

// cliphist history; choosing an entry copies it again.
Scope {
    id: root

    readonly property string prompt: "Search clipboard history"
    readonly property string glyph: "󰅌"
    property var items: []

    function refresh() {
        items = [];
        list.running = true;
    }

    function activate(item) {
        // cliphist decode takes the full "id<TAB>preview" line on stdin.
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "sh", item.line]);
    }

    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.items = text.split("\n").filter(line => line !== "").map(line => ({
                        label: line.slice(line.indexOf("\t") + 1),
                        line: line
                    }))
        }
    }
}
