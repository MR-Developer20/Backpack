pragma Singleton
import QtQuick

// Colors and sizes for GUI Mode. Every size is multiplied by `scale` (the UI size slider in
// Settings; Main.qml binds it to settings.uiScale), so QML files take px values from here or
// through s(px) instead of hard-coding them.
QtObject {
    property real scale: 1.0
    function s(px) { return Math.round(px * scale) }

    readonly property color bg: "#0f1419"
    readonly property color panel: "#182028"
    readonly property color panelAlt: "#1f2a35"
    readonly property color border: "#2c3a48"
    readonly property color text: "#e6edf3"
    readonly property color muted: "#8b9bb0"
    readonly property color accent: "#2ec4b6"
    readonly property color danger: "#e5484d"
    readonly property color warn: "#f5a524"
    readonly property color dangerFill: "#4a2328"    // Shut down button
    readonly property color cautionFill: "#3a3f2a"   // Reboot button
    readonly property color activeFill: "#3a2a2a"    // Split while a split terminal is open
    readonly property color edexFill: "#13303a"
    readonly property color scrim: "#c0000000"       // behind overlays and dialogs
    readonly property color outputBg: "#0a0e12"
    readonly property color outputInk: "#cfe3d8"
    readonly property int fontSize: s(20)
    readonly property int smallFont: s(15)
    readonly property int titleFont: s(26)
    readonly property int tileW: s(196)
    readonly property int tileH: s(140)
    readonly property int touch: s(64)
    readonly property int icon: s(34)
    readonly property int barH: s(84)
    readonly property int gap: s(10)
    function categoryColor(c) {
        switch (c) {
        case "discovery": return "#2ec4b6"
        case "connectivity": return "#4f9df7"
        case "capture": return "#f5a524"
        case "wireless": return "#c084fc"
        case "throughput": return "#34d399"
        case "dns-http": return "#fb7185"
        case "disks": return "#38bdf8"
        case "recovery": return "#fb923c"
        case "files": return "#facc15"
        case "transfer": return "#a3e635"
        }
        return "#8b9bb0"
    }
}
