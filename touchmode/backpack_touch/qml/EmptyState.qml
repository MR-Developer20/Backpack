import QtQuick

// Empty tool pane: a 24px scan grid in `grid` and the dragon-curve fractal (the "iteration" pages
// of Jurassic Park, the novel) in `gridStrong`, under the hint text.
Item {
    id: empty
    property int iteration: 11

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"), w = width, h = height, step = Theme.s(24)
            ctx.reset()
            ctx.strokeStyle = Theme.border; ctx.lineWidth = 1
            ctx.beginPath()
            for (var x = step; x < w; x += step) { ctx.moveTo(Math.round(x) + 0.5, 0); ctx.lineTo(Math.round(x) + 0.5, h) }
            for (var y = step; y < h; y += step) { ctx.moveTo(0, Math.round(y) + 0.5); ctx.lineTo(w, Math.round(y) + 0.5) }
            ctx.stroke()

            // dragon curve: turn sequence by the paper-folding rule, then fit it to the pane
            var n = Math.pow(2, empty.iteration), dx = 1, dy = 0, px = 0, py = 0
            var pts = [[0, 0]], minX = 0, maxX = 0, minY = 0, maxY = 0
            for (var i = 1; i <= n; i++) {
                px += dx; py += dy; pts.push([px, py])
                minX = Math.min(minX, px); maxX = Math.max(maxX, px); minY = Math.min(minY, py); maxY = Math.max(maxY, py)
                var k = i; while ((k & 1) === 0) k >>= 1
                var right = ((k >> 1) & 1) === 1, t = dx
                if (right) { dx = dy; dy = -t } else { dx = -dy; dy = t }
            }
            var box = Math.min(w, h) * 0.7, sc = box / Math.max(maxX - minX, maxY - minY)
            var ox = (w - (maxX - minX) * sc) / 2 - minX * sc, oy = (h - (maxY - minY) * sc) / 2 - minY * sc - Theme.s(20)
            ctx.strokeStyle = Theme.borderStrong; ctx.lineWidth = Math.max(1, Theme.s(1.5))
            ctx.beginPath()
            ctx.moveTo(ox + pts[0][0] * sc, oy + pts[0][1] * sc)
            for (var j = 1; j < pts.length; j++) ctx.lineTo(ox + pts[j][0] * sc, oy + pts[j][1] * sc)
            ctx.stroke()
        }
        Connections { target: Theme; function onScaleChanged() { canvas.requestPaint() } }
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
