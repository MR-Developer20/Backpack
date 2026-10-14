"""Load /etc/backpack/tools.yaml and build command lines from arg values."""
import os
import shlex
import shutil
import yaml

# GUI Mode tabs: each section groups some categories (in display order)
SECTIONS = [
    ("network", "Network", ["discovery", "connectivity", "capture", "wireless", "throughput", "dns-http"]),
    ("data", "Data", ["disks", "recovery", "files", "transfer"]),
    ("extra", "Extra", ["extra"]),
]
CATEGORY_ORDER = [c for _, _, cats in SECTIONS for c in cats]
CATEGORY_SECTION = {c: sid for sid, _, cats in SECTIONS for c in cats}
CATEGORY_LABELS = {
    "discovery": "Discovery", "connectivity": "Connectivity", "capture": "Capture",
    "wireless": "Wireless", "throughput": "Throughput", "dns-http": "DNS / HTTP",
    "disks": "Disks", "recovery": "Recovery", "files": "Files", "transfer": "Transfer",
    "extra": "Apps",
}
DEFAULT_PATH = "/etc/backpack/tools.yaml"
NET_DIR = "/sys/class/net"
INTERFACE_KINDS = ("any", "wifi", "monitor", "wired")


def manifest_path():
    return os.environ.get("BACKPACK_MANIFEST", DEFAULT_PATH)


def load(path=None):
    with open(path or manifest_path()) as f:
        doc = yaml.safe_load(f)
    # optional tools (installed separately, e.g. eDEX-UI) only show up when their program is there
    tools = [t for t in doc["tools"]
             if not t.get("optional") or shutil.which(t["commands"][0]["cmd"])]
    # normalise so QML gets plain, predictable shapes
    for t in tools:
        t.setdefault("gui", False)
        t["section"] = CATEGORY_SECTION.get(t["category"], "network")
        for c in t["commands"]:
            c.setdefault("args", [])
            c.setdefault("needs_root", False)
            c.setdefault("tty", False)
            for a in c["args"]:
                a.setdefault("default", "")
                a.setdefault("required", False)
                a.setdefault("flag", "")
                a.setdefault("sep", " ")
                a.setdefault("options", [])
                a.setdefault("label", a["name"].replace("_", " "))   # what a person recognises
                if a["type"] == "interface":
                    a.setdefault("kind", "any")
            c["template"] = template(c)
    return tools


def template(command):
    """The command line a button stands for, with <name> where a form value goes:
    `nmap -sn <target>`. Flags that default to on are shown; off ones are left out.
    Same shape as what run() executes (the `sudo -n` prefix follows the same rule)."""
    return preview(command, {}, placeholders=True)


def preview(command, values, placeholders=False):
    """The command line as the form stands, for display: like build_argv, but an empty
    required field shows as a `<name>` placeholder instead of an error, a non-numeric int
    is shown as typed, and the result is one string with shell quoting. With `placeholders`
    every value is a `<name>` slot (the action chip's template)."""
    parts = [command["cmd"]]
    for a in command["args"]:
        name, t = a["name"], a["type"]
        v = values.get(name, a["default"]) if values else a["default"]
        if t == "flag":
            if v in (True, "true", 1, "1"):
                parts.append(a["flag"])
            continue
        s = "" if v is None else str(v).strip()
        if placeholders:
            quoted = "<" + name + ">"          # the action's shape: every value is a slot
        elif s == "":
            if not a["required"]:
                continue
            quoted = "<" + name + ">"
        else:
            quoted = shlex.quote(s)
        if a["flag"] and a["sep"] == "":   # one word, quoted as display() quotes the argv
            parts.append(a["flag"] + quoted if quoted.startswith("<") else shlex.quote(a["flag"] + s))
        elif a["flag"]:
            parts.append(a["flag"] + " " + quoted)
        else:
            parts.append(quoted)
    if command["needs_root"] and os.geteuid() != 0:
        parts.insert(0, "sudo -n")
    return " ".join(parts)


def _read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def interfaces(kind="any", net_dir=None):
    """The network interfaces on this machine, for an `interface` field: [{name, kind, up}] with
    kind wifi | monitor | wired | other (virtual: bridges, tunnels, containers). `kind` filters:
    wifi = Wi-Fi adapters including ones in monitor mode, monitor = the same with monitor mode first,
    wired = physical non-Wi-Fi adapters, any = everything but loopback. Up interfaces come first."""
    net_dir = net_dir or os.environ.get("BACKPACK_NET_DIR", NET_DIR)   # test hook: a fake /sys/class/net
    try:
        names = sorted(os.listdir(net_dir))
    except OSError:
        return []
    out = []
    for n in names:
        d = os.path.join(net_dir, n)
        if n == "lo" or _read(os.path.join(d, "type")) == "772":   # loopback
            continue
        if _read(os.path.join(d, "type")) == "803":                 # ARPHRD_IEEE80211_RADIOTAP
            k = "monitor"
        elif os.path.exists(os.path.join(d, "wireless")) or os.path.exists(os.path.join(d, "phy80211")):
            k = "wifi"
        elif os.path.exists(os.path.join(d, "device")):
            k = "wired"
        else:
            k = "other"
        if kind in ("wifi", "monitor") and k not in ("wifi", "monitor"):
            continue
        if kind == "wired" and k != "wired":
            continue
        state = _read(os.path.join(d, "operstate"))
        try:   # monitor-mode and some USB adapters report "unknown" while up: fall back to IFF_UP
            admin_up = int(_read(os.path.join(d, "flags")) or "0", 16) & 1
        except ValueError:
            admin_up = 0
        out.append({"name": n, "kind": k, "up": state == "up" or (state == "unknown" and bool(admin_up))})
    out.sort(key=lambda i: (kind == "monitor" and i["kind"] != "monitor", not i["up"]))   # stable: names stay sorted
    return out


def categories(tools):
    present = {t["category"] for t in tools}
    return [{"id": c, "label": CATEGORY_LABELS.get(c, c), "section": CATEGORY_SECTION[c]}
            for c in CATEGORY_ORDER if c in present]


def sections(tools):
    """Tabs that have at least one tool: [{id, label, count}]."""
    out = []
    for sid, label, cats in SECTIONS:
        n = sum(1 for t in tools if t["category"] in cats)
        if n:
            out.append({"id": sid, "label": label, "count": n})
    return out


def build_argv(command, values):
    """Return (argv, error). `values` maps arg name -> user value (str/int/bool)."""
    argv = [command["cmd"]]
    for a in command["args"]:
        name, t = a["name"], a["type"]
        v = values.get(name, a["default"]) if values else a["default"]
        if t == "flag":
            if v in (True, "true", 1, "1"):
                argv.append(a["flag"])
            continue
        if v is None or str(v).strip() == "":
            if a["required"]:
                return None, f"'{name}' is required"
            continue
        s = str(v).strip()
        if t == "int":
            try:
                int(s)
            except ValueError:
                return None, f"'{name}' must be a number"
        if a["flag"]:
            if a["sep"] == "":
                argv.append(a["flag"] + s)
            else:
                argv += [a["flag"], s]
        else:
            argv.append(s)
    if command["needs_root"] and os.geteuid() != 0:
        argv = ["sudo", "-n"] + argv
    return argv, ""


def display(argv):
    return " ".join(shlex.quote(x) for x in argv)
