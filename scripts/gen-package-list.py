#!/usr/bin/env python3
"""Validate manifest/tools.yaml and generate the live-build package list.

Usage: gen-package-list.py [--check] [--manifest FILE] [--out FILE] [--print-cmds]
"""
import argparse, re, sys
import yaml

CATEGORIES = {"discovery", "connectivity", "capture", "wireless", "throughput", "dns-http"}
ARG_TYPES = {"string", "int", "flag", "choice"}
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
        if not t["commands"]:
            fail(f"{tid}: commands must be non-empty")
        for c in t["commands"]:
            for k in ("label", "cmd", "args", "needs_root"):
                if k not in c:
                    fail(f"{tid}: command missing {k}")
            for a in c["args"]:
                if "name" not in a or a.get("type") not in ARG_TYPES:
                    fail(f"{tid}/{c['label']}: bad arg {a}")
                if a["type"] == "choice" and not a.get("options"):
                    fail(f"{tid}/{c['label']}: choice arg {a['name']} needs options")
    return tools


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default="manifest/tools.yaml")
    ap.add_argument("--out", default="live/config/package-lists/nettoolkit.list.chroot")
    ap.add_argument("--check", action="store_true", help="validate only")
    ap.add_argument("--print-cmds", action="store_true", help="print 'id cmd' pairs")
    args = ap.parse_args()

    with open(args.manifest) as f:
        doc = yaml.safe_load(f)
    tools = validate(doc)

    if args.print_cmds:
        for t in tools:
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
