import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth status, hidden without an adapter. Click for devices.
BarButton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter?.enabled ?? false
    readonly property var connected: devices.filter(d => d.connected)
    // Connected, then paired, then the rest; unnamed unpaired devices are noise.
    readonly property var devices: (adapter?.devices.values ?? []).filter(d => d.paired || d.name !== d.address).slice().sort((a, b) => b.connected - a.connected || b.paired - a.paired || a.name.localeCompare(b.name))

    function deviceGlyph(icon) {
        if (/head|audio/.test(icon))
            return "󰋋";
        if (/mouse/.test(icon))
            return "󰍽";
        if (/keyboard/.test(icon))
            return "󰌌";
        if (/phone/.test(icon))
            return "󰏲";
        if (/game|joystick/.test(icon))
            return "󰊴";
        return "󰂯";
    }

    function batteryText(device) {
        if (!device.batteryAvailable)
            return "";
        const b = device.battery;
        return `${Math.round(b > 1 ? b : b * 100)}%`;
    }

    visible: adapter !== null
    text: !powered ? "󰂲" : connected.length > 0 ? "󰂱" : "󰂯"
    textColor: powered ? Theme.text : Theme.overlay1
    tooltip: !powered ? "Bluetooth off" : connected.map(d => d.name).join("\n")

    onClicked: panel.toggle()

    BarPanel {
        id: panel
        owner: root
        title: "Bluetooth"
        contentHeight: Math.max(column.implicitHeight, 40)
        onVisibleChanged: {
            if (!visible && root.adapter?.discovering)
                root.adapter.discovering = false;
        }

        actions: [
            PanelAction {
                visible: root.powered
                text: root.adapter?.discovering ? "Scanning…" : "Scan"
                active: root.adapter?.discovering ?? false
                onClicked: root.adapter.discovering = !root.adapter.discovering
            },
            PanelAction {
                text: root.powered ? "󰂯" : "󰂲"
                active: root.powered
                onClicked: root.adapter.enabled = !root.powered
            },
            PanelAction {
                text: "Settings"
                onClicked: {
                    panel.visible = false;
                    Quickshell.execDetached(["blueman-manager"]);
                }
            }
        ]

        Flickable {
            anchors.fill: parent
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: column
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.powered ? root.devices : []

                    PanelRow {
                        required property var modelData
                        width: column.width
                        glyph: root.deviceGlyph(modelData.icon)
                        label: modelData.name
                        detail: root.batteryText(modelData)
                        active: modelData.connected
                        busy: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                        status: modelData.connected ? "Connected" : modelData.paired ? "Paired" : ""
                        onClicked: {
                            if (modelData.connected)
                                modelData.disconnect();
                            else if (modelData.paired)
                                modelData.connect();
                            else
                                modelData.pair();
                        }
                    }
                }

                Text {
                    visible: !root.powered || root.devices.length === 0
                    width: column.width
                    topPadding: 8
                    horizontalAlignment: Text.AlignHCenter
                    text: !root.powered ? "Bluetooth is off" : "No devices"
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
