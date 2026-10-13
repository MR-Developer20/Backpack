import QtQuick
import QtQuick.Shapes

// A filled, bordered box with the top-right and bottom-left corners cut (the design's chamfer).
// Pure geometry: the path is rebuilt from this item's own size and drawn by the curve renderer
// with analytic anti-aliasing, so nothing is rasterised and scaled. The shape snaps to whole
// pixels so the 1px border lands on exactly one pixel row or column. A box whose border is its
// own fill colour (a filled button) is drawn as one solid path, so a disabled one at 45% opacity
// has no brighter rim where a stroke would overlap the fill.
Item {
    id: c
    property color color: Theme.panel
    property color borderColor: Theme.border
    property real borderWidth: 1      // the same 1px everywhere; 0 = no border
    property real cut: Theme.cutSm

    Shape {
        id: sh
        width: Math.round(c.width); height: Math.round(c.height)
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            id: sp
            readonly property bool solid: c.borderWidth <= 0 || Qt.colorEqual(c.borderColor, c.color)
            readonly property real h: solid ? 0 : c.borderWidth / 2
            readonly property real k: Math.min(c.cut, sh.width / 2, sh.height / 2)
            fillColor: c.color
            strokeColor: c.borderColor
            strokeWidth: solid ? -1 : c.borderWidth
            joinStyle: ShapePath.MiterJoin
            startX: h; startY: h
            PathLine { x: sh.width - sp.k; y: sp.h }
            PathLine { x: sh.width - sp.h; y: sp.k }
            PathLine { x: sh.width - sp.h; y: sh.height - sp.h }
            PathLine { x: sp.k; y: sh.height - sp.h }
            PathLine { x: sp.h; y: sh.height - sp.k }
            PathLine { x: sp.h; y: sp.h }
        }
    }
}
