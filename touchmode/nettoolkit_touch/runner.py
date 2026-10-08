"""Run manifest commands and stream their output to QML."""
import os
import shlex
from PySide6.QtCore import QObject, QProcess, Property, Signal, Slot

from . import manifest

TERMINAL = os.environ.get("NETTOOLKIT_TERMINAL", "foot")


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
            QProcess.startDetached(argv[0], argv[1:])
            self.output.emit(f"launched {manifest.display(argv)}\n")
            return
        if cmd["tty"]:
            script = manifest.display(argv) + '; echo; echo "[press Enter to close]"; read _'
            QProcess.startDetached(TERMINAL, ["-e", "sh", "-c", script])
            self.output.emit(f"opened in terminal: {manifest.display(argv)}\n")
            return
        self.stop()
        p = QProcess(self)
        p.setProcessChannelMode(QProcess.MergedChannels)
        p.readyReadStandardOutput.connect(lambda: self.output.emit(
            bytes(p.readAllStandardOutput().data()).decode("utf-8", "replace")))
        p.finished.connect(self._finished)
        p.errorOccurred.connect(lambda e, prog=argv[0]: self.error.emit(f"{prog}: {e.name if hasattr(e, 'name') else e}"))
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


class System(QObject):
    """Terminal / split / power buttons."""

    @Slot()
    def openTerminal(self):
        QProcess.startDetached("sh", ["-c",
            f"swaymsg fullscreen disable; swaymsg exec {shlex.quote(TERMINAL)}"])

    @Slot()
    def splitTerminal(self):
        QProcess.startDetached("sh", ["-c",
            f"swaymsg fullscreen disable; swaymsg splith; swaymsg exec {shlex.quote(TERMINAL)}"])

    @Slot()
    def poweroff(self):
        QProcess.startDetached("sh", ["-c", "systemctl poweroff || sudo -n systemctl poweroff"])

    @Slot()
    def reboot(self):
        QProcess.startDetached("sh", ["-c", "systemctl reboot || sudo -n systemctl reboot"])
