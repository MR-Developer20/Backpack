import QtQuick

// Line + area graph of the last N percentage samples (0-100), newest on the right.
Chamfer {
    id: graph
    property var samples: []
    property int capacity: 60
    property color lineColor: Theme.accent
    cut: Theme.cutMd
    color: Theme.outputBg
    borderColor: Theme.border

    onSamplesChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: Theme.s(10)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"), w = width, h = height
            ctx.reset()
            ctx.strokeStyle = Theme.border; ctx.lineWidth = 1
            for (var g = 0; g <= 4; g++) {        // 0/25/50/75/100% gridlines
                var gy = Math.round(h - g * h / 4) + 0.5
                ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
            }
            var s = graph.samples, n = s.length
            if (n < 2) return
            var step = w / (graph.capacity - 1), x0 = w - (n - 1) * step
            ctx.beginPath()
            for (var i = 0; i < n; i++) {
                var x = x0 + i * step, y = Math.round(h - h * Math.max(0, Math.min(100, s[i])) / 100)
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.strokeStyle = graph.lineColor; ctx.lineWidth = Math.max(2, Theme.s(2)); ctx.stroke()
            ctx.lineTo(w, h); ctx.lineTo(x0, h); ctx.closePath()
            ctx.globalAlpha = 0.18; ctx.fillStyle = graph.lineColor; ctx.fill(); ctx.globalAlpha = 1
        }
    }
    Text { font.family: Theme.fontSans; anchors { right: parent.right; top: parent.top; margins: Theme.s(12) } text: "100%"; color: Theme.muted; font.pixelSize: Theme.s(12) }
    Text { font.family: Theme.fontSans; anchors { right: parent.right; bottom: parent.bottom; margins: Theme.s(12) } text: "60 s"; color: Theme.muted; font.pixelSize: Theme.s(12) }
}
