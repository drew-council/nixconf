import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland

// Brief volume or brightness level, shown when either changes.
PanelWindow {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    property string glyph: ""
    property real level: 0
    property bool muted: false
    // Startup and the first PipeWire sync also report changes; ignore them.
    property bool ready: false

    function show(glyph, level, muted) {
        if (!ready)
            return;
        root.glyph = glyph;
        root.level = level;
        root.muted = muted;
        visible = true;
        hide.restart();
    }

    function showVolume() {
        const audio = sink?.audio;
        if (!audio)
            return;
        const glyph = audio.muted ? "󰝟" : audio.volume < 0.34 ? "󰕿" : audio.volume < 0.67 ? "󰖀" : "󰕾";
        show(glyph, audio.volume, audio.muted);
    }

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    visible: false
    anchors.bottom: true
    margins.bottom: 96
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    // Let clicks pass through.
    mask: Region {}
    color: "transparent"
    implicitWidth: 280
    implicitHeight: 48

    Timer {
        running: true
        interval: 1000
        onTriggered: root.ready = true
    }

    Timer {
        id: hide
        interval: 1200
        onTriggered: root.visible = false
    }

    PwObjectTracker {
        objects: [root.sink]
    }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() {
            root.showVolume();
        }
        function onMutedChanged() {
            root.showVolume();
        }
    }

    // The first backlight, if this machine has one.
    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name !== "") {
                    maxBrightness.path = `/sys/class/backlight/${name}/max_brightness`;
                    brightness.path = `/sys/class/backlight/${name}/brightness`;
                }
            }
        }
    }

    FileView {
        id: maxBrightness
        blockLoading: true
    }

    FileView {
        id: brightness
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const max = parseInt(maxBrightness.text());
            if (max > 0)
                root.show("󰃠", parseInt(text()) / max, false);
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.94)
        border.color: Theme.accent
        border.width: 2
        radius: height / 2

        Text {
            id: icon
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            text: root.glyph
            color: root.muted ? Theme.overlay1 : Theme.accent
            font.family: Theme.font
            font.pixelSize: 18
        }

        Rectangle {
            id: track
            anchors.left: icon.right
            anchors.leftMargin: 10
            anchors.right: percent.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Theme.surface0

            Rectangle {
                width: parent.width * Math.min(root.level, 1)
                height: parent.height
                radius: parent.radius
                color: root.muted ? Theme.overlay1 : root.level > 1 ? Theme.red : Theme.accent
            }
        }

        Text {
            id: percent
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(root.level * 100)}%`
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
    }
}
