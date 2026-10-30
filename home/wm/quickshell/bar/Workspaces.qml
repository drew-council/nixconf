import QtQuick
import Quickshell.Hyprland

Row {
    id: root

    readonly property var workspaces: Hyprland.workspaces.values
        .filter(ws => ws.id > 0)
        .sort((a, b) => a.id - b.id)

    function activate(ws) {
        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.focus({ workspace = "${ws.id}", on_current_monitor = true })`);
        else
            Hyprland.dispatch(`focusworkspaceoncurrentmonitor ${ws.id}`);
    }

    Repeater {
        model: root.workspaces

        BarButton {
            required property var modelData
            readonly property bool focused: Hyprland.focusedWorkspace === modelData

            text: modelData.name
            padding: 8
            highlighted: focused
            textColor: focused ? Theme.accent : Theme.text
            background: modelData.urgent ? Theme.red : "transparent"
            onClicked: root.activate(modelData)
        }
    }
}
