import QtQuick
import QtQuick.Shapes

// Top-bar glyphs as vector geometry: light outline paths on a 24-unit grid, a 2-unit stroke, drawn
// by the curve renderer with analytic anti-aliasing. No bitmaps: crisp at every UI size.
// The path coordinates are multiplied to the icon size in JS (not by a Scale transform) so the
// stroke can be a whole number of pixels and the rectilinear glyphs can land their horizontal and
// vertical edges on pixel boundaries (`snap`): a frame then reads as a solid 3px line at 1.0x
// instead of a 2.83px line with grey fringes. Diagonals and curves get plain analytic AA.
// Curves are written as cubic Béziers (C) with exact junction points, never as SVG arcs (A): the
// curve renderer misdraws an arc's joins at some window positions (verified over 64 positions).
// Names: terminal, split, exitsplit, keyboard, wifi, settings, chevron (the Dropdown's open mark).
Item {
    id: ic
    property string name: ""
    property color color: Theme.text
    property real stroke: 2           // in grid units: 2/24 of the icon
    implicitWidth: Theme.icon
    implicitHeight: Theme.icon
    readonly property var glyph: glyphs[name] || { stroke: "", fill: "", snap: false }
    readonly property var glyphs: ({
        // frame with the design's cut corners (top-right, bottom-left), then the prompt
        terminal:  { snap: true, stroke: "M2 3 H19 L22 6 V21 H5 L2 18 Z M7 8 L11 12 L7 16 M13 16 H17", fill: "" },
        // two panes
        split:     { snap: true, stroke: "M2 3 H10 V21 H2 Z M14 3 H22 V21 H14 Z", fill: "" },
        // one pane and an X
        exitsplit: { snap: true, stroke: "M2 3 H22 V21 H2 Z M8 8 L16 16 M16 8 L8 16", fill: "" },
        // window bar (WindowBar.qml): an X; a window with its title rule; two staggered windows
        close:     { snap: true, stroke: "M5 5 L19 19 M19 5 L5 19", fill: "" },
        maximize:  { snap: true, stroke: "M3 4 H21 V20 H3 Z M3 8 H21", fill: "" },
        restore:   { snap: true, stroke: "M8 7 V3 H21 V16 H17 M3 7 H17 V21 H3 Z M3 11 H17", fill: "" },
        // frame, two staggered rows of 2x2 keys and the space bar
        keyboard:  { snap: true, stroke: "M2 4 H22 V20 H2 Z",
                     fill: "M5 7 h2 v2 h-2 Z M9 7 h2 v2 h-2 Z M13 7 h2 v2 h-2 Z M17 7 h2 v2 h-2 Z "
                         + "M7 11 h2 v2 h-2 Z M11 11 h2 v2 h-2 Z M15 11 h2 v2 h-2 Z M7 15 h10 v2 h-10 Z" },
        // three 90-degree arcs (r 4, 8, 12) about (12,18), one cubic each, and the dot (r 1.5)
        wifi:      { snap: false,
                     stroke: "M9.172 15.172 C10.734 13.609 13.266 13.609 14.828 15.172 "
                           + "M6.343 12.343 C9.467 9.219 14.533 9.219 17.657 12.343 "
                           + "M3.515 9.515 C8.201 4.828 15.799 4.828 20.485 9.515",
                     fill: "M13.5 18 C13.5 18.828 12.828 19.5 12 19.5 C11.172 19.5 10.5 18.828 10.5 18 "
                         + "C10.5 17.172 11.172 16.5 12 16.5 C12.828 16.5 13.5 17.172 13.5 18 Z" },
        // a down-pointing chevron: the Dropdown's affordance
        chevron:   { snap: false, stroke: "M5 9 L12 16 L19 9", fill: "" },
        // eight-tooth gear (tips r 10.6, roots r 8, so the mitred tips stay inside the grid) and its bore (r 3.5)
        settings:  { snap: false,
                     stroke: "M10.41 4.16 L10.71 1.48 L13.29 1.48 L13.59 4.16 L16.42 5.33 L18.53 3.65 L20.35 5.47 L18.67 7.58 "
                           + "L19.84 10.41 L22.52 10.71 L22.52 13.29 L19.84 13.59 L18.67 16.42 L20.35 18.53 L18.53 20.35 L16.42 18.67 "
                           + "L13.59 19.84 L13.29 22.52 L10.71 22.52 L10.41 19.84 L7.58 18.67 L5.47 20.35 L3.65 18.53 L5.33 16.42 "
                           + "L4.16 13.59 L1.48 13.29 L1.48 10.71 L4.16 10.41 L5.33 7.58 L3.65 5.47 L5.47 3.65 L7.58 5.33 Z "
                           + "M15.5 12 C15.5 13.933 13.933 15.5 12 15.5 C10.067 15.5 8.5 13.933 8.5 12 "
                           + "C8.5 10.067 10.067 8.5 12 8.5 C13.933 8.5 15.5 10.067 15.5 12 Z",
                     fill: "" }
    })

    // grid unit in px, and the stroke in whole px (never thinner than 1)
    readonly property real k: width / 24
    readonly property real strokePx: Math.max(1, Math.round(stroke * k))

    // Scales an SVG path string by k. With `snap`, absolute coordinates of a stroked path are
    // rounded so the edges of a strokePx-wide line fall on pixel boundaries (fills round to whole
    // pixels) and relative lengths round to whole pixels, so key squares keep one size. Should an
    // arc command be used, its radii are scaled but not rounded and its rotation and flags pass
    // through untouched.
    function fit(d, snap, stroked) {
        var out = [], cmd = "", idx = 0, half = stroked ? strokePx / 2 : 0
        var re = /[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?/g
        var m
        while ((m = re.exec(d)) !== null) {
            var t = m[0]
            if (/[A-Za-z]/.test(t)) { cmd = t; idx = 0; out.push(t); continue }
            var v = parseFloat(t) * k
            var p = idx++
            if (cmd === "A" || cmd === "a") {
                if (p % 7 === 2 || p % 7 === 3 || p % 7 === 4) { out.push(t); continue }   // rotation, flags
                if (p % 7 < 2) { out.push(fmt(v)); continue }                              // radii: scaled only
                if (snap) v = cmd === "A" ? Math.round(v - half) + half : Math.round(v)
            } else if (snap) {
                v = cmd === cmd.toUpperCase() ? Math.round(v - half) + half : Math.round(v)
            }
            out.push(fmt(v))
        }
        return out.join(" ")
    }
    function fmt(v) { return String(Math.round(v * 1000) / 1000) }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ic.color; strokeWidth: ic.strokePx; fillColor: "transparent"
            capStyle: ShapePath.SquareCap; joinStyle: ShapePath.MiterJoin
            PathSvg { path: ic.fit(ic.glyph.stroke, ic.glyph.snap, true) }
        }
        ShapePath {
            strokeWidth: -1; fillColor: ic.color
            PathSvg { path: ic.fit(ic.glyph.fill, ic.glyph.snap, false) }
        }
    }
}
