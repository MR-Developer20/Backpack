"""Run manifest commands and stream their output to QML; session controls (split, keyboard, Wi-Fi)."""
import os
import shlex
import subprocess
from PySide6.QtCore import QObject, QProcess, QTimer, Property, Signal, Slot

from . import manifest

TERMINAL = os.environ.get("BACKPACK_TERMINAL", "foot")
SPLIT_APP_ID = "backpack-split"   # the one foot window the Split button owns
TERM_APP_ID = "backpack-term"     # Terminal button: fullscreen foot (sway rule in sway.config)
KEYBOARD_PROC = "wvkbd-mobintl"


class Runner(QObject):
    output = Signal(str)
    started = Signal(str)
    finished = Signal(int)
    runningChanged = Signal()
    error = Signal(str)

    def __init__(self, tools, parent=None):
        super().__init__(parent)
        self._tools = {t["id"]: t for t in tools}
        self._proc = None

    @Property(bool, notify=runningChanged)
    def running(self):
        return self._proc is not None and self._proc.state() != QProcess.NotRunning

    @Slot(str, int, "QVariantMap", result=str)
    def commandLine(self, tool_id, cmd_index, values):
        cmd = self._tools[tool_id]["commands"][cmd_index]
        argv, err = manifest.build_argv(cmd, dict(values))
        return err and f"error: {err}" or manifest.display(argv)

    @Slot(str, int, "QVariantMap")
    def run(self, tool_id, cmd_index, values):
        tool = self._tools[tool_id]
        cmd = tool["commands"][cmd_index]
        argv, err = manifest.build_argv(cmd, dict(values))
        if err:
            self.error.emit(err)
            return
        if tool["gui"]:
            # like openTerminal: leave fullscreen first or the app opens behind the launcher
            QProcess.startDetached("sh", ["-c", "swaymsg fullscreen disable; exec " + shlex.join(argv)])
            self.output.emit(f"launched {manifest.display(argv)}\n")
            return
        if cmd["tty"]:
            script = manifest.display(argv) + '; echo; echo "[press Enter to close]"; read _'
            # like openTerminal/toggleSplit: leave fullscreen first or foot opens behind the launcher
            QProcess.startDetached("sh", ["-c", "swaymsg fullscreen disable; exec "
                                          + shlex.join([TERMINAL, "sh", "-c", script])])
            self.output.emit(f"opened in terminal: {manifest.display(argv)}\n")
            return
        self.stop()
        p = QProcess(self)
        p.setProcessChannelMode(QProcess.MergedChannels)
        p.readyReadStandardOutput.connect(lambda: self.output.emit(
            bytes(p.readAllStandardOutput().data()).decode("utf-8", "replace")))
        p.finished.connect(self._finished)

        def _error(e, prog=argv[0]):
            self.error.emit(f"{prog}: {e.name if hasattr(e, 'name') else e}")
            if e == QProcess.ProcessError.FailedToStart:   # no finished() follows: release the Run button
                self._proc = None
                self.runningChanged.emit()
        p.errorOccurred.connect(_error)
        p.setProgram(argv[0])
        p.setArguments(argv[1:])
        self._proc = p
        self.started.emit(manifest.display(argv))
        p.start()
        self.runningChanged.emit()

    @Slot(int, "QProcess::ExitStatus")
    def _finished(self, code, status):
        self.finished.emit(code)
        self._proc = None
        self.runningChanged.emit()

    @Slot()
    def stop(self):
        if self._proc is not None and self._proc.state() != QProcess.NotRunning:
            self._proc.terminate()
            if not self._proc.waitForFinished(1500):
                self._proc.kill()
                self._proc.waitForFinished(1000)


def _sway_tree_has_app_id(app_id):
    try:
        out = subprocess.run(["swaymsg", "-t", "get_tree"], capture_output=True, text=True, timeout=2).stdout
        return f'"app_id": "{app_id}"' in out
    except Exception:
        return False


def _pkill_signal(proc_name, sig):
    try:
        subprocess.run(["pkill", f"-{sig}", "-x", proc_name], timeout=2)
    except Exception:
        pass


