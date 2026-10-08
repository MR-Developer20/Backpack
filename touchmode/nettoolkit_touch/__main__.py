import os
import sys
from pathlib import Path

from PySide6.QtCore import QObject, Property, QTimer, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow  # noqa: F401  (makes rootObjects() return QQuickWindow)

from . import manifest
from .runner import Runner, System


class Manifest(QObject):
    def __init__(self, tools):
        super().__init__()
        self._tools = tools
        self._cats = manifest.categories(tools)

    @Property("QVariantList", constant=True)
    def tools(self):
        return self._tools

    @Property("QVariantList", constant=True)
    def categories(self):
        return self._cats


def demo_tool():
    """nettoolkit.demo[=tool-id] on the kernel command line, or NETTOOLKIT_DEMO env: auto-open a tool."""
    val = os.environ.get("NETTOOLKIT_DEMO")
    if val is None:
        try:
            for p in Path("/proc/cmdline").read_text().split():
                if p.startswith("nettoolkit.demo"):
                    val = p.partition("=")[2] or "nmap"
        except OSError:
            pass
    return val


def main():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("NetToolkit Touch")
    tools = manifest.load()
    engine = QQmlApplicationEngine()
    ctx = engine.rootContext()
    mf, runner, system = Manifest(tools), Runner(tools), System()
    ctx.setContextProperty("manifest", mf)
    ctx.setContextProperty("runner", runner)
    ctx.setContextProperty("system", system)
    ctx.setContextProperty("demoTool", demo_tool() or "")
    app.aboutToQuit.connect(runner.stop)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).parent / "qml" / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    shot = os.environ.get("NETTOOLKIT_SCREENSHOT")
    if shot:  # test hook: grab the window after the demo has run, then exit
        root = engine.rootObjects()[0]
        root.setVisibility(QQuickWindow.Windowed)
        root.resize(1280, 800)
        def grab():
            engine.rootObjects()[0].grabWindow().save(shot)
            app.quit()
        QTimer.singleShot(int(os.environ.get("NETTOOLKIT_SCREENSHOT_DELAY", "6000")), grab)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
