"""App window frames for GUI Mode (sway).

Every app window (a GUI tool such as Angry IP Scanner, a tty tool's foot, an Extra app) opens
maximized as a floating frame: one floating sway container holding a WindowBar.qml window on top and
the app below. Sway draws the bar's own 5px title strip above it, which drags the whole frame
(sway moves the floating ancestor of a titlebar that is pressed). The bar has Close, Maximize
(toggle maximized / the app's own size) and Split (left or right half; top or bottom in portrait).

Sway is followed through `swaymsg -t subscribe` (window + output events) and driven with
`swaymsg` commands by container id. The bars are windows of this process, so a new window with our
pid is the bar asked for last: bars are created one at a time.
"""
import json
import os
import subprocess
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, QTimer, QUrl, Slot
from PySide6.QtQml import QQmlComponent

from .runner import SPLIT_APP_ID, TERM_APP_ID

# Backpack's own terminals are not framed: the Terminal button's is fullscreen (sway.config), the
# Split button's tiles beside the launcher
UNFRAMED_APP_IDS = {TERM_APP_ID, SPLIT_APP_ID}
# apps that open at their own size instead of maximized (a fixed-size game)
OWN_SIZE_APPS = {"ltris"}
# the launcher's window (its bars share its app_id), marked so strays can be moved next to it
LAUNCHER = '[app_id="^backpack-touch$" title="^Backpack Live$"]'
LAUNCHER_MARK = "_bp_launcher"
DEBUG = bool(os.environ.get("BACKPACK_WINDOWS_DEBUG"))


def swaymsg(*commands):
    """Run sway commands (joined with `;`); returns the parsed reply list, or [] when sway is not there."""
    line = "; ".join(commands)
    try:
        out = subprocess.run(["swaymsg", line], capture_output=True, text=True, timeout=3).stdout
        replies = json.loads(out or "[]")
    except Exception:
        return []
    if DEBUG or not all(r.get("success") for r in replies):
        print(f"backpack windows: swaymsg {line} -> {[r.get('error', 'ok') for r in replies]}", flush=True)
    return replies


def sway_get(kind):
    try:
        out = subprocess.run(["swaymsg", "-t", kind], capture_output=True, text=True, timeout=3).stdout
        return json.loads(out)
    except Exception:
        return None


def find_parent(node, con_id, parent=None):
    """The container that holds con_id (its frame), or None."""
    if node.get("id") == con_id:
        return parent
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        found = find_parent(child, con_id, node)
        if found is not None:
            return found
    return None


def find_ancestors(node, con_id):
    """The ids of the containers above con_id, innermost first ([] when not found)."""
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        if child.get("id") == con_id:
            return [node.get("id")]
        found = find_ancestors(child, con_id)
        if found:
            return found + [node.get("id")]
    return []


def find_node(node, con_id):
    if node.get("id") == con_id:
        return node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        found = find_node(child, con_id)
        if found is not None:
            return found
    return None


def app_key(con):
    """The app's id for matching: Wayland app_id, else the X11 class, lower-case."""
    return (con.get("app_id") or (con.get("window_properties") or {}).get("class") or "").lower()


def split_rect(ws, side):
    """The half of workspace rect `ws` for side "a" (left, or top in portrait) or "b"."""
    x, y, w, h = ws["x"], ws["y"], ws["width"], ws["height"]
    if h > w:   # portrait: top / bottom
        top = h // 2
        return (x, y, w, top) if side == "a" else (x, y + top, w, h - top)
    left = w // 2
    return (x, y, left, h) if side == "a" else (x + left, y, w - left, h)


