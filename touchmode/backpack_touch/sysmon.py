"""CPU / RAM usage for the GUI Mode tab-bar module and its popup (graphs + hardware details)."""
import os
import socket
import subprocess

from PySide6.QtCore import QObject, QProcess, QTimer, Property, Signal, Slot

HISTORY = 60          # samples kept for the graphs
INTERVAL_MS = 1000


def read_cpu_times(path="/proc/stat"):
    """(busy, total) jiffies summed over all CPUs."""
    with open(path) as f:
        vals = [int(x) for x in f.readline().split()[1:]]
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)   # idle + iowait
    total = sum(vals[:8])                                   # guest time is already in user/nice
    return total - idle, total


def read_meminfo(path="/proc/meminfo"):
    """(total, used) bytes; used = MemTotal - MemAvailable."""
    info = {}
    with open(path) as f:
        for line in f:
            k, _, v = line.partition(":")
            info[k] = int(v.split()[0]) * 1024
    total = info.get("MemTotal", 0)
    return total, total - info.get("MemAvailable", total)


def read_cpu_info(path="/proc/cpuinfo"):
    """{"model", "cores", "threads"} from /proc/cpuinfo."""
    model, threads, cores = "", 0, set()
    phys = core = None
    try:
        with open(path) as f:
            for line in f:
                k, _, v = line.partition(":")
                k, v = k.strip(), v.strip()
                if k == "processor":
                    threads += 1
                elif k == "model name" and not model:
                    model = v
                elif k == "physical id":
                    phys = v
                elif k == "core id":
                    core = v
                elif not k and phys is not None and core is not None:   # blank line ends a block
                    cores.add((phys, core))
                    phys = core = None
        if phys is not None and core is not None:
            cores.add((phys, core))
    except OSError:
        pass
    threads = threads or os.cpu_count() or 0
    return {"model": " ".join(model.split()) or "Unknown CPU", "cores": len(cores) or threads, "threads": threads}


def parse_dmidecode_memory(text):
    """Installed modules from `dmidecode -t 17` output: [{size, type, speed, manufacturer, part, slot}]."""
    mods, cur = [], None
    for line in text.splitlines():
        if line.startswith("Memory Device"):
            cur = {}
            mods.append(cur)
            continue
        if cur is None or ":" not in line:
            continue
        k, _, v = line.strip().partition(":")
        cur[k.strip()] = v.strip()
    out = []
    for m in mods:
        size = m.get("Size", "")
        if not size or size.startswith("No Module") or size in ("Unknown", "0 MB"):
            continue
        speed = m.get("Configured Memory Speed") or m.get("Speed") or ""
        clean = lambda s: "" if s.lower() in ("", "unknown", "not specified", "undefined", "none") else s
        out.append({"size": size, "type": clean(m.get("Type", "")), "speed": clean(speed),
                    "manufacturer": clean(m.get("Manufacturer", "")), "part": clean(m.get("Part Number", "")),
                    "slot": clean(m.get("Locator", ""))})
    return out


