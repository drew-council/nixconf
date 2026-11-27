import Quickshell
import Quickshell.Services.Pipewire

// PipeWire output devices; choosing one makes it the default sink.
Scope {
    readonly property string prompt: "Switch audio output"
    readonly property string glyph: "󰓃"
    readonly property var items: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio).map(n => ({
                label: n.description || n.nickname || n.name,
                detail: n.name,
                glyph: /head(phone|set)/i.test(n.description) ? "\uf025" : "󰓃",
                selected: n === Pipewire.defaultAudioSink,
                node: n
            }))

    function refresh() {
    }

    function activate(item) {
        Pipewire.preferredDefaultAudioSink = item.node;
    }
}
