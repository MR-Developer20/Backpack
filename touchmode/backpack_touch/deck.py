"""Elgato Stream Deck as a second input for GUI Mode.

The deck shows one of four screens, picked from what the launcher is doing:
  apps    no tool open: the current tab's tools as keys, plus Home, Settings, the tab and paging
  nav     a tool or sheet is open: arrows move keyboard focus, Select presses what has focus
  list    focus is on an open dropdown: up/down move in the list, Select picks
  keypad  focus is on an address or number field: 0-9 . / Delete Done
Arrows move focus geometrically (to the nearest focusable control in that direction, inside the
open sheet if there is one) and Select sends Space, so every control the keyboard can reach works
from the deck. Dropdowns open by themselves when the deck moves focus onto them.

Hardware access is the vendored python-elgato-streamdeck (_vendor/StreamDeck) over libhidapi; the
udev rule 70-streamdeck.rules gives the logged-in user the device. No deck, no library, no
permission: the launcher runs as before. Test hook: BACKPACK_DECK=dummy-15|dummy-6|dummy-32|
dummy-plus|dummy-neo uses the library's dummy transport (no USB), BACKPACK_DECK_SHOT=FILE.png
saves the deck's faces on every change.
"""
import os
import sys

from PySide6.QtCore import Property, QObject, QRectF, Qt, QTimer, Signal, Slot, QEvent, QMetaObject
from PySide6.QtGui import QGuiApplication, QKeyEvent
from shiboken6 import getCppPointer

from . import deckkeys as K
from .manifest import CATEGORY_LABELS, CATEGORY_ORDER, SECTIONS

# ------------------------------------------------------------------ layouts
# One grid per screen, a row per string, a key per token, left to right. "app" = the next tool of
# the page; "." = a dark key. keypad is a list of pages ("page" flips to the next one).
LAYOUTS = {
    "6": {   # Stream Deck Mini: 3 x 2
        "apps": ["app app app", "app more settings"],
        "nav": ["home up select", "left down right"],
        "list": ["home up select", "back down ."],
        "keypad": [["1 2 3", "4 5 page"], ["6 7 8", "9 0 page"], ["dot slash del", "done home page"]],
    },
    "8": {   # Stream Deck + and Neo: 4 x 2 (the + adds dials and a touch strip)
        "apps": ["app app app app", "app section more settings"],
        "nav": ["select up run home", "left down right settings"],
        "list": ["select up . home", "back down . settings"],
        "keypad": [["1 2 3 4", "5 6 del page"], ["7 8 9 0", "dot slash done page"]],
    },
    "15": {   # Stream Deck (Original, MK.2): 5 x 3
        "apps": ["app app app app app", "app app app app app", "home settings section prev next"],
        "nav": ["title up . run home", "left select right stop settings", "keyboard down back . ."],
        "list": ["title up . . home", ". select . . settings", ". down back . ."],
        "keypad": [["7 8 9 slash del", "4 5 6 dot done", "1 2 3 0 home"]],
    },
    "32": {   # Stream Deck XL: 8 x 4
        "apps": ["app app app app app app app app", "app app app app app app app app",
                 "app app app app app app app app", "app app app home settings section prev next"],
        "nav": ["title . up . . run stop home", ". left select right . . . settings",
                ". . down . . keyboard back .", ". . . . . . . ."],
        "list": ["title . up . . . . home", ". . select . . . . settings", ". . down . . . back .", ". . . . . . . ."],
        "keypad": [["7 8 9 slash . . . home", "4 5 6 dot . . . settings", "1 2 3 del . . . .", ". 0 . done . . . ."]],
    },
}
# Stream Deck + dials, per screen: (heading, turn does, press does) for each of the four
DIALS = {
    "apps":   [("page", "prev/next", ""), ("tab", "tabs", ""), ("home", "", "home"), ("settings", "", "settings")],
    "nav":    [("focus", "up/down", "select"), ("focus", "left/right", "back"), ("home", "", "home"), ("settings", "", "settings")],
    "list":   [("list", "up/down", "select"), ("", "", "back"), ("home", "", "home"), ("settings", "", "settings")],
    "keypad": [("keypad", "", "done"), ("", "", "del"), ("home", "", "home"), ("settings", "", "settings")],
}
DIAL_WORDS = {"prev/next": "◀ ▶ page", "tabs": "◀ ▶ tab", "up/down": "▲ ▼ move", "left/right": "◀ ▶ move", "select": "press: select",
              "back": "press: back", "home": "press: home", "settings": "press: settings", "done": "press: done",
              "del": "press: delete", "": ""}
