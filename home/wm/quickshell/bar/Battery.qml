import QtQuick
import Quickshell.Services.UPower

BarButton {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property int percent: Math.round(device.percentage * 100)
    readonly property bool charging: device.state === UPowerDeviceState.Charging
    readonly property bool plugged: !UPower.onBattery
    readonly property bool warning: !plugged && percent <= 30
    readonly property bool critical: !plugged && percent <= 15
    property bool showTime: false
    property color blinkColor: Theme.red

    function formatDuration(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        return `${hours}h ${minutes}m`;
    }

    readonly property string remaining: {
        const seconds = charging ? device.timeToFull : device.timeToEmpty;
        return seconds > 0 ? formatDuration(seconds) : "";
    }

    readonly property string icon: {
        if (charging)
            return "";
        if (plugged)
            return "";
        return ["", "", "", "", ""][Math.min(4, Math.floor(percent / 20))];
    }

    visible: device.isLaptopBattery
    text: showTime && remaining !== "" ? `${remaining} ${icon}` : `${percent}% ${icon}`
    textColor: plugged ? Theme.green : Theme.text
    background: critical ? blinkColor : warning ? Theme.red : "transparent"
    tooltip: remaining === "" ? "" : `${remaining} until ${charging ? "full" : "empty"}`

    onClicked: showTime = !showTime

    SequentialAnimation {
        running: root.critical
        loops: Animation.Infinite

        ColorAnimation {
            target: root
            property: "blinkColor"
            to: "#ffffff"
            duration: 500
        }
        ColorAnimation {
            target: root
            property: "blinkColor"
            to: Theme.red
            duration: 500
        }
    }
}
