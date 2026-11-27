import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import Quickshell.Wayland

// The session's polkit agent: a modal password prompt on the focused monitor.
Scope {
    id: root

    PolkitAgent {
        id: agent
    }

    LazyLoader {
        active: agent.isActive && agent.flow !== null && !agent.flow.isCompleted

        PanelWindow {
            id: dialog

            readonly property var flow: agent.flow
            // Waiting on polkit between submitting a response and its verdict.
            property bool submitting: false

            function submit() {
                if (submitting || !flow.isResponseRequired)
                    return;
                submitting = true;
                flow.submit(input.text);
                input.text = "";
            }

            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-polkit"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: Qt.rgba(0, 0, 0, 0.45)

            Connections {
                target: dialog.flow
                ignoreUnknownSignals: true
                function onIsResponseRequiredChanged() {
                    dialog.submitting = false;
                }
                function onAuthenticationFailed() {
                    dialog.submitting = false;
                    input.forceActiveFocus();
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 440
                height: content.implicitHeight + 40
                color: Theme.base
                border.color: Theme.accent
                border.width: 2
                radius: 12

                Column {
                    id: content
                    x: 20
                    y: 20
                    width: parent.width - 40
                    spacing: 12

                    Row {
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰌾"
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: 20
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Authentication required"
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 2
                            font.bold: true
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: dialog.flow?.message ?? ""
                        color: Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }

                    Rectangle {
                        visible: dialog.flow?.isResponseRequired ?? false
                        width: parent.width
                        height: 36
                        radius: 8
                        color: Theme.surface0
                        border.width: 1
                        border.color: dialog.flow?.failed ? Theme.red : input.activeFocus ? Theme.accent : Theme.surface1

                        TextInput {
                            id: input
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: dialog.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                            enabled: !dialog.submitting
                            focus: true
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 1
                            Component.onCompleted: forceActiveFocus()
                            onAccepted: dialog.submit()
                            Keys.onEscapePressed: dialog.flow.cancelAuthenticationRequest()

                            Text {
                                visible: input.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: dialog.submitting ? "Checking…" : (dialog.flow?.inputPrompt || "Password").replace(/:\s*$/, "")
                                color: Theme.overlay1
                                font: input.font
                            }
                        }
                    }

                    Text {
                        readonly property string supplementary: dialog.flow?.supplementaryMessage ?? ""
                        visible: text !== ""
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: supplementary !== "" ? supplementary : dialog.flow?.failed ? "Authentication failed, try again." : ""
                        color: dialog.flow?.supplementaryIsError || (supplementary === "" && dialog.flow?.failed) ? Theme.red : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8

                        Repeater {
                            model: [
                                {
                                    label: "Cancel",
                                    primary: false
                                },
                                {
                                    label: "Authenticate",
                                    primary: true
                                }
                            ]

                            Rectangle {
                                required property var modelData
                                implicitWidth: label.implicitWidth + 24
                                implicitHeight: 30
                                radius: 8
                                color: modelData.primary ? (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent) : (mouse.containsMouse ? Theme.surface1 : Theme.surface0)
                                opacity: modelData.primary && dialog.submitting ? 0.5 : 1

                                Text {
                                    id: label
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    color: parent.modelData.primary ? Theme.base : Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize
                                    font.bold: parent.modelData.primary
                                }

                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.modelData.primary ? dialog.submit() : dialog.flow.cancelAuthenticationRequest()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
