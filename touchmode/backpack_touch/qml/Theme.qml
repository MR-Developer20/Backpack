pragma Singleton
import QtQuick

// GUI Mode look: the "Backpack Field Terminal" design system. Values are its tokens.json (token
// names in the comments). Every size is multiplied by `scale` (the UI size slider), so QML files
// take px values from here or through s(px) instead of hard-coding them. `section` follows the open
// tab (Main.qml binds it): `accent` is acid in Network and Extra, cyan in Data.
QtObject {
    property real scale: 1.0
    property string section: "network"
    function s(px) { return Math.round(px * scale) }

    // palette
    readonly property color void_: "#07090a"
    readonly property color hull: "#0e1214"
    readonly property color hullRaised: "#161c1f"
    readonly property color grid: "#2a3438"
    readonly property color gridStrong: "#5a6b70"
    readonly property color ink: "#e6ede8"
    readonly property color inkMuted: "#8d9c96"
    readonly property color phosphor: "#b8f5a0"
    readonly property color acid: "#c6ff1a"
    readonly property color cyan: "#2fd8e8"
    readonly property color amber: "#ffb000"
    readonly property color signal: "#ff3d6e"

    // roles used across the QML
    readonly property color bg: void_
    readonly property color panel: hull
    readonly property color panelAlt: hullRaised
    readonly property color border: grid
    readonly property color borderStrong: gridStrong
    readonly property color text: ink
    readonly property color muted: inkMuted
    readonly property color accent: section === "data" ? cyan : acid
    readonly property color focus: acid
    readonly property color inkOnAccent: void_      // on-acid / on-cyan / on-amber / on-signal
    readonly property color info: cyan
    readonly property color warn: amber
    readonly property color danger: signal
    readonly property color dangerFill: signal
    readonly property color inkOnDanger: void_
    readonly property color scrim: "#c0000000"
    readonly property color outputBg: void_
    readonly property color outputInk: phosphor

    // type: one family; hierarchy from weight, case and tracking
    readonly property string fontSans: "JetBrains Mono"
    readonly property string fontDisplay: "JetBrains Mono"
    readonly property string fontMono: "JetBrains Mono"
    readonly property int wordmarkFont: s(28)
    readonly property int titleFont: s(26)
    readonly property int tileNameFont: s(22)
    readonly property int fontSize: s(19)       // body
    readonly property int smallFont: s(15)
    readonly property int labelFont: s(13)      // uppercase, tracked 0.14em
    readonly property int microFont: s(11)      // uppercase, tracked 0.16em

    // space, shape, size
    readonly property int space1: s(4)
    readonly property int space2: s(8)
    readonly property int space3: s(12)
    readonly property int space4: s(16)
    readonly property int space6: s(24)
    readonly property int cutSm: s(6)           // buttons, chips, inputs
    readonly property int cutMd: s(12)          // tiles, output pane
    readonly property int cutLg: s(20)          // panels, sheets
    readonly property int touch: s(64)
    readonly property int chipH: s(48)
    readonly property int tileW: s(196)
    readonly property int tileH: s(140)
    readonly property int barH: s(84)
    readonly property int rail: s(6)
    readonly property int icon: s(34)
    readonly property int gap: space2

    function categoryColor(c) {
        switch (c) {
        case "discovery": return acid
        case "connectivity": return "#6cc4ff"
        case "capture": return amber
        case "wireless": return "#b496ff"
        case "throughput": return "#8ff0c8"
        case "dns-http": return "#ff6fb0"
        case "disks": return cyan
        case "recovery": return "#ff8c42"
        case "files": return "#f2e15c"
        case "transfer": return "#b496ff"
        case "extra": return "#ff9a7a"
        }
        return inkMuted
    }
}