def local_ipv4():
    """The address this machine would send from (the default route's source), else the first global
    IPv4 address on any interface, else "". The UDP connect sends no packet."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))   # TEST-NET-1: only picks the route
            return s.getsockname()[0]
    except OSError:
        pass
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"],
                             capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    for line in out.splitlines():   # "2: eth0    inet 192.168.1.20/24 brd ... scope global eth0"
        parts = line.split()
        if "inet" in parts:
            return parts[parts.index("inet") + 1].split("/")[0]
    return ""


def fmt_bytes(n):
    return f"{n / 2**30:.1f} GB"


class SysMonitor(QObject):
    changed = Signal()
    hardwareChanged = Signal()
    ipv4Changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._cpu_hist, self._mem_hist = [], []
        self._cpu = self._mem = 0.0
        self._mem_total = self._mem_used = 0
        self._prev = None
        self._cpu_info = read_cpu_info()
        self._modules, self._modules_note = [], "Reading memory modules…"
        self._timer = QTimer(self)
        self._timer.setInterval(INTERVAL_MS)
        self._timer.timeout.connect(self._sample)
        self._timer.start()
        self._sample()
        QTimer.singleShot(500, self.readModules)
        self._ipv4 = os.environ.get("BACKPACK_DEMO_IPV4") or local_ipv4()   # test hook: a fixed address
        self._ip_timer = QTimer(self)
        self._ip_timer.setInterval(3000)
        self._ip_timer.timeout.connect(self._sample_ip)
        if not os.environ.get("BACKPACK_DEMO_IPV4"):
            self._ip_timer.start()

    def _sample_ip(self):
        ip = local_ipv4()
        if ip != self._ipv4:
            self._ipv4 = ip
            self.ipv4Changed.emit()

    @Property(str, notify=ipv4Changed)
    def ipv4(self):
        """The local IPv4 address shown in the top bar's corner ("" when there is none)."""
        return self._ipv4

    def _sample(self):
        try:
            busy, total = read_cpu_times()
            if self._prev and total > self._prev[1]:
                self._cpu = 100.0 * (busy - self._prev[0]) / (total - self._prev[1])
            self._prev = (busy, total)
            self._mem_total, self._mem_used = read_meminfo()
            self._mem = 100.0 * self._mem_used / self._mem_total if self._mem_total else 0.0
        except (OSError, ValueError, IndexError):
            return
        self._cpu_hist = (self._cpu_hist + [round(self._cpu, 1)])[-HISTORY:]
        self._mem_hist = (self._mem_hist + [round(self._mem, 1)])[-HISTORY:]
        self.changed.emit()

    @Property(float, notify=changed)
    def cpu(self):
        return self._cpu

    @Property(float, notify=changed)
    def mem(self):
        return self._mem

    @Property("QVariantList", notify=changed)
    def cpuHistory(self):
        return self._cpu_hist

    @Property("QVariantList", notify=changed)
    def memHistory(self):
        return self._mem_hist

    @Property(int, constant=True)
    def historyLength(self):
        return HISTORY

    @Property(str, notify=changed)
    def memText(self):
        return f"{fmt_bytes(self._mem_used)} of {fmt_bytes(self._mem_total)} used"

    @Property(str, notify=changed)
    def memCapacity(self):
        return fmt_bytes(self._mem_total) + " usable"

    @Property(str, constant=True)
    def cpuModel(self):
        return self._cpu_info["model"]

    @Property(str, constant=True)
    def cpuCores(self):
        c, t = self._cpu_info["cores"], self._cpu_info["threads"]
        return f"{c} cores, {t} threads" if t != c else f"{c} cores"

    @Property("QVariantList", notify=hardwareChanged)
    def memModules(self):
        return self._modules

    @Property(str, notify=hardwareChanged)
    def memModulesNote(self):
        return self._modules_note

    @Slot()
    def readModules(self):
        """RAM module details come from the SMBIOS tables, which only root can read."""
        p = QProcess(self)
        cmd = ["dmidecode", "-t", "17"]

        def done(code, _status=None):
            out = bytes(p.readAllStandardOutput().data()).decode("utf-8", "replace")
            self._modules = parse_dmidecode_memory(out) if code == 0 else []
            if self._modules:
                self._modules_note = ""
            elif code == 0:
                self._modules_note = "The firmware does not report memory modules."
            else:
                self._modules_note = "Memory module details are not available (needs dmidecode and root)."
            self.hardwareChanged.emit()

        p.finished.connect(done)
        p.errorOccurred.connect(lambda e: e == QProcess.ProcessError.FailedToStart and done(1))
        if os.geteuid() == 0:
            p.start(cmd[0], cmd[1:])
        else:
            p.start("sudo", ["-n"] + cmd)
