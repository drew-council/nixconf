import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The open picker, centered on the focused monitor like fuzzel.
PanelWindow {
    id: root

    required property var provider

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-picker"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    implicitWidth: view.implicitWidth
    implicitHeight: view.implicitHeight

    PickerView {
        id: view
        anchors.fill: parent
        provider: root.provider
        onCloseRequested: Pickers.close()
    }

    HyprlandFocusGrab {
        active: true
        windows: [root]
        onCleared: Pickers.close()
    }
}
