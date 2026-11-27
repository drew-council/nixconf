import Quickshell
import Quickshell.Io

// Unicode emoji; choosing one types it into the focused window.
Scope {
    id: root

    readonly property string prompt: "Search emoji"
    readonly property string glyph: "󰞅"
    property var items: []

    function refresh() {
        if (items.length === 0)
            data.reload();
    }

    function activate(item) {
        // Wait for focus to return to the previous window before typing.
        Quickshell.execDetached(["sh", "-c", "sleep 0.05; exec @wtype@ -- \"$1\"", "sh", item.emoji]);
    }

    // Lines look like: 1F600 ; fully-qualified # 😀 E1.0 grinning face
    FileView {
        id: data
        path: "@emojiTest@"
        onLoaded: {
            const items = [];
            let group = "";
            for (const line of text().split("\n")) {
                if (line.startsWith("# group: ")) {
                    group = line.slice(9);
                    continue;
                }
                const m = line.match(/; fully-qualified\s+# (\S+) E[\d.]+ (.+)$/);
                if (m)
                    items.push({
                        label: m[2],
                        glyph: m[1],
                        emoji: m[1],
                        search: group
                    });
            }
            root.items = items;
        }
    }
}
