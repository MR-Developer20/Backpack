#!/usr/bin/env python3
"""Validate manifest/tools.yaml and generate the live-build package list.

Usage: gen-package-list.py [--check] [--edition normal|extras] [--manifest FILE] [--out FILE]
                           [--manifest-out FILE] [--print-cmds]

Editions: `normal` ships the Network and Data tabs only; `extras` also ships the Extra tab's apps.
"""
import argparse, os, re, shutil, sys
import yaml

CATEGORIES = {"discovery", "connectivity", "capture", "wireless", "throughput", "dns-http",
              "disks", "recovery", "files", "transfer", "extra"}
ARG_TYPES = {"string", "int", "flag", "choice", "interface"}
INTERFACE_KINDS = {"any", "wifi", "monitor", "wired"}
ID_RE = re.compile(r"^[a-z0-9-]+$")
EDITIONS = ("normal", "extras")
EXTRA_CATEGORIES = {"extra"}   # only in the extras edition


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


def is_extra(tool):
    return tool["category"] in EXTRA_CATEGORIES


def write_list(path, tools, what):
    pkgs = sorted({p for t in tools for p in t["packages"]})
    with open(path, "w") as f:
        f.write(f"# GENERATED from manifest/tools.yaml by scripts/gen-package-list.py ({what}) — do not edit\n")
        f.write("\n".join(pkgs) + "\n")
    print(f"wrote {path}: {len(pkgs)} packages from {len(tools)} tools")


def write_manifest(src, doc, tools, edition, out):
    """The manifest the ISO ships (/etc/backpack/tools.yaml): the whole file for extras, without
    the Extra tab's tools for normal, so GUI Mode hides that tab."""
    if edition == "extras":
        shutil.copyfile(src, out)
        return
    with open(out, "w") as f:
        f.write(f"# GENERATED from {src} for the {edition} edition by scripts/gen-package-list.py\n")
        yaml.safe_dump({**doc, "tools": [t for t in tools if not is_extra(t)]}, f,
                       sort_keys=False, allow_unicode=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default="manifest/tools.yaml")
    ap.add_argument("--out", default="live/config/package-lists/backpack.list.chroot",
                    help="package list of the Network + Data tools (every edition)")
    ap.add_argument("--extras-out", default="live/config/package-lists/extras.list.chroot",
                    help="package list of the Extra tab's apps: written for extras, removed for normal")
    ap.add_argument("--edition", choices=EDITIONS, default="normal")
    ap.add_argument("--manifest-out", help="also write the edition's manifest here")
    ap.add_argument("--check", action="store_true", help="validate only")
    ap.add_argument("--print-cmds", action="store_true", help="print 'id cmd' pairs")
    args = ap.parse_args()

    with open(args.manifest) as f:
        doc = yaml.safe_load(f)
    tools = validate(doc)

    if args.print_cmds:   # every tool in the given manifest (the ISO's own is already per edition)
        for t in tools:
            if t.get("optional"):   # installed separately; GUI Mode hides it when absent
                continue
            for c in t["commands"]:
                print(t["id"], c["cmd"])
        return
    if args.check:
        print(f"manifest ok: {len(tools)} tools")
        return

    write_list(args.out, [t for t in tools if not is_extra(t)], "every edition")
    if args.edition == "extras":
        write_list(args.extras_out, [t for t in tools if is_extra(t)], "extras edition")
    elif os.path.exists(args.extras_out):
        os.remove(args.extras_out)
    if args.manifest_out:
        write_manifest(args.manifest, doc, tools, args.edition, args.manifest_out)
    print(f"edition: {args.edition}")


if __name__ == "__main__":
    main()
