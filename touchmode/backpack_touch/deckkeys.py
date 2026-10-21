"""Stream Deck key faces in the Field Terminal look, drawn with QPainter (no Pillow).

A face is a dict:
  {"kind": "icon",  "icon": "up", "label": "UP", "fill": False, "color": None, "dim": False}
  {"kind": "text",  "label": "SELECT", "sub": "", ...}      a word, big
  {"kind": "digit", "label": "7"}
  {"kind": "app",   "label": "Nmap", "sub": "DISCOVERY", "color": <category colour>}
  {"kind": "tab",   "label": "NETWORK", "sub": "SEC.01 // 26", "color": <section accent>}
  {"kind": "blank"}
`fill` = a filled key (`color`, default acid, with void ink); without it `color` makes an outline
key (border, glyph and label in that colour, like Stop and Reboot); `selected` = the 2px border.
Colours and glyph paths are Theme.qml's and Icon.qml's, so a key reads like the launcher's buttons.
"""
import re

from PySide6.QtCore import QBuffer, QIODevice, QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QFont, QFontMetricsF, QImage, QPainter, QPainterPath, QPen, QTransform

VOID = "#07090a"
HULL = "#0e1214"
HULL_RAISED = "#161c1f"
GRID = "#2a3438"
GRID_STRONG = "#5a6b70"
INK = "#e6ede8"
INK_MUTED = "#8d9c96"
ACID = "#c6ff1a"
CYAN = "#2fd8e8"
AMBER = "#ffb000"
SIGNAL = "#ff3d6e"
FONT = "JetBrains Mono"

# Theme.categoryColor
CATEGORY_COLORS = {
    "discovery": ACID, "connectivity": "#6cc4ff", "capture": AMBER, "wireless": "#b496ff",
    "throughput": "#8ff0c8", "dns-http": "#ff6fb0", "disks": CYAN, "recovery": "#ff8c42",
    "files": "#f2e15c", "transfer": "#b496ff", "extra": ACID,
}

# 24-unit outline glyphs (Icon.qml's grid and stroke); "fill" ones are solid
GLYPHS = {
    "up":        ("M5 15 L12 8 L19 15", ""),
    "down":      ("M5 9 L12 16 L19 9", ""),
    "left":      ("M15 5 L8 12 L15 19", ""),
    "right":     ("M9 5 L16 12 L9 19", ""),
    "home":      ("M3 11 L12 3 L21 11 M6 8.5 V21 H18 V8.5 M10 21 V14 H14 V21", ""),
    "back":      ("M10 5 L3 12 L10 19 M3 12 H21", ""),
    "backspace": ("M8 4 H22 V20 H8 L2 12 Z M11 9 L17 15 M17 9 L11 15", ""),
    "done":      ("M4 12 L10 18 L20 6", ""),
    "run":       ("", "M7 4 L20 12 L7 20 Z"),
    "stop":      ("", "M6 6 H18 V18 H6 Z"),
    "keyboard":  ("M2 4 H22 V20 H2 Z",
                  "M5 7 h2 v2 h-2 Z M9 7 h2 v2 h-2 Z M13 7 h2 v2 h-2 Z M17 7 h2 v2 h-2 Z "
                  "M7 11 h2 v2 h-2 Z M11 11 h2 v2 h-2 Z M15 11 h2 v2 h-2 Z M7 15 h10 v2 h-10 Z"),
    "settings":  ("M10.41 4.16 L10.71 1.48 L13.29 1.48 L13.59 4.16 L16.42 5.33 L18.53 3.65 L20.35 5.47 L18.67 7.58 "
                  "L19.84 10.41 L22.52 10.71 L22.52 13.29 L19.84 13.59 L18.67 16.42 L20.35 18.53 L18.53 20.35 L16.42 18.67 "
                  "L13.59 19.84 L13.29 22.52 L10.71 22.52 L10.41 19.84 L7.58 18.67 L5.47 20.35 L3.65 18.53 L5.33 16.42 "
                  "L4.16 13.59 L1.48 13.29 L1.48 10.71 L4.16 10.41 L5.33 7.58 L3.65 5.47 L5.47 3.65 L7.58 5.33 Z "
                  "M15.5 12 C15.5 13.933 13.933 15.5 12 15.5 C10.067 15.5 8.5 13.933 8.5 12 "
                  "C8.5 10.067 10.067 8.5 12 8.5 C13.933 8.5 15.5 10.067 15.5 12 Z", ""),
}

_TOKEN = re.compile(r"[MLHVCZmlhvcz]|[-+]?(?:\d*\.\d+|\d+\.?)")