class System(QObject):
    """Terminal / split / keyboard / power buttons. Split state is polled from the sway tree so the
    button stays correct even if the user closes the terminal with `exit`."""
    splitActiveChanged = Signal()
    keyboardVisibleChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._split = False
        self._kbd = False
        self._poll = QTimer(self)
        self._poll.setInterval(1500)
        self._poll.timeout.connect(self._refresh)
        self._poll.start()
        QTimer.singleShot(300, self._refresh)

    def _refresh(self):
        s = _sway_tree_has_app_id(SPLIT_APP_ID)
        if s != self._split:
            self._split = s
            self.splitActiveChanged.emit()

    @Property(bool, notify=splitActiveChanged)
    def splitActive(self):
        return self._split

    @Property(bool, notify=keyboardVisibleChanged)
    def keyboardVisible(self):
        return self._kbd

    @Slot()
    def openTerminal(self):
        # fullscreen foot over everything (sway for_window rule); `exit` returns to the launcher
        QProcess.startDetached("sh", ["-c",
            f"swaymsg fullscreen disable; swaymsg exec '{TERMINAL} --app-id {TERM_APP_ID}'"])

    @Slot(bool)
    def toggleSplit(self, portrait):
        if self._split:
            QProcess.startDetached("swaymsg", [f"[app_id={SPLIT_APP_ID}] kill"])
            self._split = False
            self.splitActiveChanged.emit()
            return
        direction = "splitv" if portrait else "splith"   # portrait: terminal below; landscape: beside
        QProcess.startDetached("sh", ["-c",
            f"swaymsg fullscreen disable; swaymsg {direction}; swaymsg exec '{TERMINAL} --app-id {SPLIT_APP_ID}'"])
        QTimer.singleShot(800, self._refresh)

    @Slot()
    def showKeyboard(self):
        _pkill_signal(KEYBOARD_PROC, "USR2")
        self._kbd = True
        self.keyboardVisibleChanged.emit()

    @Slot()
    def hideKeyboard(self):
        _pkill_signal(KEYBOARD_PROC, "USR1")
        self._kbd = False
        self.keyboardVisibleChanged.emit()

    @Slot()
    def toggleKeyboard(self):
        self.hideKeyboard() if self._kbd else self.showKeyboard()

    @Slot()
    def poweroff(self):
        QProcess.startDetached("sh", ["-c", "systemctl poweroff || sudo -n systemctl poweroff"])

    @Slot()
    def reboot(self):
        QProcess.startDetached("sh", ["-c", "systemctl reboot || sudo -n systemctl reboot"])


def _nmcli_fields(line):
    """Split one `nmcli -t` line into fields; nmcli escapes ':' and '\\' inside values as '\\:' and '\\\\'."""
    fields, cur, i = [], [], 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line):
            cur.append(line[i + 1])
            i += 2
            continue
        if c == ":":
            fields.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    fields.append("".join(cur))
    return fields