NEO_TOUCH_KEYS = ["home", "settings"]   # the Neo's two touch points, left and right
SHEET_TITLES = {"settings": "Settings", "wifi": "Wi-Fi", "monitor": "System"}
ARROWS = {"up", "down", "left", "right"}
CHARS = {str(d): (getattr(Qt.Key, "Key_%d" % d), str(d)) for d in range(10)}
CHARS["dot"] = (Qt.Key.Key_Period, ".")
CHARS["slash"] = (Qt.Key.Key_Slash, "/")
ROW_SLACK = 48            # px sideways a control may sit further out than the nearest one and still share its row
HOLD_CLEAR_S = 0.6        # Delete held this long clears the field
REPEAT_DELAY_MS, REPEAT_MS = 400, 140   # held arrows repeat


def layout_for(key_count):
    """The layout for a deck with this many keys (unknown decks get the largest that fits)."""
    sizes = sorted(int(k) for k in LAYOUTS)
    fit = [s for s in sizes if s <= key_count]
    return str(fit[-1] if fit else sizes[0])


def same(a, b):
    return a is not None and b is not None and getCppPointer(a)[0] == getCppPointer(b)[0]


def prop(item, name):
    return None if item is None else item.property(name)


def role_of(item):
    """The deckRole of the item or the nearest ancestor that has one (a list's rows inherit "list")."""
    while item is not None:
        r = item.property("deckRole")
        if r:
            return r
        item = item.parentItem()
    return None


def scene_rect(it):
    return it.mapRectToScene(QRectF(0, 0, it.width(), it.height()))


def _section_tools(tools, section):
    order = {c: i for i, c in enumerate(CATEGORY_ORDER)}
    return sorted((t for t in tools if t.get("section") == section), key=lambda t: order.get(t["category"], 99))