def svg_path(d, k, ox=0.0, oy=0.0):
    """Icon.qml's path subset (M L H V C Z, relative h v l m c) scaled by k and moved to (ox, oy)."""
    p, cmd, nums = QPainterPath(), "", []
    x = y = sx = sy = 0.0

    def flush():
        nonlocal x, y, sx, sy, nums
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            for i in range(0, len(nums) - 1, 2):
                nx, ny = (x + nums[i], y + nums[i + 1]) if rel else (nums[i], nums[i + 1])
                if i == 0:
                    p.moveTo(ox + nx * k, oy + ny * k); sx, sy = nx, ny
                else:
                    p.lineTo(ox + nx * k, oy + ny * k)
                x, y = nx, ny
        elif c == "L":
            for i in range(0, len(nums) - 1, 2):
                x, y = (x + nums[i], y + nums[i + 1]) if rel else (nums[i], nums[i + 1])
                p.lineTo(ox + x * k, oy + y * k)
        elif c == "H":
            for v in nums:
                x = x + v if rel else v
                p.lineTo(ox + x * k, oy + y * k)
        elif c == "V":
            for v in nums:
                y = y + v if rel else v
                p.lineTo(ox + x * k, oy + y * k)
        elif c == "C":
            for i in range(0, len(nums) - 5, 6):
                q = nums[i:i + 6]
                if rel:
                    q = [q[0] + x, q[1] + y, q[2] + x, q[3] + y, q[4] + x, q[5] + y]
                p.cubicTo(ox + q[0] * k, oy + q[1] * k, ox + q[2] * k, oy + q[3] * k, ox + q[4] * k, oy + q[5] * k)
                x, y = q[4], q[5]
        elif c == "Z":
            p.closeSubpath(); x, y = sx, sy
        nums = []

    for t in _TOKEN.findall(d):
        if t.isalpha():
            if cmd:
                flush()
            cmd = t
        else:
            nums.append(float(t))
    if cmd:
        flush()
    return p


def chamfer(r, cut):
    """Chamfer.qml's outline: top-right and bottom-left corners cut."""
    p = QPainterPath()
    p.moveTo(r.left(), r.top())
    p.lineTo(r.right() - cut, r.top())
    p.lineTo(r.right(), r.top() + cut)
    p.lineTo(r.right(), r.bottom())
    p.lineTo(r.left() + cut, r.bottom())
    p.lineTo(r.left(), r.bottom() - cut)
    p.closeSubpath()
    return p


def _font(px, weight=QFont.Weight.Bold, tracking=0.0):
    f = QFont(FONT)
    f.setPixelSize(max(6, int(round(px))))
    f.setWeight(weight)
    if tracking:
        f.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, px * tracking)
    return f


def _wrap(text, font, width, max_lines, split=False):
    """Greedy word wrap; the last line elides. A word wider than the line is cut into pieces when
    `split`, else the wrap fails (None) so the caller tries a smaller font."""
    fm = QFontMetricsF(font)
    words, lines, cur = [], [], ""
    for w in text.split():
        if fm.horizontalAdvance(w) <= width:
            words.append(w)
        elif not split:
            return None
        else:
            piece = ""
            for ch in w:
                if piece and fm.horizontalAdvance(piece + ch) > width:
                    words.append(piece); piece = ""
                piece += ch
            words.append(piece)
    for w in words:
        trial = (cur + " " + w).strip()
        if fm.horizontalAdvance(trial) <= width:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        lines[-1] = fm.elidedText(lines[-1] + " …", Qt.TextElideMode.ElideRight, width)
    return lines


def _fit_lines(text, px, width, max_lines, weight=QFont.Weight.Bold, tracking=0.0, min_px=8):
    """The largest font from px down to min_px at which the words fit whole in max_lines; at
    min_px a long word is cut across lines instead (a key is too small to shrink further)."""
    size = px
    min_px = int(round(min_px))
    while size >= min_px:
        f = _font(size, weight, tracking)
        lines = _wrap(text, f, width, max_lines)
        if lines is not None and not lines[-1].endswith("…"):
            return f, lines
        size -= 1
    f = _font(min_px, weight, tracking)
    return f, _wrap(text, f, width, max_lines, split=True)


def _draw_lines(p, font, lines, color, rect, align=Qt.AlignmentFlag.AlignHCenter, line_h=None):
    fm = QFontMetricsF(font)
    lh = line_h or fm.height()
    p.setFont(font)
    p.setPen(QColor(color))
    y = rect.top() + (rect.height() - lh * len(lines)) / 2
    for ln in lines:
        p.drawText(QRectF(rect.left(), y, rect.width(), lh), int(align | Qt.AlignmentFlag.AlignVCenter), ln)
        y += lh


