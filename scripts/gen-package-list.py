#!/usr/bin/env python3
"""Validate manifest/tools.yaml and generate the live-build package list.

Usage: gen-package-list.py [--check] [--manifest FILE] [--out FILE] [--print-cmds]
"""
import argparse, re, sys
import yaml

CATEGORIES = {"discovery", "connectivity", "capture", "wireless", "throughput", "dns-http",
              "disks", "recovery", "files", "transfer", "extra"}
ARG_TYPES = {"string", "int", "flag", "choice", "interface"}
INTERFACE_KINDS = {"any", "wifi", "monitor", "wired"}
ID_RE = re.compile(r"^[a-z0-9-]+$")


def fail(msg):
    print(f"manifest error: {msg}", file=sys.stderr)
    sys.exit(1)


def validate(doc):
    if doc.get("version") != 1:
        fail("version must be 1")
    tools = doc.get("tools")
    if not isinstance(tools, list) or not tools:
        fail("tools must be a non-empty list")
    seen = set()
    for t in tools:
        tid = t.get("id")
        if not tid or not ID_RE.match(tid):
            fail(f"bad id {tid!r}")
        if tid in seen:
            fail(f"duplicate id {tid}")
        seen.add(tid)
        for k in ("name", "description", "category", "packages", "commands"):
            if k not in t:
                fail(f"{tid}: missing {k}")
        if t["category"] not in CATEGORIES:
            fail(f"{tid}: bad category {t['category']}")
        if not isinstance(t["packages"], list) or not all(isinstance(p, str) for p in t["packages"]):
            fail(f"{tid}: packages must be a list of strings")
        src = t.get("source")
        if src is not None:
            if src.get("type") != "upstream":
                fail(f"{tid}: source.type must be upstream")
            if "url" in src and "sha256" not in src:
                fail(f"{tid}: source.url needs sha256")
            if "apt_repo" in src and ("apt_key_url" not in src or "apt_key_sha256" not in src):
                fail(f"{tid}: apt_repo needs apt_key_url + apt_key_sha256")
            if "url" not in src and "apt_repo" not in src:
                fail(f"{tid}: source needs url or apt_repo")
        if not isinstance(t.get("gui", False), bool):
            fail(f"{tid}: gui must be a bool")
        if not isinstance(t.get("optional", False), bool):
            fail(f"{tid}: optional must be a bool")
        if not isinstance(t["commands"], list) or not t["commands"]:
            fail(f"{tid}: commands must be a non-empty list")
        for c in t["commands"]:
            for k in ("label", "cmd", "args", "needs_root"):
                if k not in c:
                    fail(f"{tid}: command missing {k}")
            if not isinstance(c["needs_root"], bool) or not isinstance(c.get("tty", False), bool):
                fail(f"{tid}/{c['label']}: needs_root and tty must be bools")
            if not isinstance(c["args"], list):
                fail(f"{tid}/{c['label']}: args must be a list")
            for a in c["args"]:
                if "name" not in a or a.get("type") not in ARG_TYPES:
                    fail(f"{tid}/{c['label']}: bad arg {a}")
                if a["type"] == "choice" and not a.get("options"):
                    fail(f"{tid}/{c['label']}: choice arg {a['name']} needs options")
                if a["type"] == "choice" and a.get("default") not in a["options"]:
                    fail(f"{tid}/{c['label']}: choice arg {a['name']} default not in options")
                if a["type"] == "flag" and (not a.get("flag") or not isinstance(a.get("default", False), bool)):
                    fail(f"{tid}/{c['label']}: flag arg {a['name']} needs a flag and a bool default")
                if a["type"] == "int" and not isinstance(a.get("default", 0), int):
                    fail(f"{tid}/{c['label']}: int arg {a['name']} default must be an int")
                if a["type"] == "interface" and a.get("kind", "any") not in INTERFACE_KINDS:
                    fail(f"{tid}/{c['label']}: interface arg {a['name']} kind must be one of {sorted(INTERFACE_KINDS)}")
                if a["type"] == "interface" and not all(isinstance(o, str) and o for o in a.get("options", [])):
                    fail(f"{tid}/{c['label']}: interface arg {a['name']} options must be non-empty strings")
                if a.get("sep", " ") not in ("", " "):
                    fail(f"{tid}/{c['label']}: arg {a['name']} sep must be \"\" or \" \"")
                if "label" in a and (not isinstance(a["label"], str) or not a["label"].strip()):
                    fail(f"{tid}/{c['label']}: arg {a['name']} label must be a non-empty string")
    return tools


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default="manifest/tools.yaml")
    ap.add_argument("--out", default="live/config/package-lists/backpack.list.chroot")
    ap.add_argument("--check", action="store_true", help="validate only")
    ap.add_argument("--print-cmds", action="store_true", help="print 'id cmd' pairs")
    args = ap.parse_args()

    with open(args.manifest) as f:
        doc = yaml.safe_load(f)
    tools = validate(doc)

    if args.print_cmds:
        for t in tools:
            if t.get("optional"):   # installed separately; GUI Mode hides it when absent
                continue
            for c in t["commands"]:
                print(t["id"], c["cmd"])
        return
    if args.check:
        print(f"manifest ok: {len(tools)} tools")
        return

    pkgs = sorted({p for t in tools for p in t["packages"]})
    with open(args.out, "w") as f:
        f.write("# GENERATED from manifest/tools.yaml by scripts/gen-package-list.py — do not edit\n")
        f.write("\n".join(pkgs) + "\n")
    print(f"wrote {args.out}: {len(pkgs)} packages from {len(tools)} tools")


if __name__ == "__main__":
    main()
