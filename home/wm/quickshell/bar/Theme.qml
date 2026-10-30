pragma Singleton

import QtQuick
import Quickshell

// Catppuccin Mocha
Singleton {
    readonly property color base: "#1e1e2e"
    readonly property color mantle: "#181825"
    readonly property color surface0: "#313244"
    readonly property color overlay1: "#7f849c"
    readonly property color text: "#cdd6f4"
    readonly property color subtext0: "#a6adc8"
    readonly property color mauve: "#cba6f7"
    readonly property color blue: "#89b4fa"
    readonly property color green: "#a6e3a1"
    readonly property color red: "#f38ba8"

    readonly property color accent: mauve
    readonly property color barBackground: Qt.rgba(30 / 255, 30 / 255, 46 / 255, 0.5)

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
    readonly property int barHeight: 24
}
