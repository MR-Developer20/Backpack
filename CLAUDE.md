# NetToolkit Live — project notes for Claude sessions

Bootable Debian 13 (trixie) live USB with network discovery/testing tools. Spec and fixed
decisions: `/home/r3admin/Downloads/nettoolkit-claude-code-prompt.md`. Plan:
`~/.claude/plans/home-r3admin-downloads-nettoolkit-claud-streamed-rocket.md`.

## Decisions (fixed)
- Debian trixie amd64, `live-build`, zstd squashfs, `--apt-recommends false`, no installer.
- Desktop: LXQt + LightDM (X11). Touch Mode: PySide6/QML under sway (Wayland), `foot` terminal.
- Boot entries: Terminal / Desktop / Touch Mode, each also as `toram`. Touch = `nettoolkit.ui=touch`.
- Persistence: 5 GB ext4 labelled `persistence`, targeted dirs `/home /var/lib/nettoolkit /etc/NetworkManager`.
- Upstream: Kismet apt repo (trixie suite exists), Angry IP Scanner `.deb` 3.10.0 + `openjdk-21-jre`.

## Build host (this machine)
- Ubuntu 25.10. Its `live-build` is the ancient 3.0 fork → **Docker path**: `Dockerfile`
  (debian:trixie + live-build), run `--privileged`. `USE_DOCKER=1` is the Makefile default.
- `sudo` needs a password: run privileged things via the user's terminal panel, not Bash.
- QEMU + OVMF run on the host: `/usr/share/OVMF/OVMF_CODE_4M.fd`, `OVMF_VARS_4M.fd`.
- User is in the `docker` group (added at install; use `sg docker -c '…'` if the login shell predates it).

## Layout
```
manifest/tools.yaml            single source of truth for tools (schema in file header)
scripts/gen-package-list.py    validate YAML → live/config/package-lists/nettoolkit.list.chroot
scripts/check-tools.sh         command -v for every manifest cmd; prints MISSING: lines
scripts/fetch-upstream.sh      upstream .debs → live/config/packages.chroot, keys → config/archives
scripts/test-qemu.sh           boot ISO in QEMU (BIOS/UEFI/direct-kernel), waits for selftest marker
scripts/mkusb.sh               write USB or test image + persistence partition
live/auto/{config,build,clean} live-build config
touchmode/                     PySide6/QML Touch Mode app + sway config + session files (phase 4)
scripts/build-touchmode-deb.sh dpkg-deb -> live/config/packages.chroot/nettoolkit-touch_*.deb (run by make build)
build/                         ignored: ISO, logs, cache, test images
```

## Commands
```
make manifest      # regenerate package list + /etc/nettoolkit/tools.yaml include
make fetch         # download/verify upstream debs + keys
make build         # full ISO → build/nettoolkit.iso (log: build/logs/build.log)
make test-bios / test-uefi / test-persist
make mkusb DEV=/dev/sdX [SIZE=5G]   # sudo; refuses disks > 256G without --force
make test-usb-img                  # build/test-usb.img (8G sparse) with persistence partition
make release
```

## Gotchas log
- (phase 1) Ubuntu live-build unusable → Docker. Kismet has a trixie suite. ipscan deb depends
  on `openjdk-25-jre | openjdk-21-jre | java-runtime (>= 21)`; we ship openjdk-21-jre.
- (phase 2) Run docker via `sg docker -c '...'` until the shell has the docker group. Never
  poll a status file you are about to delete: `rm` it BEFORE starting the monitor.
- live-build 20250505 script names have no `lb_` prefix (/usr/lib/live/build/<name>). Archives
  accept `*.list` + `*.key`; preseed `*.cfg(.chroot)`; includes.chroot is applied before hooks.
