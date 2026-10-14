"""GUI Mode settings popup: UI size and display rotation (saved per user), Load to RAM, Switch to CLI Mode."""
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, Property, Signal, Slot

from . import toram

SCALE_MIN, SCALE_MAX = 0.5, 1.6   # design token ui-scale-max; below 0.75 (ui-scale-min) at Marc's request
# sway output transforms offered by the Orientation dropdown; relative to the panel's own
# orientation (a GPD Pocket 3's panel is natively portrait, so "90" makes it landscape there)
ROTATIONS = [("normal", "Normal"), ("90", "Rotate 90°"), ("180", "Rotate 180°"), ("270", "Rotate 270°")]


def config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return Path(base) / "backpack" / "gui.json"


def _clamp_scale(v):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return 1.0
    return round(min(SCALE_MAX, max(SCALE_MIN, v)), 2)


def sway_output():
    """Name of the output the launcher is on (the focused one, else the first), or "" outside sway."""
    try:
        outs = json.loads(subprocess.run(["swaymsg", "-t", "get_outputs", "-r"], capture_output=True,
                                         text=True, timeout=2).stdout or "[]")
    except (OSError, ValueError, subprocess.SubprocessError):
        return ""
    outs = [o for o in outs if o.get("active", True)]
    for o in outs:
        if o.get("focused"):
            return o.get("name", "")
    return outs[0].get("name", "") if outs else ""


def rotation_commands(output, rotation):
    """The swaymsg lines that turn `output` to `rotation` and keep touch and pen input on it
    (map_to_output makes wlroots apply the same transform to touch coordinates)."""
    out = shlex.quote(output) if output else "<output>"
    return [f"swaymsg output {out} transform {rotation}",
            f"swaymsg input type:touch map_to_output {out}",
            f"swaymsg input type:tablet_tool map_to_output {out}"]


class Settings(QObject):
    uiScaleChanged = Signal()
    rotationChanged = Signal()
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
        self._rotation = self._cfg.get("rotation", "normal")
        if self._rotation not in dict(ROTATIONS):
            self._rotation = "normal"
        self._output = sway_output()
        if self._rotation != "normal":   # restore the saved orientation when the session starts
            self._apply_rotation()
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

    # ------------------------------------------------------------ display orientation
    @Property("QVariantList", constant=True)
    def rotations(self):
        """[{value, label, command}] for the Orientation dropdown; command = what choosing it runs."""
        return [{"value": v, "label": l, "command": rotation_commands(self._output, v)[0]} for v, l in ROTATIONS]

    def _get_rotation(self):
        return self._rotation

    def _set_rotation(self, v):
        if v not in dict(ROTATIONS) or v == self._rotation:
            return
        self._rotation = v
        self.rotationChanged.emit()
        self._save("rotation", v)
        self._apply_rotation()

    rotation = Property(str, _get_rotation, _set_rotation, notify=rotationChanged)

    def _apply_rotation(self):
        if not self._output:
            self._output = sway_output()
        if self._output:
            QProcess.startDetached("sh", ["-c", "; ".join(rotation_commands(self._output, self._rotation))])

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

    @Property(str, constant=True)
    def ramCommand(self):
        """The command the Load to RAM button runs, shown under its label."""
        cmd = f"{os.path.basename(sys.executable)} -m backpack_touch.toram run"
        return cmd if os.geteuid() == 0 else "sudo -n " + cmd

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
    @Property(str, constant=True)
    def cliCommand(self):
        """Shown under Switch to CLI Mode and executed as shown. backpack-cli-mode (in the
        backpack-touch deb) is `systemctl isolate multi-user.target && chvt 1`: it stops
        LightDM and with it this sway session; tty1 has the live user's autologin."""
        cmd = "backpack-cli-mode"
        return cmd if os.geteuid() == 0 else "sudo -n " + cmd

    @Slot()
    def switchToCli(self):
        QProcess.startDetached("sh", ["-c", self.cliCommand])