class Deck(QObject):
    """Owns the deck (hotplug, drawing, input) and drives the launcher window."""
    connectedChanged = Signal()
    request = Signal(str, str)        # to Main.qml: tool <id> | home | settings | section <id> | run | stop | back | keyboard
    _keySig = Signal(int, bool)       # from the library's reader thread to the GUI thread
    _dialSig = Signal(int, str, int)
    _touchSig = Signal(int)

    def __init__(self, tools, runner=None, system=None, parent=None):
        super().__init__(parent)
        self._tools = tools
        self._by_id = {t["id"]: t for t in tools}
        self._sections = [sid for sid, _, cats in SECTIONS if any(t["category"] in cats for t in tools)]
        self._runner, self._system = runner, system
        self._window = None
        self._deck = None
        self._layout = None
        self._name = ""
        self._manager = None
        self._dummy = os.environ.get("BACKPACK_DECK", "")
        self._shot = os.environ.get("BACKPACK_DECK_SHOT", "")
        # launcher state (Main.qml calls setLauncher)
        self._tool, self._section, self._sheet = "", self._sections[0] if self._sections else "network", ""
        self._page = {}
        self._kpage = 0
        self._editing = None          # the address field the keypad types into
        self._last_focus = None
        self._last_role = None
        self._faces = []              # what each key shows now (dicts)
        self._sent = {}               # key -> face last written, so only changed keys are redrawn
        self._pressed = None
        self._pressed_action = None
        self._actions = []
        self._held_cleared = False
        self._screen = ""
        self._strip_sent = None

        self._keySig.connect(self._on_key)
        self._dialSig.connect(self._on_dial)
        self._touchSig.connect(self._on_touch)
        self._scan = QTimer(self, interval=2000, timeout=self._hotplug)
        self._poll = QTimer(self, interval=300, timeout=self.refresh)   # follows touch-driven changes too
        self._repeat = QTimer(self, interval=REPEAT_MS, timeout=self._repeat_tick)
        self._repeat_wait = QTimer(self, singleShot=True, interval=REPEAT_DELAY_MS, timeout=self._repeat.start)
        self._hold = QTimer(self, singleShot=True, interval=int(HOLD_CLEAR_S * 1000), timeout=self._hold_clear)

    # ---------------------------------------------------------------- QML-facing
    @Property(bool, notify=connectedChanged)
    def connected(self):
        return self._deck is not None

    @Property(str, notify=connectedChanged)
    def name(self):
        return self._name

    @Slot(str, str, str)
    def setLauncher(self, tool_id, section, sheet):
        if section != self._section:
            self._page[section] = 0
        self._tool, self._section, self._sheet = tool_id, section, sheet
        self.refresh()

    def attach(self, window):
        """Start: watch the launcher window's focus and look for a deck."""
        self._window = window
        window.activeFocusItemChanged.connect(self._on_focus)
        self._hotplug()
        self._scan.start()

    def stop(self):
        self._close()
        self._scan.stop()

    # ---------------------------------------------------------------- device
    def _open_manager(self):
        if self._manager is None:
            here = os.path.join(os.path.dirname(__file__), "_vendor")
            if here not in sys.path:
                sys.path.insert(0, here)
            from StreamDeck.DeviceManager import DeviceManager
            self._manager = DeviceManager(transport="dummy" if self._dummy else None)
        return self._manager

    def _hotplug(self):
        if self._deck is not None:
            try:
                if self._deck.connected():
                    return
            except Exception:
                pass
            self._close()
        try:
            decks = [d for d in self._open_manager().enumerate() if d.is_visual()]
        except Exception as e:   # no libhidapi: say so once, then stay out of the way
            print("backpack-deck: Stream Deck support off:", e, file=sys.stderr)
            self._scan.stop()
            return
        if self._dummy:
            want = {"dummy-6": "StreamDeckMini", "dummy-15": "StreamDeckOriginalV2", "dummy-32": "StreamDeckXL",
                    "dummy-plus": "StreamDeckPlus", "dummy-neo": "StreamDeckNeo"}.get(self._dummy, "StreamDeckOriginalV2")
            decks = [d for d in decks if type(d).__name__ == want][:1]
        for d in decks:
            try:
                d.open()
                d.reset()
                d.set_brightness(70)
            except Exception as e:   # busy, or no permission (udev rule missing): try again later
                print("backpack-deck: cannot open %s: %s" % (d.deck_type(), e), file=sys.stderr)
                continue
            self._deck = d
            self._name = d.deck_type()
            self._layout = LAYOUTS[layout_for(d.key_count())]
            self._sent, self._strip_sent = {}, None
            d.set_key_callback(lambda deck, k, state: self._keySig.emit(k, state))
            if d.dial_count():
                d.set_dial_callback(lambda deck, i, ev, v: self._dialSig.emit(i, ev.name, int(v)))
            if d.is_touch() and d.TOUCHSCREEN_PIXEL_WIDTH:
                d.set_touchscreen_callback(lambda deck, ev, v: self._touchSig.emit(int((v or {}).get("x", 0))))
            self.connectedChanged.emit()
            self._poll.start()
            self.refresh()
            return

    def _close(self):
        d, self._deck = self._deck, None
        self._poll.stop()
        if d is not None:
            try:
                d.reset()
                d.close()
            except Exception:
                pass
            self._name = ""
            self.connectedChanged.emit()

    # ---------------------------------------------------------------- the launcher's focus
    def _focus_item(self):
        return self._window.activeFocusItem() if self._window else None

    def _on_focus(self):
        fi = self._focus_item()
        role = role_of(fi)
        if role == "ip" and not same(fi, self._last_focus):
            self._begin_editing(fi)
        elif role != "ip":
            self._editing = None
        if role == "dropdown" and self._last_role == "list":
            # back from the list: Qt gives focus back without the ring; put the ring back
            QTimer.singleShot(0, lambda it=fi: it.forceActiveFocus(Qt.FocusReason.TabFocusReason))
        self._last_focus, self._last_role = fi, role
        self.refresh()

    def _begin_editing(self, field):
        """The keypad takes over the field. Its text is selected, so the first digit replaces it
        (an address is mostly typed anew); Delete first drops the selection and one character."""
        self._editing = field
        self._kpage = 0
        QMetaObject.invokeMethod(field, "selectAll")

    def _has_selection(self, field):
        return (field.property("selectedText") or "") != ""

    def _scope(self):
        """The item arrows move within: the topmost open sheet, else the whole window bar the overlay."""
        root = self._window.contentItem()
        overlay = None
        stack = list(root.childItems())
        while stack and overlay is None:
            it = stack.pop(0)
            if it.metaObject().className() == "QQuickOverlay":
                overlay = it
            else:
                stack.extend(it.childItems())
        if overlay is not None:
            for c in reversed(overlay.childItems()):
                if c.isVisible() and c.width() > 0 and self._focusables(c):
                    return c, None
        return root, overlay

    def _focusables(self, scope, skip=None):
        out = []

        def walk(it):
            if not it.isVisible() or it.opacity() < 0.01 or same(it, skip):
                return
            if (it.activeFocusOnTab() and it.isEnabled() and it.width() > 1 and it.height() > 1
                    and "Slider" not in it.metaObject().className()):
                out.append(it)
            for c in it.childItems():
                walk(c)
        walk(scope)
        return out

    def _current(self, items):
        it = self._focus_item()
        while it is not None:
            for c in items:
                if same(c, it):
                    return c
            it = it.parentItem()
        return None

    @staticmethod
    def _first(items):
        return min(items, key=lambda it: (round(scene_rect(it).top() / 8), scene_rect(it).left()))

    @staticmethod
    def _neighbour(cur, items, d):
        """The control an arrow moves to. Up/down: the nearest row in that direction; in it, the
        control under this one (most of this one's width over it: a grid, a column), else the row's
        first control (a form: from a field down to Run). Left/right: the nearest on the same row."""
        cr = scene_rect(cur)
        cc = cr.center()
        cands = []
        for it in items:
            if same(it, cur):
                continue
            r = scene_rect(it)
            c = r.center()
            if d in ("up", "down"):
                primary = (c.y() - cc.y()) * (1 if d == "down" else -1)
                gap = max(0.0, r.left() - cr.right(), cr.left() - r.right())
                if primary > cr.height() / 2:   # below (above) this one, not beside it
                    cands.append((primary, r, it, gap))
            else:
                primary = (c.x() - cc.x()) * (1 if d == "right" else -1)
                gap = max(0.0, r.top() - cr.bottom(), cr.top() - r.bottom())
                if primary > 2 and gap <= cr.height() / 2:   # left/right stays on its row
                    cands.append((primary + gap * 3 + abs(c.y() - cc.y()) * 0.5, r, it, gap))
        if not cands:
            return None
        if d in ("left", "right"):
            return min(cands, key=lambda t: t[0])[2]
        # the nearest row, counting sideways distance double (so a move stays in its pane)
        lead = min(cands, key=lambda t: t[0] + t[3] * 2)
        row = [t for t in cands if t[0] <= lead[0] + max(12.0, cr.height() / 2) and t[3] <= lead[3] + ROW_SLACK]

        def over(r):
            return max(0.0, min(r.right(), cr.right()) - max(r.left(), cr.left())) / max(1.0, cr.width())
        best = max(row, key=lambda t: (over(t[1]), -abs(t[1].center().x() - cc.x())))
        if over(best[1]) >= 0.5:
            return best[2]
        return min(row, key=lambda t: t[1].left())[2]

    def _reveal(self, it):
        """Scroll every Flickable around `it` so it is in view."""
        p = it.parentItem()
        while p is not None:
            if p.inherits("QQuickFlickable"):
                r = it.mapRectToItem(p, QRectF(0, 0, it.width(), it.height()))
                cy, h, m = p.property("contentY"), p.height(), 8
                ny = cy
                if r.top() < 0:
                    ny = cy + r.top() - m
                elif r.bottom() > h:
                    ny = cy + min(r.bottom() - h + m, r.top())
                if ny != cy:
                    oy, ch = p.property("originY") or 0, p.property("contentHeight") or 0
                    p.setProperty("contentY", max(oy, min(ny, oy + max(0.0, ch - h))))
            p = p.parentItem()

    def _focus(self, it, open_lists=True):
        if self._system is not None:
            self._system._touch = False   # focus from the deck never pops up the on-screen keyboard
        it.forceActiveFocus(Qt.FocusReason.TabFocusReason)
        self._reveal(it)
        if open_lists and role_of(it) == "dropdown" and not prop(it, "deckListOpen"):
            QMetaObject.invokeMethod(it, "deckOpenList")
        self.refresh()

    def _move(self, d):
        if self._window is None:
            return
        scope, skip = self._scope()
        items = self._focusables(scope, skip)
        if not items:
            return
        cur = self._current(items)
        target = self._first(items) if cur is None else self._neighbour(cur, items, d)
        if target is not None:
            self._focus(target)

    def focusToolPane(self):
        """After a tool opens from the deck: focus its first control (an action, a field)."""
        if self._window is None:
            return
        pane = self._find(self._window.contentItem(), "toolPane")
        items = self._focusables(pane) if pane is not None else []
        if items:
            self._focus(self._first(items))

    @staticmethod
    def _find(root, name):
        stack = [root]
        while stack:
            it = stack.pop()
            if it.objectName() == name:
                return it
            stack.extend(it.childItems())
        return None

    def _send_key(self, key, text=""):
        if self._window is None:
            return
        for t in (QEvent.Type.KeyPress, QEvent.Type.KeyRelease):
            QGuiApplication.sendEvent(self._window, QKeyEvent(t, key, Qt.KeyboardModifier.NoModifier, text))

    # ---------------------------------------------------------------- screens
    def screen(self):
        fi = self._focus_item()
        role = role_of(fi)
        if role == "list" or (role == "dropdown" and prop(fi, "deckListOpen")):
            return "list"
        if role == "ip" and same(fi, self._editing):
            return "keypad"
        if self._tool or self._sheet:
            return "nav"
        return "apps"

    def _grid(self, screen):
        g = self._layout[screen]
        if screen == "keypad":
            g = g[self._kpage % len(g)]
        return [tok for row in g for tok in row.split()]

    def _apps(self):
        tools = _section_tools(self._tools, self._section)
        slots = self._grid("apps").count("app")
        pages = max(1, -(-len(tools) // slots))
        page = min(self._page.get(self._section, 0), pages - 1)
        return tools[page * slots:(page + 1) * slots], page, pages

    def _accent(self):
        return K.CYAN if self._section == "data" else K.ACID

    def _face(self, tok, screen, apps_iter, page, pages):
        """What key `tok` shows on `screen`; its action is the same token."""
        running = bool(self._runner and self._runner.running)
        tool = self._by_id.get(self._tool)
        acc = self._accent()
        if tok == "app":
            t = next(apps_iter, None)
            if t is None:
                return {"kind": "blank"}, None
            return {"kind": "app", "label": t["name"], "sub": CATEGORY_LABELS.get(t["category"], ""),
                    "color": K.CATEGORY_COLORS.get(t["category"], K.INK_MUTED),
                    "selected": t["id"] == self._tool}, ("tool", t["id"])
        if tok in ARROWS:
            return {"kind": "icon", "icon": tok}, tok
        if tok == "select":
            return {"kind": "text", "label": "Select", "fill": True, "color": K.ACID}, tok
        if tok == "home":
            return {"kind": "icon", "icon": "home", "label": "Home"}, tok
        if tok == "settings":
            return {"kind": "icon", "icon": "settings", "label": "Settings", "selected": self._sheet == "settings"}, tok
        if tok == "back":
            return {"kind": "icon", "icon": "back", "label": "Back"}, tok
        if tok == "keyboard":
            on = bool(self._system and self._system.keyboardVisible)
            return {"kind": "icon", "icon": "keyboard", "label": "Keys", "color": K.AMBER if on else None}, tok
        if tok == "run":
            if not tool:
                return {"kind": "blank"}, None
            word = "Open" if tool.get("gui") or tool.get("section") == "extra" else "Run"
            return {"kind": "icon", "icon": "run", "label": word, "fill": True, "color": acc, "dim": running}, tok
        if tok == "stop":
            if not tool or tool.get("section") == "extra":
                return {"kind": "blank"}, None
            return {"kind": "icon", "icon": "stop", "label": "Stop", "color": K.SIGNAL, "dim": not running}, tok
        if tok == "title":
            if tool:
                return {"kind": "app", "label": tool["name"], "sub": CATEGORY_LABELS.get(tool["category"], ""),
                        "color": K.CATEGORY_COLORS.get(tool["category"], K.INK_MUTED), "selected": True}, None
            if self._sheet:
                return {"kind": "text", "label": SHEET_TITLES.get(self._sheet, self._sheet)}, None
            return {"kind": "blank"}, None
        if tok == "section":
            label = next((lbl for sid, lbl, _ in SECTIONS if sid == self._section), self._section)
            n = len(_section_tools(self._tools, self._section))
            idx = self._sections.index(self._section) + 1 if self._section in self._sections else 1
            return {"kind": "tab", "label": label, "sub": "SEC.%02d // %d" % (idx, n), "color": acc}, tok
        if tok in ("prev", "next"):
            ok = page > 0 if tok == "prev" else page < pages - 1
            if pages <= 1:
                return {"kind": "blank"}, None
            return {"kind": "icon", "icon": "left" if tok == "prev" else "right",
                    "label": "%d/%d" % (page + 1, pages), "dim": not ok}, tok if ok else None
        if tok == "more":
            label = "%d/%d" % (page + 1, pages) if pages > 1 else next((lbl for sid, lbl, _ in SECTIONS if sid == self._section), "")
            return {"kind": "icon", "icon": "right", "label": label}, tok
        if tok in CHARS:
            return {"kind": "digit", "label": CHARS[tok][1]}, tok
        if tok == "del":
            return {"kind": "icon", "icon": "backspace", "label": "Delete"}, tok
        if tok == "done":
            return {"kind": "icon", "icon": "done", "label": "Done", "fill": True, "color": acc}, tok
        if tok == "page":
            n = len(self._layout["keypad"])
            return {"kind": "icon", "icon": "right", "label": "%d/%d" % (self._kpage % n + 1, n)}, tok
        return {"kind": "blank"}, None

    def _build(self):
        screen = self.screen()
        page = pages = 0
        apps = iter(())
        if screen == "apps":
            tools, page, pages = self._apps()
            apps = iter(tools)
        faces, actions = [], []
        for tok in self._grid(screen):
            f, a = self._face(tok, screen, apps, page, pages)
            faces.append(f)
            actions.append(a)
        return screen, faces, actions

    @Slot()
    def refresh(self):
        if self._deck is None or self._layout is None:
            return
        screen, faces, actions = self._build()
        self._screen, self._faces, self._actions = screen, faces, actions
        size = self._deck.key_image_format()["size"][0]
        changed = False
        for i, f in enumerate(faces):
            pressed = i == self._pressed
            sig = (repr(sorted(f.items())), pressed)
            if self._sent.get(i) == sig:
                continue
            img = K.render_key(f, size, pressed)
            try:
                self._deck.set_key_image(i, K.to_native(img, self._deck.key_image_format()))
            except Exception:
                self._close()
                return
            self._sent[i] = sig
            changed = True
        if self._deck.dial_count() and self._deck.is_touch():
            self._draw_strip(screen)
        if changed and self._shot:
            self.save_faces(self._shot)

    def _strip_zones(self, screen):
        tool = self._by_id.get(self._tool)
        zones = []
        for i, (head, turn, press) in enumerate(DIALS[screen]):
            if i == 0 and tool:
                head = tool["name"]
            zones.append({"head": head, "turn": DIAL_WORDS.get(turn, turn), "press": DIAL_WORDS.get(press, press),
                          "accent": self._accent() if i == 0 else None})
        return zones

    def _draw_strip(self, screen):
        zones = self._strip_zones(screen)
        sig = repr(zones)
        if sig == self._strip_sent:
            return
        d = self._deck
        img = K.render_strip(zones, d.TOUCHSCREEN_PIXEL_WIDTH, d.TOUCHSCREEN_PIXEL_HEIGHT)
        try:
            d.set_touchscreen_image(K.to_native(img, d.touchscreen_image_format()), 0, 0,
                                    d.TOUCHSCREEN_PIXEL_WIDTH, d.TOUCHSCREEN_PIXEL_HEIGHT)
            self._strip_sent = sig
        except Exception:
            pass

    def save_faces(self, path):
        """A picture of the deck as it is now (test hook and screenshots)."""
        if self._deck is None:
            return
        rows, cols = self._deck.key_layout()
        size = self._deck.key_image_format()["size"][0]
        imgs = [K.render_key(f, size, i == self._pressed) for i, f in enumerate(self._faces)]
        img = K.compose(imgs, cols, rows, size)
        d = self._deck
        if d.dial_count() and d.is_touch() and d.TOUCHSCREEN_PIXEL_WIDTH:   # the + : its touch strip below the keys
            strip = K.render_strip(self._strip_zones(self.screen()), d.TOUCHSCREEN_PIXEL_WIDTH, d.TOUCHSCREEN_PIXEL_HEIGHT)
            img = K.stack(img, strip)
        img.save(path)

    # ---------------------------------------------------------------- input
    def press(self, index):
        """A key went down and up (tests, and the Neo's touch points)."""
        self._on_key(index, True)
        self._on_key(index, False)

    @Slot(int, bool)
    def _on_key(self, k, down):
        if self._deck is None:
            return
        n = self._deck.key_count()
        if k >= n:   # Neo touch points
            if down:
                self._act(NEO_TOUCH_KEYS[(k - n) % len(NEO_TOUCH_KEYS)])
            return
        action = self._actions[k] if k < len(self._actions) else None
        if down:
            self._pressed, self._held_cleared = k, False
            self._pressed_action = action
            if action == "del":
                self._hold.start()
            elif action in ARROWS:
                self._act(action)
                self._repeat_wait.start()
            elif action is not None:
                self._act(action)
        else:
            self._hold.stop(); self._repeat_wait.stop(); self._repeat.stop()
            if action == "del" and self._pressed_action == "del" and not self._held_cleared:
                self._act("del")
            self._pressed = None
        self.refresh()

    def _repeat_tick(self):
        if self._pressed is not None and self._pressed_action in ARROWS:
            self._act(self._pressed_action)

    def _hold_clear(self):
        fi = self._focus_item()
        if role_of(fi) == "ip":
            fi.setProperty("text", "")
            self._held_cleared = True

    @Slot(int, str, int)
    def _on_dial(self, i, event, value):
        screen = self.screen()
        head, turn, press = DIALS[screen][i] if i < 4 else ("", "", "")
        if event == "TURN" and value and turn:
            steps = min(abs(value), 5)
            for _ in range(steps):
                if turn == "tabs":
                    self._act("section", -1 if value < 0 else 1)
                else:
                    a, b = {"prev/next": ("prev", "next"), "up/down": ("up", "down"), "left/right": ("left", "right")}[turn]
                    self._act(a if value < 0 else b)
        elif event == "PUSH" and value and press:
            self._act(press)
        self.refresh()

    @Slot(int)
    def _on_touch(self, x):
        d = self._deck
        if d is None or not d.TOUCHSCREEN_PIXEL_WIDTH:
            return
        zone = min(3, max(0, x * 4 // d.TOUCHSCREEN_PIXEL_WIDTH))
        self._on_dial(zone, "PUSH", 1)

    def _act(self, a, arg=None):
        if isinstance(a, tuple):
            a, arg = a
        screen = self.screen()
        fi = self._focus_item()
        role = role_of(fi)
        if a == "tool":
            self._editing = None
            self.request.emit("tool", arg)
            QTimer.singleShot(120, self.focusToolPane)
        elif a in ("home", "settings", "run", "stop", "keyboard"):
            if a in ("home", "settings"):
                self._editing = None
            self.request.emit(a, "")
        elif a == "section":
            if self._sections:
                i = self._sections.index(self._section) if self._section in self._sections else 0
                self.request.emit("section", self._sections[(i + (arg or 1)) % len(self._sections)])
        elif a in ("prev", "next"):
            _, page, pages = self._apps()
            page = page + (1 if a == "next" else -1)
            if 0 <= page < pages:
                self._page[self._section] = page
        elif a == "more":
            _, page, pages = self._apps()
            if page + 1 < pages:
                self._page[self._section] = page + 1
            elif len(self._sections) > 1:
                self._act("section", 1)
            else:
                self._page[self._section] = 0
        elif a in ARROWS:
            if screen == "list":
                if a in ("up", "down"):
                    self._send_key(Qt.Key.Key_Up if a == "up" else Qt.Key.Key_Down)
            else:
                self._move(a)
        elif a == "select":
            if screen == "list":
                self._send_key(Qt.Key.Key_Return, "\r")
            elif role == "text":
                self.request.emit("keyboard", "")
            elif role == "ip":
                self._begin_editing(fi)
            elif role == "dropdown":
                QMetaObject.invokeMethod(fi, "deckOpenList")
            elif fi is not None:
                self._send_key(Qt.Key.Key_Space, " ")
        elif a == "back":
            if screen == "list":
                self._send_key(Qt.Key.Key_Escape)
            elif screen == "keypad":
                self._editing = None
            else:
                self.request.emit("back", "")
        elif a in CHARS:
            key, text = CHARS[a]
            self._send_key(key, text)
        elif a == "del":
            if fi is not None and role == "ip" and self._has_selection(fi):
                fi.setProperty("cursorPosition", len(fi.property("text") or ""))   # deselect, keep the text
            self._send_key(Qt.Key.Key_Backspace)
        elif a == "done":
            self._editing = None
        elif a == "page":
            self._kpage += 1
        QTimer.singleShot(0, self.refresh)
        QTimer.singleShot(250, self.refresh)   # popups and sheets animate open
