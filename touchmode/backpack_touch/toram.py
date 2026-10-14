"""Move the running live system into RAM after boot ("Load to RAM" in GUI Mode settings).

live-boot mounts the root squashfs through a read-only loop device backed by
/run/live/medium/live/filesystem.squashfs on the USB stick. `run` copies that file into a
dedicated tmpfs and swaps the loop device's backing file with LOOP_CHANGE_FD (allowed for
read-only loops when the new file has the same size), then unmounts the stick if nothing
else on it is in use. Same end state as booting with `toram`, without a reboot.

    python3 -m backpack_touch.toram status   # JSON, works unprivileged
    python3 -m backpack_touch.toram run      # as root; prints PROGRESS n / DONE msg / ERROR msg
"""
import fcntl
import json
import os
import subprocess
import sys

LOOP_CHANGE_FD = 0x4C06
SYS_BLOCK = "/sys/block"
RAM_DIR = "/run/backpack-ram"
MEDIUM = "/run/live/medium"
HEADROOM = 512 * 1024 * 1024   # keep this much RAM free after the copy
CHUNK = 4 * 1024 * 1024


def _out(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def find_image():
    """(loop device, backing file) of the live root squashfs, or (None, None).

    Reads sysfs rather than running losetup: losetup lives in /usr/sbin, which is not on the
    live user's PATH, so the unprivileged status check never found the image."""
    try:
        names = sorted(n for n in os.listdir(SYS_BLOCK) if n.startswith("loop"))
    except OSError:
        return None, None
    for name in names:
        try:
            with open(os.path.join(SYS_BLOCK, name, "loop", "backing_file")) as f:
                back = f.read().strip()
        except OSError:
            continue
        if back.endswith(".squashfs"):
            return f"/dev/{name}", back
    return None, None


def fstype(path):
    return _out("findmnt", "-n", "-o", "FSTYPE", "--target", path).strip()


def mem_available():
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemAvailable:"):
                    return int(line.split()[1]) * 1024
    except OSError:
        pass
    return 0


def status():
    loop, image = find_image()
    size = 0
    if image:
        try:
            size = os.path.getsize(image)
        except OSError:
            image = None
    in_ram = bool(image) and fstype(image) in ("tmpfs", "ramfs")
    return {"supported": bool(image), "inRam": in_ram, "image": image or "", "loop": loop or "",
            "size": size, "memAvailable": mem_available(), "headroom": HEADROOM}


def _say(kind, msg=""):
    print(f"{kind} {msg}".rstrip(), flush=True)


def _medium_disk():
    src = _out("findmnt", "-n", "-o", "SOURCE", MEDIUM).strip()
    if not src.startswith("/dev/"):
        return src, ""
    return src, _out("lsblk", "-n", "-o", "PKNAME", src).strip() or os.path.basename(src)


def _release_medium():
    """Unmount the stick's ISO filesystem. Returns a sentence for the user."""
    src, disk = _medium_disk()
    if not src:
        return "The system now runs from RAM."
    if subprocess.run(["umount", MEDIUM], capture_output=True).returncode != 0:
        return "The system now runs from RAM, but the USB stick is still in use, so leave it plugged in."
    if disk:
        busy = [l.split()[1] for l in _out("lsblk", "-n", "-r", "-o", "NAME,MOUNTPOINT", f"/dev/{disk}").splitlines()
                if len(l.split()) == 2]
        if busy:
            return ("The system now runs from RAM. The persistence partition on the USB stick is still "
                    "mounted, so leave the stick plugged in to keep saving your files.")
    return "The system now runs from RAM. You can unplug the USB stick."


def run():
    st = status()
    if not st["supported"]:
        _say("ERROR", "This is not running from a Backpack live USB.")
        return 1
    if st["inRam"]:
        _say("DONE", "The system already runs from RAM.")
        return 0
    need = st["size"] + HEADROOM
    if st["memAvailable"] < need:
        _say("ERROR", f"Not enough free memory: need {need // 2**20} MiB, have {st['memAvailable'] // 2**20} MiB.")
        return 1
    os.makedirs(RAM_DIR, exist_ok=True)
    # Our own tmpfs, sized for the image. Checking the fstype would not do: /run is itself a
    # tmpfs (10% of RAM from initramfs-tools), so RAM_DIR always looked like one and the copy
    # landed in /run and ran out of space on machines with less than ~10x the image in RAM.
    if not os.path.ismount(RAM_DIR):
        size_mib = st["size"] // 2**20 + 16
        r = subprocess.run(["mount", "-t", "tmpfs", "-o", f"size={size_mib}m,mode=0755", "backpack-ram", RAM_DIR],
                           capture_output=True, text=True)
        if r.returncode != 0:
            _say("ERROR", f"Could not create the RAM disk: {r.stderr.strip()}")
            return 1
    dest = os.path.join(RAM_DIR, os.path.basename(st["image"]))
    try:
        done, last = 0, -1
        with open(st["image"], "rb") as src, open(dest, "wb") as dst:
            while True:
                buf = src.read(CHUNK)
                if not buf:
                    break
                dst.write(buf)
                done += len(buf)
                pct = done * 100 // max(st["size"], 1)
                if pct != last:
                    _say("PROGRESS", str(pct))
                    last = pct
        if os.path.getsize(dest) != st["size"]:
            raise OSError("copy is incomplete")
        newfd = os.open(dest, os.O_RDONLY)
        loopfd = os.open(st["loop"], os.O_RDONLY)
        try:
            fcntl.ioctl(loopfd, LOOP_CHANGE_FD, newfd)
        finally:
            os.close(loopfd)
            os.close(newfd)
    except OSError as e:
        try:
            os.unlink(dest)
        except OSError:
            pass
        subprocess.run(["umount", RAM_DIR], capture_output=True)
        _say("ERROR", f"Could not move the system to RAM: {e.strerror or e}")
        return 1
    _say("DONE", _release_medium())
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd == "status":
        print(json.dumps(status()))
        return 0
    if cmd == "run":
        if os.geteuid() != 0:
            _say("ERROR", "Load to RAM needs root.")
            return 1
        return run()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
