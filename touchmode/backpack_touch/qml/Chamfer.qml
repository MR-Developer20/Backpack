import QtQuick
import QtQuick.Shapes

// A filled, bordered box with the top-right and bottom-left corners cut (the design's chamfer).
// Used instead of Rectangle for panels, tiles, buttons and fields; children draw on top.
Item {
    id: c
    property color color: Theme.panel
    property color borderColor: Theme.border
    property real borderWidth: 1      // the same 1px everywhere; 0 = no border
    property real cut: Theme.cutSm

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4
        ShapePath {
            id: sp
            readonly property real h: c.borderWidth / 2
            readonly property real k: Math.min(c.cut, c.width / 2, c.height / 2)
            fillColor: c.color
            strokeColor: c.borderWidth > 0 ? c.borderColor : "transparent"
            strokeWidth: Math.max(c.borderWidth, 0)
            joinStyle: ShapePath.MiterJoin
            startX: h; startY: h
            PathLine { x: c.width - sp.k; y: sp.h }
            PathLine { x: c.width - sp.h; y: sp.k }
            PathLine { x: c.width - sp.h; y: c.height - sp.h }
            PathLine { x: sp.k; y: c.height - sp.h }
            PathLine { x: sp.h; y: c.height - sp.k }
            PathLine { x: sp.h; y: sp.h }
        }
    }
}
