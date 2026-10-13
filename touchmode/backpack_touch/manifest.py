"""Load /etc/backpack/tools.yaml and build command lines from arg values."""
import os
import shlex
import shutil
import yaml

# GUI Mode tabs: each section groups some categories (in display order)
SECTIONS = [
    ("network", "Network", ["discovery", "connectivity", "capture", "wireless", "throughput", "dns-http"]),
    ("data", "Data", ["disks", "recovery", "files", "transfer"]),
    ("extra", "Extra", ["apps"]),
]
CATEGORY_ORDER = [c for _, _, cats in SECTIONS for c in cats]
CATEGORY_SECTION = {c: sid for sid, _, cats in SECTIONS for c in cats}
CATEGORY_LABELS = {
    "discovery": "Discovery", "connectivity": "Connectivity", "capture": "Capture",
    "wireless": "Wireless", "throughput": "Throughput", "dns-http": "DNS / HTTP",
    "disks": "Disks", "recovery": "Recovery", "files": "Files", "transfer": "Transfer",
    "apps": "Apps",
}
DEFAULT_PATH = "/etc/backpack/tools.yaml"


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
    return tools


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
