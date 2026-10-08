pragma Singleton
import QtQuick

QtObject {
    readonly property color bg: "#0f1419"
    readonly property color panel: "#182028"
    readonly property color panelAlt: "#1f2a35"
    readonly property color border: "#2c3a48"
    readonly property color text: "#e6edf3"
    readonly property color muted: "#8b9bb0"
    readonly property color accent: "#2ec4b6"
    readonly property color danger: "#e5484d"
    readonly property color warn: "#f5a524"
    readonly property int fontSize: 20
    readonly property int smallFont: 15
    readonly property int tileW: 196
    readonly property int tileH: 140
    readonly property int touch: 64
    function categoryColor(c) {
        switch (c) {
        case "discovery": return "#2ec4b6"
        case "connectivity": return "#4f9df7"
        case "capture": return "#f5a524"
        case "wireless": return "#c084fc"
        case "throughput": return "#34d399"
        case "dns-http": return "#fb7185"
        }
        return "#8b9bb0"
    }
}
