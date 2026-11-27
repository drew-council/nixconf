import QtQuick
import Quickshell
import Quickshell.Widgets
import "Fuzzy.js" as Fuzzy

// Fuzzy-searchable list for a picker provider.
// A provider has prompt, glyph, items, and activate(item).
// Each item has label and optionally detail, search, icon, glyph, and selected.
Rectangle {
    id: root

    required property var provider
    readonly property int rowHeight: 34
    readonly property int maxRows: 10

    property string query: ""
    property int current: 0
    readonly property var results: Fuzzy.filter(provider?.items ?? [], query)

    signal closeRequested

    // Start on the selected item, such as the active sink, until the user types.
    // ListView resets its index when the model changes, so set it after that.
    onResultsChanged: Qt.callLater(() => {
        current = query === "" ? Math.max(0, results.findIndex(r => r.item.selected)) : 0;
        list.currentIndex = current;
    })
    onCurrentChanged: list.currentIndex = current

    function accept() {
        const result = results[current];
        if (!result)
            return;
        closeRequested();
        provider.activate(result.item);
    }

    function move(delta) {
        if (results.length > 0)
            current = (current + delta + results.length) % results.length;
    }

    implicitWidth: 560
    // Size by the unfiltered list so the box does not jump while typing.
    implicitHeight: header.height + list.height + 29
    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.94)
    border.color: Theme.accent
    border.width: 2
    radius: 12

    Component.onCompleted: input.forceActiveFocus()

    Item {
        id: header
        x: 14
        y: 12
        width: parent.width - 28
        height: 30

        Text {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            text: root.provider?.glyph ?? ""
            color: Theme.accent
            font.family: Theme.font
            font.pixelSize: 16
        }

        TextInput {
            id: input
            anchors.left: glyph.right
            anchors.leftMargin: 10
            anchors.right: count.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            selectionColor: Theme.surface1
            font.family: Theme.font
            font.pixelSize: 15
            clip: true
            onTextChanged: root.query = text

            Text {
                visible: input.text === ""
                text: root.provider?.prompt ?? ""
                color: Theme.overlay1
                font: input.font
            }

            Keys.onPressed: event => {
                const ctrl = event.modifiers & Qt.ControlModifier;
                if (event.key === Qt.Key_Escape)
                    root.closeRequested();
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    root.accept();
                else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))
                    root.move(1);
                else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))
                    root.move(-1);
                else
                    return;
                event.accepted = true;
            }
        }

        Text {
            id: count
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: `${root.results.length}/${root.provider?.items.length ?? 0}`
            color: Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 12
        }
    }

    Rectangle {
        id: rule
        anchors.top: header.bottom
        anchors.topMargin: 8
        x: 2
        width: parent.width - 4
        height: 1
        color: Theme.surface0
    }

    ListView {
        id: list
        anchors.top: rule.bottom
        anchors.topMargin: 6
        x: 8
        width: parent.width - 16
        height: Math.max(1, Math.min(root.provider?.items.length ?? 0, root.maxRows)) * root.rowHeight
        clip: true
        model: root.results
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        highlight: Rectangle {
            width: list.width
            color: Theme.surface0
            radius: 8

            Rectangle {
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: parent.height - 14
                radius: 2
                color: Theme.accent
            }
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var item: modelData.item

            width: list.width
            height: root.rowHeight

            // Items with an icon field fall back to a generic glyph
            // when the icon theme lacks it, so labels stay aligned.
            readonly property string iconSource: row.item.icon ? Quickshell.iconPath(row.item.icon, true) : ""
            readonly property string glyph: row.item.glyph ?? (row.item.icon !== undefined ? "\uf2d0" : "")

            IconImage {
                id: icon
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 22
                visible: row.iconSource !== ""
                source: row.iconSource
            }

            Text {
                id: rowGlyph
                x: 12
                width: 22
                anchors.verticalCenter: parent.verticalCenter
                visible: !icon.visible && row.glyph !== ""
                horizontalAlignment: Text.AlignHCenter
                text: row.glyph
                color: row.index === root.current ? Theme.accent : Theme.subtext0
                font.family: Theme.font
                font.pixelSize: 16
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: icon.visible || rowGlyph.visible ? 46 : 14
                anchors.right: check.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    id: label
                    width: Math.min(implicitWidth, parent.width)
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: Fuzzy.highlight(row.item.label, row.modelData.positions, Theme.accent, Theme.subtext0)
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                }

                Text {
                    width: parent.width - label.width - parent.spacing
                    anchors.baseline: label.baseline
                    visible: !!row.item.detail && width > 40
                    elide: Text.ElideRight
                    text: row.item.detail ?? ""
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
            }

            Text {
                id: check
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: row.item.selected ? "\uf00c" : ""
                color: Theme.green
                font.family: Theme.font
                font.pixelSize: 14
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: root.current = row.index
                onClicked: root.accept()
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.results.length === 0
            text: (root.provider?.items.length ?? 0) === 0 ? "Loading…" : "No matches"
            color: Theme.overlay1
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
    }
}