def _glyph(p, name, cx, cy, size, color):
    stroke, fill = GLYPHS[name]
    k = size / 24.0
    ox, oy = cx - size / 2, cy - size / 2
    if stroke:
        pen = QPen(QColor(color), max(1.5, 2 * k))
        pen.setJoinStyle(Qt.PenJoinStyle.MiterJoin); pen.setCapStyle(Qt.PenCapStyle.SquareCap)
        p.setPen(pen); p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawPath(svg_path(stroke, k, ox, oy))
    if fill:
        p.setPen(Qt.PenStyle.NoPen); p.setBrush(QColor(color))
        p.drawPath(svg_path(fill, k, ox, oy))


def render_key(face, size, pressed=False):
    """One key face as a size x size QImage."""
    s = float(size)
    u = s / 72.0                    # 1 unit = 1px on the 72px keys of the 15-key deck
    img = QImage(size, size, QImage.Format.Format_RGB32)
    img.fill(QColor(VOID))
    kind = face.get("kind", "blank")
    if kind == "blank":
        return img
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    p.setRenderHint(QPainter.RenderHint.TextAntialiasing)
    if face.get("dim"):
        p.setOpacity(0.35)

    color = face.get("color")          # the fill of a primary, or an outline key's border and ink
    accent = color or ACID
    filled = bool(face.get("fill"))
    selected = bool(face.get("selected"))
    ink = VOID if filled else (color if color and kind not in ("app", "tab") else INK)
    fill = QColor(accent if filled else HULL_RAISED)
    if pressed:
        fill = fill.lighter(115 if filled else 160)
    outline = filled or (color and kind not in ("app", "tab"))
    border = QColor(accent if (outline or selected) else GRID_STRONG)
    bw = (2 if selected else 1) * max(1.0, u)

    inset = 3 * u
    r = QRectF(inset, inset, s - inset * 2, s - inset * 2)
    p.setPen(QPen(border, bw)); p.setBrush(fill)
    p.drawPath(chamfer(r.adjusted(bw / 2, bw / 2, -bw / 2, -bw / 2), 8 * u))

    pad = 7 * u
    inner = r.adjusted(pad, pad, -pad, -pad)
    label, sub = face.get("label", ""), face.get("sub", "")
    micro = _font(9 * u, QFont.Weight.DemiBold, 0.12)

    if kind == "icon":
        has_label = bool(label)
        gsize = 30 * u if has_label else 38 * u
        cy = inner.top() + (inner.height() - (13 * u if has_label else 0)) / 2
        _glyph(p, face["icon"], inner.center().x(), cy, gsize, ink)
        if has_label:
            f, lines = _fit_lines(label.upper(), 9.5 * u, inner.width(), 1, QFont.Weight.Bold, 0.1, 6)
            _draw_lines(p, f, lines, ink if (filled or color) else INK_MUTED,
                        QRectF(inner.left(), inner.bottom() - 12 * u, inner.width(), 12 * u))
    elif kind == "digit":
        f = _font(30 * u, QFont.Weight.Bold)
        _draw_lines(p, f, [label], ink, inner)
    elif kind == "text":
        f, lines = _fit_lines(label.upper(), 14 * u, inner.width(), 2, QFont.Weight.ExtraBold, 0.06, 7)
        body = inner.adjusted(0, 0, 0, -(12 * u if sub else 0))
        _draw_lines(p, f, lines, ink, body)
        if sub:
            _draw_lines(p, micro, [sub.upper()], VOID if filled else INK_MUTED,
                        QRectF(inner.left(), inner.bottom() - 12 * u, inner.width(), 12 * u))
    elif kind == "app":
        # Tile.qml in miniature: category rail, name, micro strip
        rail = QRectF(r.left() + 5 * u, r.top() + 6 * u, 3 * u, r.height() - 12 * u)
        p.fillRect(rail, QColor(accent))
        right = r.right() - 4 * u
        body = QRectF(rail.right() + 4 * u, inner.top(), right - rail.right() - 4 * u, inner.height() - 11 * u)
        if not (sub and u >= 1.2):   # the category strip only where it is legible (XL, +)
            body.setBottom(inner.bottom())
        f, lines = _fit_lines(label, 13 * u, body.width(), 3, QFont.Weight.Bold, 0.0, 9 * u)
        _draw_lines(p, f, lines, INK, body, Qt.AlignmentFlag.AlignLeft)
        if sub and u >= 1.2:
            mf, ml = _fit_lines(sub.upper(), 8 * u, body.width(), 1, QFont.Weight.DemiBold, 0.12, 6)
            _draw_lines(p, mf, ml, INK_MUTED, QRectF(body.left(), inner.bottom() - 10 * u, body.width(), 10 * u),
                        Qt.AlignmentFlag.AlignLeft)
    elif kind == "tab":
        # a section tab: accent label over its micro strip, underlined
        f, lines = _fit_lines(label.upper(), 12 * u, inner.width(), 1, QFont.Weight.Bold, 0.1, 7)
        _draw_lines(p, f, lines, accent, QRectF(inner.left(), inner.top(), inner.width(), inner.height() - 22 * u))
        mf, ml = _fit_lines(sub.upper(), 9 * u, inner.width(), 1, QFont.Weight.DemiBold, 0.12, 6)
        _draw_lines(p, mf, ml, INK_MUTED, QRectF(inner.left(), inner.bottom() - 24 * u, inner.width(), 12 * u))
        p.fillRect(QRectF(r.left() + 6 * u, r.bottom() - 9 * u, r.width() - 12 * u, 3 * u), QColor(accent))
    p.end()
    return img


