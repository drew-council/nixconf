import Quickshell

// Desktop applications, launched like fuzzel's default mode.
Scope {
    readonly property string prompt: "Launch an application"
    readonly property string glyph: "\uf135"
    readonly property var items: DesktopEntries.applications.values.filter(e => !e.noDisplay).sort((a, b) => a.name.localeCompare(b.name)).map(e => ({
                label: e.name,
                detail: e.genericName || e.comment,
                search: [e.genericName, e.comment, ...e.keywords].join(" "),
                icon: e.icon,
                entry: e
            }))

    function refresh() {
    }

    function activate(item) {
        item.entry.execute();
    }
}
