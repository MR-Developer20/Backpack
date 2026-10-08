"""Load /etc/nettoolkit/tools.yaml and build command lines from arg values."""
import os
import shlex
import yaml

CATEGORY_ORDER = ["discovery", "connectivity", "capture", "wireless", "throughput", "dns-http"]
CATEGORY_LABELS = {
    "discovery": "Discovery", "connectivity": "Connectivity", "capture": "Capture",
    "wireless": "Wireless", "throughput": "Throughput", "dns-http": "DNS / HTTP",
}
DEFAULT_PATH = "/etc/nettoolkit/tools.yaml"


def manifest_path():
    return os.environ.get("NETTOOLKIT_MANIFEST", DEFAULT_PATH)


def load(path=None):
    with open(path or manifest_path()) as f:
        doc = yaml.safe_load(f)
    tools = doc["tools"]
    # normalise so QML gets plain, predictable shapes
    for t in tools:
        t.setdefault("gui", False)
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
    return [{"id": c, "label": CATEGORY_LABELS.get(c, c)} for c in CATEGORY_ORDER if c in present]


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