def own_size_rect(ws, natural, bar_h):
    """The app at its own size (plus the bar), at most 90% of the workspace, centred."""
    nw, nh = natural
    w = min(max(nw, 320), int(ws["width"] * 0.9))
    h = min(max(nh, 200) + bar_h, int(ws["height"] * 0.9))
    return (ws["x"] + (ws["width"] - w) // 2, ws["y"] + (ws["height"] - h) // 2, w, h)


def other_side(side):
    return "b" if side == "a" else "a"


def choose_split(state, others):
    """Where Split sends a frame: its other side if it is split already, else the free side when
    one other frame holds a side; None = ask (no side taken, or both)."""
    if state in ("a", "b"):
        return other_side(state)
    taken = {s for s in others if s in ("a", "b")}
    if len(taken) == 1:
        return other_side(taken.pop())
    return None


class Frame:
    def __init__(self, app_con, pid, natural, own_size):
        self.app = app_con         # the app's container id
        self.pid = pid
        self.natural = natural     # (w, h) the app asked for
        self.state = "own" if own_size else "max"   # "max" | "own" | "a" | "b"
        self.bar = None            # WindowBar.qml window
        self.bar_con = None        # its sway container id
        self.frame_con = None      # the floating container holding both


class Windows(QObject):
    """Frames app windows; the bars call back through the context property `windows`."""

    def __init__(self, engine, parent=None):
        super().__init__(parent)
        self._engine = engine
        self._component = QQmlComponent(engine, QUrl.fromLocalFile(str(Path(__file__).parent / "qml" / "WindowBar.qml")))
        self._frames = {}          # app container id -> Frame
        self._queue = []           # frames waiting for a bar (bars are made one at a time)
        self._pending = None       # the frame whose bar has been created but not seen by sway yet
        self._buf = b""
        self._proc = None
        self._deco = 5             # sway's title strip above the bar, measured once a bar is framed

    def start(self):
        if not os.environ.get("SWAYSOCK"):
            return
        p = QProcess(self)
        p.readyReadStandardOutput.connect(self._read)
        p.finished.connect(lambda *_: QTimer.singleShot(2000, self.start))   # sway restarted the IPC
        p.start("swaymsg", ["-m", "-r", "-t", "subscribe", '["window","output"]'])
        self._proc = p

    def _read(self):
        self._buf += bytes(self._proc.readAllStandardOutput().data())
        while b"\n" in self._buf:
            line, self._buf = self._buf.split(b"\n", 1)
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            try:
                self._event(ev)
            except Exception as e:   # one odd event must not stop the frames
                print(f"backpack windows: {e}", flush=True)

    def _event(self, ev):
        change = ev.get("change")
        con = ev.get("container")
        if con is None:   # an output event (a monitor or its rotation changed)
            QTimer.singleShot(300, self._apply_all)
            return
        cid = con.get("id")
        if change == "new":
            self._new(con)
        elif change == "close":
            self._closed(cid)
        elif change == "focus":
            for f in self._frames.values():
                if f.bar is not None:
                    f.bar.setProperty("active", f.app == cid or f.bar_con == cid)
        elif change == "title" and cid in self._frames and self._frames[cid].bar is not None:
            self._frames[cid].bar.setProperty("appTitle", con.get("name") or "")

    def _out_of_frames(self, cid):
        """Sway opens a new window next to the focused one, and that can be inside a frame (an app's
        dialog, or anything opened while an app has focus). Move it out, tiled next to the launcher."""
        frames = {f.frame_con for f in self._frames.values()}
        if not frames.intersection(find_ancestors(sway_get("get_tree") or {}, cid)):
            return False
        swaymsg(f"{LAUNCHER} mark --add {LAUNCHER_MARK}", f"[con_id={cid}] move window to mark {LAUNCHER_MARK}")
        return True

    def _new(self, con):
        cid, pid = con.get("id"), con.get("pid")
        if con.get("type") != "con":
            return
        if pid == os.getpid():   # a bar we made (or the launcher's own window at start)
            if self._pending is not None:
                self._out_of_frames(cid)
                self._assemble(self._pending, cid)
                self._pending = None
            self._next_bar()
            return
        moved = self._out_of_frames(cid)
        if con.get("app_id") == SPLIT_APP_ID:
            # tiled beside the launcher (System.toggleSplit set the direction). Not a sway.config rule:
            # `floating disable` on a window that opened inside a frame would tile the whole frame
            swaymsg(f"[con_id={cid}] floating disable")
            return
        if con.get("app_id") in UNFRAMED_APP_IDS:
            return
        geo = con.get("geometry") or {}
        if pid and any(f.pid == pid for f in self._frames.values()):
            # another window of a framed app: a dialog; float it centred over its app at its own size,
            # or at 60% of the screen when it opened inside the frame (its size is then the frame's)
            ws = self._workspace() or {"width": 1280, "height": 800}
            w = int(ws["width"] * 0.6) if moved else min(geo.get("width") or 480, ws["width"])
            h = int(ws["height"] * 0.6) if moved else min(geo.get("height") or 320, ws["height"])
            place = (f"[con_id={cid}] floating enable, border pixel 2, resize set width {w} px height {h} px, "
                     "move position center")
            swaymsg(place)
            QTimer.singleShot(400, lambda: swaymsg(place))   # again once it has drawn at its first size
            return
        f = Frame(cid, pid, (geo.get("width", 0), geo.get("height", 0)), app_key(con) in OWN_SIZE_APPS)
        self._frames[cid] = f
        # float it at once where the frame will be, so it never flashes up tiled beside the launcher
        ws = self._workspace()
        if ws:
            x, y, w, h = self._rect(f, ws)
            swaymsg(f"[con_id={cid}] floating enable, border none, resize set width {w} px height {h} px",
                    f"[con_id={cid}] move position {x - ws['x']} {y - ws['y']}")
        self._queue.append(f)
        self._next_bar()

    def _next_bar(self):
        while self._pending is None and self._queue:
            f = self._queue.pop(0)
            if f.app not in self._frames:   # closed before its bar came
                continue
            bar = self._component.create()
            if bar is None:
                print("backpack windows: " + self._component.errorString(), flush=True)
                return
            bar.setProperty("appTitle", self._title(f.app))
            bar.closeRequested.connect(lambda f=f: self.close(f))
            bar.maximizeRequested.connect(lambda f=f: self.toggle_maximize(f))
            bar.splitRequested.connect(lambda f=f: self.split(f))
            bar.sideChosen.connect(lambda side, f=f: self.place(f, side))
            f.bar = bar
            self._pending = f
            bar.show()

    def _assemble(self, f, bar_con):
        """Put the bar above the app in one container, float it, give the bar its 5px strip."""
        f.bar_con = bar_con
        mark = f"_bp_frame_{f.app}"
        swaymsg(f"[con_id={f.app}] mark --add {mark}",
                f"[con_id={f.app}] split vertical",
                f"[con_id={bar_con}] floating disable",   # it opened floating (sway.config), like every window
                f"[con_id={bar_con}] move window to mark {mark}",
                f"[con_id={bar_con}] move up",
                f"[con_id={f.app}] unmark {mark}",
                f"[con_id={bar_con}] border normal 0, title_format \" \"",
                f"[con_id={f.app}] border none")
        tree = sway_get("get_tree") or {}
        parent = find_parent(tree, f.app)
        if parent is None or parent.get("type") != "floating_con":
            return
        f.frame_con = parent["id"]
        bar_node = find_node(tree, bar_con) or {}
        self._deco = (bar_node.get("deco_rect") or {}).get("height") or self._deco
        self._apply(f)
        swaymsg(f"[con_id={f.app}] focus")

    def _closed(self, cid):
        f = self._frames.pop(cid, None)
        if f is not None:
            if f.bar is not None:
                f.bar.close()
                f.bar.deleteLater()
            return
        for f in list(self._frames.values()):
            if f.bar_con == cid:   # its bar went away on its own: leave the app as it is
                f.bar, f.bar_con = None, None

    def _workspace(self):
        for ws in sway_get("get_workspaces") or []:
            if ws.get("focused"):
                return ws["rect"]
        return None

    def _title(self, cid):
        node = find_node(sway_get("get_tree") or {}, cid) or {}
        return node.get("name") or app_key(node)

    def _bar_h(self, f):
        return (int(f.bar.property("contentH")) if f.bar is not None else 64) + self._deco

    def _rect(self, f, ws):
        if f.state in ("a", "b"):
            return split_rect(ws, f.state)
        if f.state == "own":
            return own_size_rect(ws, f.natural, self._bar_h(f))
        return ws["x"], ws["y"], ws["width"], ws["height"]

    def _apply(self, f, ws=None):
        ws = ws or self._workspace()
        if not ws or f.frame_con is None:
            return
        x, y, w, h = self._rect(f, ws)
        swaymsg(f"[con_id={f.frame_con}] resize set width {w} px height {h} px",
                f"[con_id={f.frame_con}] move position {x - ws['x']} {y - ws['y']}",
                f"[con_id={f.bar_con}] resize set height {self._bar_h(f)} px")
        f.bar.setProperty("maximized", f.state == "max")
        f.bar.setProperty("side", f.state if f.state in ("a", "b") else "")
        f.bar.setProperty("portrait", ws["height"] > ws["width"])
        f.bar.setProperty("asking", False)

    def _apply_all(self):
        ws = self._workspace()
        for f in self._frames.values():
            self._apply(f, ws)

    # the bar's buttons

    def close(self, f):
        swaymsg(f"[con_id={f.app}] kill")

    def _frame_of(self, bar):
        return next((f for f in self._frames.values() if f.bar is bar), None)

    def toggle_maximize(self, f):
        f.state = "own" if f.state == "max" else "max"
        self._apply(f)

    def split(self, f):
        side = choose_split(f.state, [g.state for g in self._frames.values() if g is not f])
        if side is None:
            ws = self._workspace()
            f.bar.setProperty("portrait", bool(ws) and ws["height"] > ws["width"])
            f.bar.setProperty("asking", not f.bar.property("asking"))
            return
        self.place(f, side)

    def place(self, f, side):
        f.state = side
        self._apply(f)
        swaymsg(f"[con_id={f.app}] focus")

    @Slot(QObject)
    def refit(self, bar):   # the UI size slider changed the bar's height
        f = self._frame_of(bar)
        if f is not None:
            self._apply(f)
