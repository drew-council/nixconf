import QtQuick
import Quickshell
import Quickshell.Networking

// Connection status. Click for wired and Wi-Fi networks.
BarButton {
    id: root

    readonly property var devices: Networking.devices.values
    readonly property var wired: devices.filter(d => d.type === DeviceType.Wired)
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredUp: wired.find(d => d.connected) ?? null
    readonly property var wifiUp: wifi?.networks.values.find(n => n.connected) ?? null
    // Connected first, then saved, then by signal.
    readonly property var networks: (wifi?.networks.values ?? []).slice().sort((a, b) => b.connected - a.connected || b.known - a.known || b.signalStrength - a.signalStrength)
    // A secured network waiting for its password.
    property var pending: null

    function strengthGlyph(s) {
        return s > 0.75 ? "󰤨" : s > 0.5 ? "󰤥" : s > 0.25 ? "󰤢" : "󰤟";
    }

    function choose(network) {
        if (network.connected)
            network.disconnect();
        else if (network.known || network.security === WifiSecurityType.Open)
            network.connect();
        else
            pending = network;
    }

    visible: devices.length > 0
    text: wiredUp ? "󰈀" : wifiUp ? strengthGlyph(wifiUp.signalStrength) : wifi && !Networking.wifiEnabled ? "󰤮" : wifi ? "󰤭" : "󰈂"
    textColor: wiredUp || wifiUp ? Theme.text : Theme.overlay1
    tooltip: wiredUp ? `Wired: ${wiredUp.name}` : wifiUp ? `${wifiUp.name} (${Math.round(wifiUp.signalStrength * 100)}%)` : "Disconnected"

    onClicked: panel.toggle()

    BarPanel {
        id: panel
        owner: root
        title: "Network"
        contentHeight: Math.max(column.implicitHeight, 40)
        onVisibleChanged: {
            if (root.wifi)
                root.wifi.scannerEnabled = visible;
            if (!visible)
                root.pending = null;
        }

        actions: [
            PanelAction {
                visible: root.wifi !== null
                text: Networking.wifiEnabled ? "󰖩" : "󰖪"
                active: Networking.wifiEnabled
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            },
            PanelAction {
                text: "Settings"
                onClicked: {
                    panel.visible = false;
                    Quickshell.execDetached(["nm-connection-editor"]);
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
                    model: root.wired

                    PanelRow {
                        required property var modelData
                        width: column.width
                        glyph: "󰈀"
                        label: "Ethernet"
                        detail: modelData.name
                        active: modelData.connected
                        status: modelData.connected ? "Connected" : modelData.hasLink ? "" : "No cable"
                        onClicked: modelData.connected ? modelData.disconnect() : modelData.network?.connect()
                    }
                }

                Repeater {
                    model: Networking.wifiEnabled ? root.networks : []

                    PanelRow {
                        required property var modelData
                        width: column.width
                        glyph: root.strengthGlyph(modelData.signalStrength)
                        label: modelData.name
                        detail: modelData.security === WifiSecurityType.Open ? "" : "󰌾"
                        active: modelData.connected
                        busy: modelData.stateChanging
                        status: modelData.connected ? "Connected" : modelData.known ? "Saved" : ""
                        onClicked: root.choose(modelData)
                    }
                }

                // Password entry for a new secured network.
                Rectangle {
                    visible: root.pending !== null
                    width: column.width
                    height: 34
                    radius: 8
                    color: Theme.surface0
                    border.color: Theme.accent
                    border.width: 1

                    TextInput {
                        id: psk
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        focus: parent.visible
                        onVisibleChanged: {
                            text = "";
                            if (visible)
                                forceActiveFocus();
                        }
                        onAccepted: {
                            root.pending.connectWithPsk(text);
                            root.pending = null;
                        }
                        Keys.onEscapePressed: root.pending = null

                        Text {
                            visible: psk.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: `Password for ${root.pending?.name ?? ""}`
                            color: Theme.overlay1
                            font: psk.font
                        }
                    }
                }

                Text {
                    visible: root.wifi !== null && !Networking.wifiEnabled
                    width: column.width
                    topPadding: 8
                    horizontalAlignment: Text.AlignHCenter
                    text: "Wi-Fi is off"
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
