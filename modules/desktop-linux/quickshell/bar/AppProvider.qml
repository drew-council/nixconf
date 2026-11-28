import QtQuick
import Quickshell
import Quickshell.Io

// Desktop applications, launched like fuzzel's default mode.
// Launch counts rank frequent apps first, as fuzzel does.
Scope {
    id: root

    readonly property string prompt: "Launch an application"
    readonly property string glyph: "\uf135"
    // Desktop file name to launch count.
    property var launches: ({})
    readonly property var items: DesktopEntries.applications.values.filter(e => !e.noDisplay).sort((a, b) => a.name.localeCompare(b.name)).map(e => ({
                label: e.name,
                detail: e.genericName || e.comment,
                search: [e.genericName, e.comment, ...e.keywords].join(" "),
                icon: e.icon,
                weight: launches[key(e)] ?? 0,
                entry: e
            }))

    function key(entry) {
        return entry.id.endsWith(".desktop") ? entry.id : `${entry.id}.desktop`;
    }

    function refresh() {
    }

    function activate(item) {
        item.entry.execute();
        const k = key(item.entry);
        launches = Object.assign({}, launches, {
            [k]: (launches[k] ?? 0) + 1
        });
        history.setText(Object.entries(launches).map(([id, n]) => `${id}|${n}\n`).join(""));
    }

    // One "name.desktop|count" line per app, the format of fuzzel's cache.
    FileView {
        id: history
        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/quickshell/app-launches`
        printErrors: false
        onLoaded: {
            const counts = {};
            for (const line of text().split("\n")) {
                const [id, n] = line.split("|");
                if (id && Number(n) > 0)
                    counts[id] = Number(n);
            }
            root.launches = counts;
        }
    }
}