- Kismet's HTTPS repo needs ca-certificates inside the bootstrap: `--debootstrap-options
  "--variant=minbase --include=ca-certificates,gnupg"`. Changing bootstrap options requires
  deleting `live/cache/bootstrap` (root-owned; remove via a docker run).
- `.dockerignore` excludes `live/` and `build/` (root-owned cache breaks `docker build`).
- BIOS menu is syslinux/isolinux (template has `timeout 0`; overridden in
  `live/config/bootloaders/{isolinux,syslinux}/`). UEFI menu is GRUB (`bootloaders/grub-pc/grub.cfg`).
- Do NOT re-run `lb binary` alone: it re-enters the chroot and apt breaks (apt-utils/apt version skew). Use `make clean build` (package cache in live/cache makes it ~8 min).
- QEMU: `scripts/test-qemu.sh [--uefi] [--headless] [--direct --append "..."] [--disk IMG] [--touch]`;
  serial log `build/logs/serial-<tag>.log`, screenshots `build/shots/<tag>.png`. Selftest unit
  (`nettoolkit-selftest`, VM-only, writes to ttyS0) prints BOOTTIME / TOOLS / MISSING / PERSIST-MARKER-*.
- `--apt-recommends false` drops live-config's Recommends: **`user-setup` is required** or the
  live user is never created (LightDM then shows a greeter, nothing autologs in). base.list.chroot
  lists it explicitly. Debug a running VM without rebuilding: `scripts/test-qemu.sh --keep-alive 150`
  in the background, then `scripts/qemu-type.sh 'cmd > /dev/ttyS0\n'` (switch tty with
  `echo "sendkey ctrl-alt-f2" | socat - UNIX-CONNECT:build/qemu-mon.sock`).
- (phase 3) ISO is an MBR isohybrid (p1 = ISO9660, p2 = EFI nested inside p1); `sfdisk --append`
  adds p3. Image mode formats via `mkfs.ext4 -E offset=... -d <dir>` so no root/loop needed.
  live-boot finds the `persistence`-labelled partition on any disk, including with `toram`.
  `scripts/test-persist.sh` = 6 boots (bios/uefi x normal,normal,toram) on a fresh image.
- (phase 4) Touch Mode = `nettoolkit-touch` deb: python package in /usr/lib/python3/dist-packages,
  `/usr/bin/nettoolkit-touch-session` (sway -c /etc/nettoolkit/sway.config), wayland-sessions
  entry `nettoolkit-touch`, unit `nettoolkit-ui.service` (ConditionKernelCommandLine
  nettoolkit.ui=touch) writes lightdm.conf.d/60-nettoolkit-touch.conf before lightdm starts.
  Test the app without an ISO: `docker run ... nettoolkit-qt` (build/tmpl/Dockerfile.qt) with
  QT_QPA_PLATFORM=offscreen NETTOOLKIT_DEMO=<tool-id> NETTOOLKIT_SCREENSHOT=<png>
  NETTOOLKIT_MANIFEST=manifest/tools.yaml PYTHONPATH=touchmode. In QEMU: `make test-touch`
  (kernel params nettoolkit.ui=touch + nettoolkit.demo=<id> auto-open and run a tool).
  Manifest extras: `tty: true` (run in foot), `sep: ""` (join flag+value), `gui: true`.
- (phase 4 debug) sway config: `{ ... }` blocks (bar, input) MUST be multi-line; a one-line
  `bar { mode invisible }` makes sway report "Error(s) loading config!" (the `}` is unmatched).
  Validate inside a running session: `swaymsg exec 'sway -d -C -c FILE 2>&1 | grep config.c'`
  (`sway -C` from a plain tty fails on seat/tty permissions, not a config error).
- QEMU input injection for Touch Mode tests:
  * harness adds `-machine vmport=off` in `--touch` so the virtio tablet keeps absolute focus;
  * `--console` (with `--direct`) puts a getty on a serial *socket* — `scripts/qemu-serial.sh
    --login` then `scripts/qemu-serial.sh 'cmd'` runs commands in-guest, output in the serial log;
  * reliable tap = `scripts/qemu-tap.sh --sway X Y` (swaymsg cursor set/press/release in-guest).
    Hardware tablet taps via the monitor are flaky under nested virt; not a product defect —
    libinput enumerates the touch device under sway, so real touchscreens deliver events.
  * `scripts/qemu-shot.sh NAME` screendumps to build/shots/NAME.png.
- (phase 5) Branding + splash: assets generated in branding/ (ImageMagick via nettoolkit-edex),
  staged into includes.chroot (wallpaper -> /usr/share/backgrounds/nettoolkit.png + LXQt skel,
  greeter bg via lightdm-gtk-greeter.conf.d, /etc/issue + /etc/motd). Boot menus branded:
  syslinux stdmenu.cfg colors + splash.png + "NetToolkit Live" title; GRUB background_image.
  Plymouth theme "nettoolkit" (script module, splash.png) set in hook 0300 + update-initramfs.
  Plymouth cost: +74 MiB (plymouth-label pulls pango/cairo/fonts) but **no boot-time regression**
  (BIOS desktop 21.1s vs 21.4s before). `splash` added to bootappend.
- `make release` -> build/release/nettoolkit-live-<UTCdate>-amd64.iso + SHA256SUMS (scripts/release.sh).
- Final ISO: 1023 MiB (target < 1.5 GB). README.md documents build/test/USB/add-a-tool/persistence.

- (ventoy diagnosis) Reproduced the user's failure with REAL Ventoy 1.1.17 in QEMU UEFI.
  Per Ventoy boot mode: Normal mode FAILS ("error: cannot load image / you need to load the
  kernel first"); Grub2 mode FAILS (guest resets); Memdisk mode BOOTS to the desktop.
  Root cause: Ventoy's bundled GRUB cannot load the Debian trixie kernel's EFI image; memdisk
  loads the whole ISO to RAM and uses the ISO's own bootloader. Not an ISO defect (direct boot
  and `make mkusb` work). Repro tooling: build/tmpl/make-ventoy-usb.sh (+ ventoy-copy4.sh).
  QEMU needs -m 2G here (host ~3 GB free).
