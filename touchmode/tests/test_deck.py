"""Stream Deck support, without a deck: the library's dummy transport stands in for USB.

Run from the repo root (CI does):
  QT_QPA_PLATFORM=offscreen BACKPACK_MANIFEST=manifest/tools.yaml PYTHONPATH=touchmode \
    python3 -m unittest discover -s touchmode/tests
"""
import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
os.environ.setdefault("BACKPACK_MANIFEST", str(Path(__file__).resolve().parents[2] / "manifest" / "tools.yaml"))

from PySide6.QtCore import QEventLoop, QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

app = QGuiApplication.instance() or QGuiApplication(sys.argv)

import backpack_touch.__main__ as M  # noqa: E402
from backpack_touch import deck as D, deckkeys as K, manifest  # noqa: E402
from backpack_touch.runner import Runner, System, Wifi  # noqa: E402
from backpack_touch.settings import Settings  # noqa: E402
from backpack_touch.sysmon import SysMonitor  # noqa: E402

KEYS = {"6": 6, "8": 8, "15": 15, "32": 32}


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


class Layouts(unittest.TestCase):
    def test_every_screen_fills_its_deck(self):
        for name, layout in D.LAYOUTS.items():
            for screen, grid in layout.items():
                pages = grid if screen == "keypad" else [grid]
                for g in pages:
                    toks = [t for row in g for t in row.split()]
                    self.assertEqual(len(toks), KEYS[name], (name, screen, g))

    def test_layout_choice(self):
        self.assertEqual(D.layout_for(6), "6")
        self.assertEqual(D.layout_for(8), "8")
        self.assertEqual(D.layout_for(15), "15")
        self.assertEqual(D.layout_for(32), "32")

    def test_keypad_has_every_character(self):
        for name, layout in D.LAYOUTS.items():
            toks = {t for page in layout["keypad"] for row in page for t in row.split()}
            self.assertTrue(set(D.CHARS) | {"del", "done"} <= toks, name)

    def test_faces_render(self):
        for face in ({"kind": "app", "label": "Angry IP Scanner", "sub": "Discovery", "color": K.ACID},
                     {"kind": "icon", "icon": "settings", "label": "Settings"},
                     {"kind": "text", "label": "Select", "fill": True},
                     {"kind": "digit", "label": "7"},
                     {"kind": "tab", "label": "Network", "sub": "SEC.01 // 26"}):
            for size in (72, 80, 96, 120):
                img = K.render_key(face, size)
                self.assertEqual((img.width(), img.height()), (size, size))
                fmt = {"size": (size, size), "format": "JPEG", "flip": (True, True), "rotation": 90}
                self.assertTrue(K.to_native(img, fmt).startswith(b"\xff\xd8"))


class Driving(unittest.TestCase):
    """The launcher with a dummy 15-key deck: open a tool, move, type an address, use a dropdown."""

    @classmethod
    def setUpClass(cls):
        os.environ["BACKPACK_DECK"] = "dummy-15"
        tools = manifest.load()
        cls.engine = QQmlApplicationEngine()
        ctx = cls.engine.rootContext()
        cls.runner, cls.system = Runner(tools), System()
        cls.deck = D.Deck(tools, cls.runner, cls.system)
        props = dict(manifest=M.Manifest(tools), runner=cls.runner, system=cls.system, wifi=Wifi(), settings=Settings(),
                     deck=cls.deck, sysmon=SysMonitor(), demoTool="", demoWifi=False, demoSettings=False,
                     demoSection="", demoMonitor=False, demoAsk="", demoWifiSelect="")
        cls.props = props   # the context objects must outlive this method
        for k, v in props.items():
            ctx.setContextProperty(k, v)
        cls.engine.load(QUrl.fromLocalFile(str(Path(M.__file__).parent / "qml" / "Main.qml")))
        cls.win = cls.engine.rootObjects()[0]
        cls.win.setVisibility(QQuickWindow.Windowed)
        cls.win.resize(1280, 800)
        cls.deck.attach(cls.win)
        wait(800)

    @classmethod
    def tearDownClass(cls):
        cls.deck.stop()

    def press(self, tok):
        acts = self.deck._actions
        for i, a in enumerate(acts):
            if a == tok or (isinstance(a, tuple) and ":".join(a) == tok):
                self.deck.press(i)
                wait(250)
                return
        self.fail("no %r key on the %s screen: %s" % (tok, self.deck.screen(), acts))

    def focus(self):
        return self.win.activeFocusItem()

    def test_flow(self):
        d = self.deck
        self.assertTrue(d.connected)
        self.press("home")
        self.assertEqual(d.screen(), "apps")

        # an app key opens the tool and focuses its first control
        self.press("tool:nmap")
        wait(300)
        self.assertEqual(d._tool, "nmap")   # Main.qml told the deck which tool is open
        self.assertEqual(d.screen(), "nav")
        self.assertIsNotNone(self.focus())

        # down to the target field: the keypad; digits replace the default, then Done
        for _ in range(6):
            if D.role_of(self.focus()) == "ip":
                break
            self.press("down")
        self.assertEqual(d.screen(), "keypad")
        for t in ["1", "0", "dot", "0", "dot", "0", "dot", "0", "slash", "8"]:
            self.press(t)
        self.assertEqual(self.focus().property("text"), "10.0.0.0/8")
        self.press("del")
        self.assertEqual(self.focus().property("text"), "10.0.0.0/")
        self.press("done")
        self.assertEqual(d.screen(), "nav")

        # a dropdown opens when focus lands on it; down + select picks the next entry
        self.press("home")
        self.press("tool:arp-scan")
        wait(400)
        self.assertEqual(d.screen(), "list")
        self.press("down")
        self.press("select")
        wait(300)
        self.assertEqual(d.screen(), "nav")
        self.assertEqual(D.role_of(self.focus()), "dropdown")

        # Settings opens the sheet; Back closes it; Home returns to the apps
        self.press("settings")
        wait(300)
        self.assertTrue(self.win.property("settingsOpen"))
        self.press("back")
        wait(300)
        self.assertFalse(self.win.property("settingsOpen"))
        self.press("home")
        self.assertEqual(d.screen(), "apps")
        self.assertEqual(self.win.property("section"), "network")
        self.press("section")
        wait(200)
        self.assertEqual(self.win.property("section"), "data")


if __name__ == "__main__":
    unittest.main()
