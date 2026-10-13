"""GUI Mode settings popup: UI size (saved per user), Load to RAM, Switch to CLI Mode."""
import json
import os
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, Property, Signal, Slot

from . import toram

SCALE_MIN, SCALE_MAX = 0.75, 1.6   # design tokens ui-scale-min / ui-scale-max


def config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return Path(base) / "backpack" / "gui.json"


def _clamp_scale(v):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return 1.0
    return round(min(SCALE_MAX, max(SCALE_MIN, v)), 2)


class Settings(QObject):
    uiScaleChanged = Signal()
    ramChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._cfg = {}
        try:
            self._cfg = json.loads(config_path().read_text())
        except (OSError, ValueError):
            pass
        env = os.environ.get("BACKPACK_UI_SCALE")   # test hook
        self._scale = _clamp_scale(env if env else self._cfg.get("uiScale", 1.0))
        self._ram = toram.status()
        self._ram_busy = False
        self._ram_progress = 0
        self._ram_message = ""
        self._proc = None

    # ------------------------------------------------------------ UI size
    @Property(float, constant=True)
    def uiScaleMin(self):
        return SCALE_MIN

    @Property(float, constant=True)
    def uiScaleMax(self):
        return SCALE_MAX

    def _get_scale(self):
        return self._scale

    def _set_scale(self, v):
        v = _clamp_scale(v)
        if v == self._scale:
            return
        self._scale = v
        self.uiScaleChanged.emit()
        self._save("uiScale", v)

    uiScale = Property(float, _get_scale, _set_scale, notify=uiScaleChanged)

    def _save(self, key, value):
        self._cfg[key] = value
        try:   # ~/.config is on the persistence partition when there is one
            p = config_path()
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(self._cfg, indent=1) + "\n")
        except OSError:
            pass

    # ------------------------------------------------------------ Load to RAM
    @Property(bool, notify=ramChanged)
    def ramSupported(self):
        return self._ram["supported"]

    @Property(bool, notify=ramChanged)
    def inRam(self):
        return self._ram["inRam"]

    @Property(bool, notify=ramChanged)
    def ramBusy(self):
        return self._ram_busy

    @Property(int, notify=ramChanged)
    def ramProgress(self):
        return self._ram_progress

    @Property(str, notify=ramChanged)
    def ramMessage(self):
        return self._ram_message

    @Property(str, notify=ramChanged)
    def ramSummary(self):
        st = self._ram
        free = st["memAvailable"] / 2**30
        if not st["supported"]:
            return f"Not running from a Backpack live USB. {free:.1f} GB RAM free."
        size = st["size"] / 2**30
        if st["inRam"]:
            return f"The system runs from RAM. {free:.1f} GB RAM free."
        if st["memAvailable"] < st["size"] + st["headroom"]:
            return f"Needs {size + st['headroom'] / 2**30:.1f} GB free RAM; {free:.1f} GB free."
        return f"Copies the {size:.1f} GB system image into memory so you can unplug the USB stick. {free:.1f} GB RAM free."

    @Property(str, notify=ramChanged)
    def ramFacts(self):
        """Metadata strip for the sheet header, e.g. "RAM 7.6 GB FREE // FROM RAM"."""
        st = self._ram
        out = f"RAM {st['memAvailable'] / 2**30:.1f} GB FREE"
        return out + (" // FROM RAM" if st["inRam"] else "")

    @Property(bool, notify=ramChanged)
    def canLoadToRam(self):
        st = self._ram
        return (st["supported"] and not st["inRam"] and not self._ram_busy
                and st["memAvailable"] >= st["size"] + st["headroom"])

    @Slot()
    def refresh(self):
        self._ram = toram.status()
        self.ramChanged.emit()

    @Slot()
    def loadToRam(self):
        if self._ram_busy:
            return
        self._ram_busy, self._ram_progress, self._ram_message = True, 0, "Copying the system into RAM…"
        self.ramChanged.emit()
        p = QProcess(self)
        p.setProcessChannelMode(QProcess.MergedChannels)
        buf = {"s": ""}

        def _read():
            buf["s"] += bytes(p.readAllStandardOutput().data()).decode("utf-8", "replace")
            *lines, buf["s"] = buf["s"].split("\n")
            for line in lines:
                kind, _, msg = line.strip().partition(" ")
                if kind == "PROGRESS" and msg.isdigit():
                    self._ram_progress = int(msg)
                elif kind in ("DONE", "ERROR"):
                    self._ram_message = msg
                elif line.strip():   # e.g. sudo refusing
                    self._ram_message = line.strip()
            self.ramChanged.emit()

        def _done(code, _status):
            _read()
            self._proc = None
            self._ram_busy = False
            if code == 0:
                self._ram_progress = 100
            self.refresh()

        p.readyReadStandardOutput.connect(_read)
        p.finished.connect(_done)
        p.errorOccurred.connect(lambda e: e == QProcess.ProcessError.FailedToStart and _done(1, None))
        self._proc = p
        cmd = [sys.executable, "-m", "backpack_touch.toram", "run"]
        if os.geteuid() == 0:
            p.start(cmd[0], cmd[1:])
        else:
            p.start("sudo", ["-n"] + cmd)

    # ------------------------------------------------------------ CLI Mode
    @Slot()
    def switchToCli(self):
        # Stops LightDM and with it this sway session; tty1 has the live user's autologin.
        QProcess.startDetached("sh", ["-c",
            "sudo -n sh -c 'systemctl isolate multi-user.target && chvt 1'"])
