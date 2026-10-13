pragma Singleton
import QtQuick

// Colors, fonts and sizes for GUI Mode. Two looks: Field Terminal (the design system, default)
// and the previous look, switched by `fieldTerminal` (Settings > Display; Main.qml binds it to
// settings.fieldTerminal). Every size is multiplied by `scale` (the UI size slider), so QML files
// take px values from here or through s(px) instead of hard-coding them.
QtObject {
    property real scale: 1.0
    property bool fieldTerminal: true
    readonly property bool ft: fieldTerminal
    function s(px) { return Math.round(px * scale) }

    // Field Terminal (Night) values come from the design system's tokens.json; the second value
    // is the previous look.
    readonly property color bg: ft ? "#161616" : "#0f1419"            // void
    readonly property color panel: ft ? "#1d1d1d" : "#182028"         // surface
    readonly property color panelAlt: ft ? "#262626" : "#1f2a35"      // surface-raised
    readonly property color border: ft ? "#333333" : "#2c3a48"        // line
    readonly property color borderStrong: ft ? "#757575" : "#2c3a48"  // line-strong (controls)
    readonly property color text: ft ? "#ececec" : "#e6edf3"          // ink
    readonly property color muted: ft ? "#bbbbbb" : "#8b9bb0"         // ink-muted
    readonly property color accent: ft ? "#99ff45" : "#2ec4b6"        // signal
    readonly property color inkOnAccent: ft ? "#161616" : "#0f1419"      // text on an accent fill
    readonly property color accentDim: ft ? "#24331a" : "#1b3a3a"     // signal-dim: selected fill
    readonly property color info: ft ? "#82e1ff" : "#4f9df7"
    readonly property color danger: ft ? "#ff4320" : "#e5484d"
    readonly property color warn: ft ? "#fff262" : "#f5a524"
    readonly property color dangerFill: ft ? "#ff4320" : "#4a2328"    // Shut down button
    readonly property color inkOnDanger: ft ? "#161616" : "#e6edf3"
    readonly property color cautionFill: ft ? "#262626" : "#3a3f2a"   // Reboot button
    readonly property color activeFill: ft ? "#24331a" : "#3a2a2a"    // Split while a split terminal is open
    readonly property color scrim: ft ? "#c7030404" : "#c0000000"     // behind overlays and dialogs
    readonly property color outputBg: ft ? "#0c0c0c" : "#0a0e12"      // surface-sunk
    readonly property color outputInk: ft ? "#c9f5b0" : "#cfe3d8"

    // fonts: Field Terminal uses one text family for every label; mono only for terminal content
    readonly property string fontSans: ft ? "IBM Plex Sans Condensed" : "DejaVu Sans"
    readonly property string fontDisplay: ft ? "Chakra Petch" : "DejaVu Sans"   // wordmark, titles
    readonly property string fontMono: ft ? "IBM Plex Mono" : "DejaVu Sans Mono"
    readonly property bool upperLabels: ft          // tabs, wordmark and group labels in caps

    readonly property int fontSize: s(20)
    readonly property int smallFont: s(15)
    readonly property int titleFont: s(26)
    readonly property int tileW: s(196)
    readonly property int tileH: s(140)
    readonly property int touch: s(64)
    readonly property int icon: s(ft ? 28 : 34)
    readonly property int barH: s(84)
    readonly property int gap: s(ft ? 8 : 10)
    readonly property int radius: s(10)                 // buttons, chips, fields ("main")
    readonly property int radiusLarge: s(ft ? 10 : 14)  // tiles
    readonly property int radiusPanel: s(ft ? 10 : 16)  // sheets and dialogs
    readonly property int radiusTab: ft ? 0 : s(10)     // section tabs are part of the screen

    function categoryColor(c) {
        if (ft) {
            switch (c) {
            case "discovery": return "#3ee6c4"
            case "connectivity": return "#7fa8ff"
            case "capture": return "#ffb000"
            case "wireless": return "#c79bff"
            case "throughput": return "#74e8a2"
            case "dns-http": return "#ff86a8"
            case "extra": return "#ff9a7a"     // cat-extra
            }
            return "#e8d27a"                   // cat-data: every Data-tab category
        }
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
        case "extra": return "#c084fc"
        }
        return "#8b9bb0"
    }
}
