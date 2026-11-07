import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

BarButton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property int volume: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property bool headphones: {
        const props = sink?.properties ?? {};
        const keys = ["device.form-factor", "device.form_factor", "device.icon_name", "device.profile.description"];
        return keys.some(key => /head(phone|set)/i.test(props[key] ?? ""));
    }

    readonly property string sinkIcon: {
        if (sink?.audio?.muted)
            return "󰖁";
        if (headphones)
            return "";
        if (volume < 34)
            return "";
        if (volume < 67)
            return "";
        return "";
    }
    readonly property string sourceIcon: source?.audio?.muted ? "" : ""

    text: `${volume}% ${sinkIcon} ${sourceIcon}`
    tooltip: sink?.description ?? ""

    onClicked: button => {
        if (button === Qt.LeftButton)
            Quickshell.execDetached(["switchaudio"]);
        else if (button === Qt.RightButton)
            Quickshell.execDetached(["pavucontrol"]);
    }

    onScrolled: delta => {
        if (!sink?.audio)
            return;
        const step = delta > 0 ? 0.05 : -0.05;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + step));
    }

    PwObjectTracker {
        objects: [root.sink, root.source]
    }
}