class Wifi(QObject):
    """Wi-Fi discovery/connection via NetworkManager (nmcli). The live user is in `netdev`."""
    networksChanged = Signal()
    statusChanged = Signal()
    busyChanged = Signal()
    message = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._networks = []
        self._status = "Checking Wi-Fi…"
        self._device = ""
        self._busy = False
        self._procs = []

    @Property("QVariantList", notify=networksChanged)
    def networks(self):
        return self._networks

    @Property(str, notify=statusChanged)
    def status(self):
        return self._status

    @Property(bool, notify=busyChanged)
    def busy(self):
        return self._busy

    @Property(bool, notify=statusChanged)
    def hasDevice(self):
        return bool(self._device)

    def _run(self, args, done):
        p = QProcess(self)
        p.setProcessChannelMode(QProcess.MergedChannels)
        self._procs.append(p)
        def _fin(code, _status):
            if p not in self._procs:   # errorOccurred (e.g. Crashed) may precede finished
                return
            out = bytes(p.readAllStandardOutput().data()).decode("utf-8", "replace")
            self._procs.remove(p)
            done(code, out)
        p.finished.connect(_fin)
        # FailedToStart never gets a finished(); any other error (e.g. Crashed) does, with the real output
        p.errorOccurred.connect(lambda e: e == QProcess.ProcessError.FailedToStart and _fin(-1, "nmcli not available"))
        p.start("nmcli", args)

    def _set_busy(self, b):
        self._busy = b
        self.busyChanged.emit()

    def _set_status(self, s):
        self._status = s
        self.statusChanged.emit()

    @Slot()
    def refreshStatus(self):
        def done_dev(code, out):
            dev = ""
            state = ""
            for line in out.splitlines():
                parts = _nmcli_fields(line)
                if len(parts) >= 3 and parts[1] == "wifi":
                    dev, state = parts[0], parts[2]
                    break
            self._device = dev
            if not dev:
                self._set_status("No Wi-Fi device found (monitor mode, or missing driver/firmware)")
                return
            if state == "unavailable":
                self._set_status(f"{dev} unavailable: Wi-Fi is switched off or blocked (rfkill)")
                return
            if state == "unmanaged":
                self._set_status(f"{dev} is not managed by NetworkManager (monitor mode? run airmon-ng stop)")
                return
            def done_act(code2, out2):
                for line in out2.splitlines():
                    p = _nmcli_fields(line)
                    if len(p) >= 3 and p[2] == dev:
                        self._set_status(f"Connected to {p[0]} on {dev}")
                        return
                self._set_status(f"Not connected ({dev}: {state})")
            self._run(["-t", "-f", "NAME,TYPE,DEVICE", "con", "show", "--active"], done_act)
        self._run(["-t", "-f", "DEVICE,TYPE,STATE", "dev"], done_dev)

    @Slot()
    def scan(self):
        if self._busy:
            return
        self._set_busy(True)
        def done(code, out):
            self.refreshStatus()
            best = {}
            for line in out.splitlines():
                # IN-USE:SSID:SIGNAL:SECURITY  (SSID may contain escaped ":" and "\\")
                parts = _nmcli_fields(line)
                if len(parts) < 4:
                    continue
                inuse, ssid, signal_, sec = parts[0], parts[1], parts[2], parts[3]
                if not ssid:
                    continue
                try:
                    sig = int(signal_)
                except ValueError:
                    sig = 0
                cur = best.get(ssid)
                if cur is None or sig > cur["signal"]:
                    best[ssid] = {"ssid": ssid, "signal": sig, "security": sec.strip() or "open",
                                  "secured": bool(sec.strip()) and sec.strip() != "--", "inUse": inuse.strip() == "*"}
            self._networks = sorted(best.values(), key=lambda n: (-int(n["inUse"]), -n["signal"]))
            self.networksChanged.emit()
            self._set_busy(False)
            if code != 0 and not self._networks:
                self.message.emit(out.strip().splitlines()[-1] if out.strip() else "scan failed")
        def do_scan(*_):
            self._run(["-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"], done)
        def done_radio(code, out):
            # A soft-blocked/disabled radio makes the adapter "unavailable" and the list empty.
            if out.strip() == "disabled":
                self._run(["radio", "wifi", "on"], lambda *_: QTimer.singleShot(2000, do_scan))
            else:
                do_scan()
        self._run(["radio", "wifi"], done_radio)

    @Slot(str, str, str)
    def connectTo(self, ssid, password, security=""):
        if self._busy:
            return
        if "802.1X" in security:
            # `nmcli dev wifi connect` cannot build an 802.1X (WPA-Enterprise) profile.
            self.message.emit("Enterprise (802.1X) networks need a profile made in the terminal: nmtui")
            return
        self._set_busy(True)
        self._set_status(f"Connecting to {ssid}…")
        args = ["dev", "wifi", "connect", ssid]
        if password:
            args += ["password", password]
        def done(code, out):
            self._set_busy(False)
            msg = out.strip().splitlines()[-1] if out.strip() else ("connected" if code == 0 else "failed")
            self.message.emit(msg)
            self.refreshStatus()
            QTimer.singleShot(1500, self.scan)
        self._run(args, done)

    @Slot()
    def disconnect(self):
        if not self._device:
            return
        def done(code, out):
            self.message.emit("disconnected" if code == 0 else out.strip())
            self.refreshStatus()
        self._run(["dev", "disconnect", self._device], done)

    @Slot(str)
    def forget(self, ssid):
        def done(code, out):
            self.message.emit(f"forgot {ssid}" if code == 0 else out.strip())
            self.refreshStatus()
        self._run(["con", "delete", "id", ssid], done)
