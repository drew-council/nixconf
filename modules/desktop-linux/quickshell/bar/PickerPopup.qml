import QtQuick
import Quickshell

// The picker named kind, hanging below a bar item.
PopupWindow {
    id: root

    required property Item anchorItem
    required property string kind
    readonly property bool open: Pickers.kind === kind && Pickers.anchor === anchorItem

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4
    grabFocus: true
    color: "transparent"
    implicitWidth: loader.item?.implicitWidth ?? 1
    implicitHeight: loader.item?.implicitHeight ?? 1

    // The compositor hides the popup on outside clicks,
    // so drive visible imperatively and report dismissal back.
    onOpenChanged: visible = open
    onVisibleChanged: {
        if (!visible && open)
            Pickers.close();
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: root.visible

        sourceComponent: PickerView {
            implicitWidth: 460
            provider: Pickers.provider
            onCloseRequested: Pickers.close()
        }
    }
}
