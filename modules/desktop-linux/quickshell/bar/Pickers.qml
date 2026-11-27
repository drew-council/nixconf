pragma Singleton

import QtQuick
import Quickshell

// Which picker is open, and where.
Singleton {
    id: root

    // kind names the open picker, or "" when none is open.
    property string kind: ""
    // anchor is the bar item the picker hangs from,
    // or null to center it on the focused monitor.
    property Item anchor: null

    readonly property var providers: ({
            apps: apps,
            clipboard: clipboard,
            audio: audio,
            emoji: emoji,
            monitors: monitors
        })
    readonly property var provider: providers[kind] ?? null

    function toggle(name: string, item: Item) {
        if (kind === name && anchor === item) {
            close();
            return;
        }
        if (!providers[name]) {
            console.warn(`unknown picker: ${name}`);
            return;
        }
        // Close first so a picker moving between bar and center recreates its view.
        close();
        anchor = item;
        kind = name;
        provider.refresh();
    }

    function close() {
        kind = "";
        anchor = null;
    }

    AppProvider {
        id: apps
    }

    ClipboardProvider {
        id: clipboard
    }

    AudioProvider {
        id: audio
    }

    MonitorProvider {
        id: monitors
    }

    EmojiProvider {
        id: emoji
    }
}
