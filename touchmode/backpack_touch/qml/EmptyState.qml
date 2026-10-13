import QtQuick
import QtQuick.Shapes

// Empty tool pane: a 24px scan grid in `grid` and the dragon-curve fractal (the "iteration" pages
// of Jurassic Park, the novel) in `gridStrong`, under the hint text. Everything is geometry: no
// bitmap, layer, gradient or shadow. The grid is 1px Rectangles on whole pixels (plain quads, no
// anti-aliasing, so each line is exactly one pixel row or column on every render backend); the
// dragon is a Shape drawn by the curve renderer (analytic anti-aliasing) as the smoothed curve: one
// quadratic per corner, from the midpoint of a segment through the corner to the midpoint of the
// next, stroked ~1.5px with round joins, so iteration 11's 2048 right angles read as one continuous
// line instead of a pixel pattern. The dragon path is rebuilt once per size or UI-scale change
// (coalesced through Qt.callLater), never per frame; the grid follows its bindings.
Item {
    id: empty
    property int iteration: 11

    // generated geometry; plain properties set by rebuild(), so no binding depends on itself
    property string dragonPath: ""
    property real snapX: 0
    property real snapY: 0
    readonly property int gridStep: Theme.s(24)

    function schedule() { Qt.callLater(rebuild) }
    onWidthChanged: schedule()
    onHeightChanged: schedule()
    onIterationChanged: schedule()
    Component.onCompleted: schedule()
    Connections { target: Theme; function onScaleChanged() { empty.schedule() } }

    function rebuild() {
        var w = Math.round(width), h = Math.round(height)
        if (w <= 0 || h <= 0) { dragonPath = ""; return }

        // Sit the geometry on whole window pixels (the pane's margins can be fractional at some
        // UI sizes) so a 1px line covers exactly one pixel column or row.
        var o = empty.mapToItem(null, 0, 0)
        snapX = Math.round(o.x) - o.x
        snapY = Math.round(o.y) - o.y

        // dragon curve: turn sequence by the paper-folding rule, as unit right-angle segments
        var n = Math.pow(2, iteration), dx = 1, dy = 0, px = 0, py = 0
        var pts = [[0, 0]], minX = 0, maxX = 0, minY = 0, maxY = 0
        for (var i = 1; i <= n; i++) {
            px += dx; py += dy; pts.push([px, py])
            minX = Math.min(minX, px); maxX = Math.max(maxX, px); minY = Math.min(minY, py); maxY = Math.max(maxY, py)
            var k = i; while ((k & 1) === 0) k >>= 1
            var right = ((k >> 1) & 1) === 1, t = dx
            if (right) { dx = dy; dy = -t } else { dx = -dy; dy = t }
        }

        // fit it into the pane above the hint text, centred, with a margin all round
        var m = Theme.space6, textH = Theme.fontSize + Theme.space1 + Theme.microFont + Theme.space6
        var bw = maxX - minX, bh = maxY - minY
        var avW = w - 2 * m, avH = h - textH - 2 * m
        var sc = Math.min(avW / bw, avH / bh) * 0.9
        var ox = (w - bw * sc) / 2 - minX * sc
        var oy = m + (avH - bh * sc) / 2 - minY * sc
        function X(p) { return (ox + p[0] * sc).toFixed(2) }
        function Y(p) { return (oy + p[1] * sc).toFixed(2) }
        function MX(a, b) { return (ox + (a[0] + b[0]) * 0.5 * sc).toFixed(2) }
        function MY(a, b) { return (oy + (a[1] + b[1]) * 0.5 * sc).toFixed(2) }

        // smoothed dragon: start at the first point, run to the first midpoint, then one quadratic
        // per corner (control = the corner, end = the midpoint of the segment after it), and the
        // last half segment; tangents match at every midpoint, so the stroke is one smooth line
        var d = ["M" + X(pts[0]) + " " + Y(pts[0]), "L" + MX(pts[0], pts[1]) + " " + MY(pts[0], pts[1])]
        for (var j = 1; j < n; j++)
            d.push("Q" + X(pts[j]) + " " + Y(pts[j]) + " " + MX(pts[j], pts[j + 1]) + " " + MY(pts[j], pts[j + 1]))
        d.push("L" + X(pts[n]) + " " + Y(pts[n]))
        dragonPath = d.join(" ")
    }

    // scan grid: 1px hairlines every gridStep, starting one step in, exactly like a ruled sheet
    Item {
        id: grid
        x: empty.snapX; y: empty.snapY
        width: Math.round(empty.width); height: Math.round(empty.height)
        Repeater {
            model: Math.max(0, Math.ceil(grid.width / empty.gridStep) - 1)
            Rectangle { required property int index; x: (index + 1) * empty.gridStep; width: 1; height: grid.height; color: Theme.border }
        }
        Repeater {
            model: Math.max(0, Math.ceil(grid.height / empty.gridStep) - 1)
            Rectangle { required property int index; y: (index + 1) * empty.gridStep; height: 1; width: grid.width; color: Theme.border }
        }
    }

    Shape {
        id: shape
        x: empty.snapX; y: empty.snapY
        width: Math.round(empty.width); height: Math.round(empty.height)
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.borderStrong
            strokeWidth: Math.max(1, 1.5 * Theme.scale)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: empty.dragonPath }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.space6
        spacing: Theme.space1
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Tap a tool to begin"
            color: Theme.text; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "ITERATION " + empty.iteration
            color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium
            font.letterSpacing: Theme.microFont * 0.16
        }
    }
}
