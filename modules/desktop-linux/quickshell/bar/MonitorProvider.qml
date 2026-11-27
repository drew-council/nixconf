import Quickshell
import Quickshell.Io

// Monitor profiles from hypr-monitor-profile, which also applies the choice.
Scope {
    id: root

    readonly property string prompt: "Switch monitor profile"
    readonly property string glyph: "󰍹"
    property var items: []

    function refresh() {
        state.reload();
        list.running = true;
    }

    function activate(item) {
        Quickshell.execDetached(["hypr-monitor-profile", item.label]);
    }

    // monitor_profiles.lua records the applied profile here.
    FileView {
        id: state
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hyprmonitor-state.lua`
        blockLoading: true
        printErrors: false
    }

    Process {
        id: list
        command: ["hypr-monitor-profile", "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const active = state.text().match(/active_profile = "(.*)"/)?.[1];
                root.items = text.split("\n").filter(label => label !== "").map(label => ({
                            label: label,
                            glyph: "󰍹",
                            selected: label === active
                        }));
            }
        }
    }
}
