#!/usr/bin/env python3
"""Simple GTK4 front-end for scripts/mkusb.sh: pick an ISO and a USB stick, write it.

Runs mkusb.sh through pkexec (graphical password prompt) and streams its output.
Only USB / hot-pluggable whole disks are offered; the disk holding / is never listed.
Needs python3-gi + GTK 4.10+ (stock on Ubuntu 24.04+/Debian trixie desktops).
"""
import json
import os
import re
import subprocess
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gtk, Pango  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MKUSB = os.path.join(ROOT, "scripts", "mkusb.sh")
DEFAULT_ISO = os.path.join(ROOT, "build", "nettoolkit.iso")


def human(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1000


def root_disk():
    try:
        src = subprocess.run(["findmnt", "-no", "SOURCE", "/"], capture_output=True, text=True).stdout.strip()
        pk = subprocess.run(["lsblk", "-no", "PKNAME", src], capture_output=True, text=True).stdout.split()
        return "/dev/" + pk[0] if pk else ""
    except OSError:
        return ""


def usb_disks():
    """[{path, label, size, has_persistence, mounted:[parts]}] for removable/USB whole disks."""
    out = subprocess.run(
        ["lsblk", "-J", "-b", "-o", "NAME,PATH,SIZE,MODEL,VENDOR,TRAN,RM,HOTPLUG,TYPE,LABEL,MOUNTPOINTS"],
        capture_output=True, text=True).stdout
    rootdev = root_disk()
    disks = []
    for d in json.loads(out or '{"blockdevices":[]}')["blockdevices"]:
        if d.get("type") != "disk" or d["path"] == rootdev or not int(d.get("size") or 0):
            continue
        if d.get("tran") != "usb" and not d.get("rm") and not d.get("hotplug"):
            continue
        kids = d.get("children") or []
        mounted = [k["path"] for k in kids if any(k.get("mountpoints") or [])]
        if any(d.get("mountpoints") or []):
            mounted.append(d["path"])
        name = " ".join(x.strip() for x in (d.get("vendor"), d.get("model")) if x and x.strip()) or "disk"
        disks.append({
            "path": d["path"],
            "size": int(d["size"]),
            "label": f'{d["path"]}  —  {name}  ({human(int(d["size"]))})',
            "has_persistence": any(k.get("label") == "persistence" for k in kids),
            "mounted": mounted,
        })
    return disks


class Win(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="NetToolkit USB Writer")
        self.set_default_size(640, 520)
        self.iso = DEFAULT_ISO if os.path.isfile(DEFAULT_ISO) else ""
        self.disks = []
        self.proc = None
        self.buf = ""

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                      margin_top=14, margin_bottom=14, margin_start=14, margin_end=14)
        self.set_child(box)
        grid = Gtk.Grid(column_spacing=10, row_spacing=10)
        box.append(grid)

        # ISO
        grid.attach(Gtk.Label(label="ISO image", xalign=0), 0, 0, 1, 1)
        self.iso_label = Gtk.Label(xalign=0, hexpand=True, ellipsize=Pango.EllipsizeMode.START)
        grid.attach(self.iso_label, 1, 0, 1, 1)
        b = Gtk.Button(label="Choose…")
        b.connect("clicked", self.choose_iso)
        grid.attach(b, 2, 0, 1, 1)

        # device
        grid.attach(Gtk.Label(label="USB drive", xalign=0), 0, 1, 1, 1)
        self.dev_dd = Gtk.DropDown.new_from_strings([])
        self.dev_dd.set_hexpand(True)
        self.dev_dd.connect("notify::selected", lambda *_: self.on_device())
        grid.attach(self.dev_dd, 1, 1, 1, 1)
        b = Gtk.Button(label="Refresh")
        b.connect("clicked", lambda *_: self.refresh())
        grid.attach(b, 2, 1, 1, 1)

        # mode
        grid.attach(Gtk.Label(label="Mode", xalign=0), 0, 2, 1, 1)
        mode = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.fresh = Gtk.CheckButton(label="Fresh install — erase the drive, new persistence partition")
        self.keep = Gtk.CheckButton(label="Update system only — keep the existing persistence (saved data)")
        self.keep.set_group(self.fresh)
        self.fresh.set_active(True)
        self.fresh.connect("toggled", lambda *_: self.update_state())
        mode.append(self.fresh)
        mode.append(self.keep)
        grid.attach(mode, 1, 2, 2, 1)

        grid.attach(Gtk.Label(label="Persistence", xalign=0), 0, 3, 1, 1)
        sz = Gtk.Box(spacing=6)
        self.size = Gtk.SpinButton.new_with_range(1, 256, 1)
        self.size.set_value(5)
        sz.append(self.size)
        sz.append(Gtk.Label(label="GB"))
        grid.attach(sz, 1, 3, 1, 1)

        # action + progress
        self.write_btn = Gtk.Button(label="Write to USB")
        self.write_btn.add_css_class("destructive-action")
        self.write_btn.connect("clicked", self.confirm)
        box.append(self.write_btn)
        self.progress = Gtk.ProgressBar(show_text=True, text="Ready")
        box.append(self.progress)
        self.status = Gtk.Label(xalign=0, wrap=True)
        box.append(self.status)

        self.log = Gtk.TextView(editable=False, monospace=True, cursor_visible=False)
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.set_child(self.log)
        box.append(sw)

        self.refresh()

    # ------------------------------------------------------------------ state
    def refresh(self):
        self.disks = usb_disks()
        labels = [d["label"] for d in self.disks] or ["(no USB drive found — plug one in and press Refresh)"]
        self.dev_dd.set_model(Gtk.StringList.new(labels))
        self.dev_dd.set_selected(0)
        self.on_device()

    def device(self):
        i = self.dev_dd.get_selected()
        return self.disks[i] if self.disks and i < len(self.disks) else None

    def on_device(self):
        d = self.device()
        # default to "keep" when the stick already carries a NetToolkit persistence partition
        if d and d["has_persistence"]:
            self.keep.set_active(True)
        else:
            self.fresh.set_active(True)
        self.update_state()

    def update_state(self):
        d = self.device()
        busy = self.proc is not None
        self.iso_label.set_text(self.iso or "(none selected)")
        self.keep.set_sensitive(bool(d and d["has_persistence"]) and not busy)
        self.size.set_sensitive(self.fresh.get_active() and not busy)
        self.write_btn.set_sensitive(bool(d and self.iso) and not busy)
        if not busy:
            if not self.iso:
                self.status.set_text("Choose an ISO image (run `make build` to create build/nettoolkit.iso).")
            elif not d:
                self.status.set_text("No USB drive detected.")
            elif d["has_persistence"]:
                self.status.set_text("This drive already has a NetToolkit persistence partition.")
            else:
                self.status.set_text("")

    def choose_iso(self, *_):
        dlg = Gtk.FileDialog(title="Choose ISO image")
        f = Gtk.FileFilter()
        f.set_name("ISO images")
        f.add_pattern("*.iso")
        filters = Gio.ListStore.new(Gtk.FileFilter)
        filters.append(f)
        dlg.set_filters(filters)
        if self.iso:
            dlg.set_initial_folder(Gio.File.new_for_path(os.path.dirname(self.iso)))

        def done(dialog, res):
            try:
                self.iso = dialog.open_finish(res).get_path()
            except GLib.Error:
                return
            self.update_state()
        dlg.open(self, None, done)

    # ------------------------------------------------------------------ run
    def confirm(self, *_):
        d = self.device()
        if self.keep.get_active():
            body = (f"The system on {d['path']} will be replaced with:\n{os.path.basename(self.iso)}\n\n"
                    "Your persistence partition (saved files, Wi-Fi, settings) is kept.")
            ok = "Update"
        else:
            body = (f"EVERYTHING on {d['path']} ({human(d['size'])}) will be erased and replaced with:\n"
                    f"{os.path.basename(self.iso)} + {int(self.size.get_value())} GB persistence.")
            ok = "Erase and write"
        dlg = Gtk.AlertDialog(message=d["label"], detail=body, buttons=["Cancel", ok],
                              cancel_button=0, default_button=0, modal=True)

        def done(dialog, res):
            try:
                if dialog.choose_finish(res) == 1:
                    self.start(d)
            except GLib.Error:
                pass
        dlg.choose(self, None, done)

    def append(self, text):
        b = self.log.get_buffer()
        b.insert(b.get_end_iter(), text)
        self.log.scroll_to_iter(b.get_end_iter(), 0, False, 0, 0)

    def start(self, d):
        # mkusb.sh refuses mounted targets: unmount via udisks (no root needed)
        for part in d["mounted"]:
            r = subprocess.run(["udisksctl", "unmount", "-b", part], capture_output=True, text=True)
            self.append((r.stdout or r.stderr).strip() + "\n")
        self.iso_size = os.path.getsize(self.iso)
        args = ["pkexec", MKUSB, "--yes", "--iso", self.iso]
        args += ["--keep-persistence"] if self.keep.get_active() else ["--size", f"{int(self.size.get_value())}G"]
        args.append(d["path"])
        self.append("$ " + " ".join(args) + "\n")
        self.progress.set_fraction(0)
        self.progress.set_text("Waiting for password…")
        self.status.set_text("Writing — do not unplug the drive.")
        try:
            self.proc = Gio.Subprocess.new(args, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE)
        except GLib.Error as e:
            self.append(f"error: {e.message}\n")
            return
        self.update_state()
        self.stream = self.proc.get_stdout_pipe()
        self.stream.read_bytes_async(4096, GLib.PRIORITY_DEFAULT, None, self.on_read)
        self.proc.wait_async(None, self.on_exit)

    def on_read(self, stream, res):
        try:
            data = stream.read_bytes_finish(res).get_data()
        except GLib.Error:
            return
        if not data:
            return
        text = data.decode(errors="replace")
        # dd status=progress rewrites one line with \r: show its latest value on the bar, not the log
        self.buf += text
        *lines, self.buf = re.split(r"[\r\n]", self.buf)
        for ln in lines:
            m = re.match(r"(\d+) bytes", ln)
            if m:
                frac = min(1.0, int(m.group(1)) / self.iso_size)
                self.progress.set_fraction(frac)
                self.progress.set_text(f"Writing image {frac * 100:.0f}%")
            elif ln.strip():
                self.append(ln + "\n")
        m = re.match(r"(\d+) bytes", self.buf)
        if m:
            frac = min(1.0, int(m.group(1)) / self.iso_size)
            self.progress.set_fraction(frac)
            self.progress.set_text(f"Writing image {frac * 100:.0f}%")
        stream.read_bytes_async(4096, GLib.PRIORITY_DEFAULT, None, self.on_read)

    def on_exit(self, proc, res):
        proc.wait_finish(res)
        code = proc.get_exit_status()
        if self.buf.strip():
            self.append(self.buf + "\n")
        self.buf = ""
        self.proc = None
        if code == 0:
            self.progress.set_fraction(1)
            self.progress.set_text("Done")
            self.status.set_text("Finished. You can remove the drive.")
        elif code in (126, 127):
            self.progress.set_text("Cancelled")
            self.status.set_text("Authentication was cancelled or failed.")
        else:
            self.progress.set_text(f"Failed (exit {code})")
            self.status.set_text("Writing failed — see the log above.")
        msg = self.status.get_text()
        self.refresh()                 # partitions changed; keep the result message visible
        self.status.set_text(msg)


def main():
    app = Gtk.Application(application_id="live.nettoolkit.UsbWriter")
    app.connect("activate", lambda a: Win(a).present())
    return app.run(sys.argv[:1])


if __name__ == "__main__":
    sys.exit(main())