def render_strip(zones, width, height):
    """The Stream Deck + touch strip: one zone per dial, each a micro heading over its two uses."""
    img = QImage(width, height, QImage.Format.Format_RGB32)
    img.fill(QColor(VOID))
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    p.setRenderHint(QPainter.RenderHint.TextAntialiasing)
    zw = width / max(1, len(zones))
    head = _font(11, QFont.Weight.DemiBold, 0.14)
    body = _font(17, QFont.Weight.Bold)
    for i, z in enumerate(zones):
        r = QRectF(i * zw + 4, 6, zw - 8, height - 12)
        p.setPen(QPen(QColor(GRID_STRONG if not z.get("accent") else z["accent"]), 1))
        p.setBrush(QColor(HULL_RAISED))
        p.drawPath(chamfer(r, 10))
        p.setFont(head); p.setPen(QColor(INK_MUTED))
        p.drawText(r.adjusted(12, 6, -12, 0), int(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop), z.get("head", "").upper())
        lines = [x for x in (z.get("turn", ""), z.get("press", "")) if x]
        p.setFont(body)
        y = r.top() + 34
        for j, ln in enumerate(lines):
            p.setPen(QColor(z.get("accent") or INK) if j == 0 else QColor(INK_MUTED))
            p.drawText(QRectF(r.left() + 12, y, r.width() - 24, 24), int(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter),
                       QFontMetricsF(body).elidedText(ln, Qt.TextElideMode.ElideRight, r.width() - 24))
            y += 24
    p.end()
    return img


def to_native(img, fmt):
    """What PILHelper.to_native_*_format does, in Qt: fit, rotate (counter-clockwise, as PIL), flip, encode."""
    w, h = fmt["size"]
    if (img.width(), img.height()) != (w, h):
        img = img.scaled(w, h, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
    if fmt.get("rotation"):
        img = img.transformed(QTransform().rotate(-fmt["rotation"]))
    fx, fy = fmt.get("flip", (False, False))
    if fx or fy:
        img = img.mirrored(bool(fx), bool(fy))
    img = img.convertToFormat(QImage.Format.Format_RGB888)
    buf = QBuffer()
    buf.open(QIODevice.OpenModeFlag.WriteOnly)
    img.save(buf, fmt["format"], 100)
    return bytes(buf.data())


def compose(faces, cols, rows, size, gap=None):
    """A picture of the whole deck (for screenshots and tests): the faces on a dark plate."""
    gap = gap if gap is not None else max(6, size // 6)
    W, H = cols * size + (cols + 1) * gap, rows * size + (rows + 1) * gap
    img = QImage(W, H, QImage.Format.Format_RGB32)
    img.fill(QColor("#000000"))
    p = QPainter(img)
    for i, f in enumerate(faces[:cols * rows]):
        c, r = i % cols, i // cols
        p.drawImage(QPointF(gap + c * (size + gap), gap + r * (size + gap)), f)
    p.end()
    return img


def stack(top, bottom, gap=12):
    """`bottom` centred under `top` on the same dark plate (the + deck's keys over its strip)."""
    W, H = max(top.width(), bottom.width()), top.height() + gap + bottom.height()
    img = QImage(W, H, QImage.Format.Format_RGB32)
    img.fill(QColor("#000000"))
    p = QPainter(img)
    p.drawImage(QPointF((W - top.width()) / 2, 0), top)
    p.drawImage(QPointF((W - bottom.width()) / 2, top.height() + gap), bottom)
    p.end()
    return img
