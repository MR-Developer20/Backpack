# Backpack Live — Claude Code build prompt

Build a bootable Debian live USB for network discovery/testing ("Hiren's BootCD, but Linux + network tools"). Work phase by phase in the order below. Stop at each phase gate and wait for my approval before continuing.

## Decisions (fixed — do not re-research or propose alternatives)
- Base: Debian 13 "trixie", built with `live-build`. x86_64 only. Raspberry Pi is out of scope.
- Desktop mode: LXQt + LightDM (X11).
- Touch Mode: PySide6 / Qt Quick (QML) tile launcher, run as its own Wayland session under **sway** with a locked-down config (tiling gives split-screen). Terminal button spawns `foot`. Later phase: fork and modernize eDEX-UI as an optional full-screen view launched from Touch Mode.
- Boot menu entries: Terminal (`systemd.unit=multi-user.target`), Desktop (LXQt), Touch Mode, plus a "copy to RAM" (`toram`) variant of each.
- Squashfs compression: zstd. `--apt-recommends false`. No LibreOffice, no installer, no task-* metapackages.
- Persistence: ~5 GB ext4 partition labelled `persistence` with `persistence.conf`. Targeted entries (`/home`, `/var/lib/backpack`, `/etc/NetworkManager`), not `/ union`. Boot param `persistence`.
- Tools (Debian packages unless noted): nmap zenmap arp-scan netdiscover lldpd mtr-tiny fping iperf3 bind9-dnsutils curl tcpdump tshark wireshark ethtool wpasupplicant socat netcat-openbsd ngrep hping3 iftop nload bmon speedtest-cli aircrack-ng. Kismet from the upstream Kismet apt repo. Angry IP Scanner from the upstream `.deb` (needs a JRE ≥ 21; include `openjdk-21-jre`).

## Token rules (apply throughout)
- Minimal prose. No restating the task, no explaining what I already decided.
- Never print full build logs or large files. Use `tail -n 40`, `grep`, or write logs to `build/logs/` and report only pass/fail plus the relevant lines.
- Don't read a file you just wrote. Don't re-read unchanged files.
- One commit per phase with a short message. Keep a `CLAUDE.md` at repo root with decisions, repo layout, and build/test commands so later sessions skip discovery.
- Ask only when blocked on a decision that is mine; otherwise pick the conventional default and note it in one line.
- Phase gate report format: 3–6 bullet lines (what was built, how it was verified, open issues).

## Environment
- Build host must be Debian/Ubuntu with root (`live-build`, `debootstrap`, `squashfs-tools`, `xorriso`, `qemu-system-x86`, `ovmf`). If not on such a host, create a `Dockerfile` for a privileged `debian:trixie` build container and a `make` wrapper; verify that path works before anything else.
- Test every ISO in QEMU, both BIOS and UEFI (OVMF), with a test persistence disk image. Script this (`scripts/test-qemu.sh`); don't do it by hand.

## Repo layout
```
backpack/
  CLAUDE.md
  Makefile                 # build, clean, test-bios, test-uefi, mkusb
  manifest/tools.yaml      # phase 1
  live/                    # live-build config tree (auto/, config/)
  touchmode/               # phase 4 PySide6 app
  scripts/                 # mkusb.sh, test-qemu.sh, helpers
  build/                   # ignored output
```

## Phase 1 — Tool manifest
Create `manifest/tools.yaml`. One entry per tool: `id`, `name`, `description` (one sentence, plain English), `category` (discovery / connectivity / capture / wireless / throughput / dns-http), `packages` (Debian names) or `source: upstream` with URL, `commands`: list of `{label, cmd, args: [{name, type, default, required}], needs_root}`. This file drives the apt package list, Touch Mode tiles, and docs. Generate `live/config/package-lists/backpack.list.chroot` from it with a script; don't hand-maintain both.
Gate: show the YAML schema and two example entries, not the whole file.

## Phase 2 — Minimal live image
`lb config` in `live/auto/config` with: trixie, amd64, `--chroot-squashfs-compression-type zstd`, `--apt-recommends false`, `--debian-installer none`, `--bootappend-live "boot=live components quiet persistence"`, firmware packages for common laptop NICs/Wi-Fi (`firmware-linux`, `firmware-iwlwifi`, `firmware-realtek`, `firmware-atheros`). Packages: tool list from phase 1 + LXQt core + LightDM + NetworkManager + `foot`. Add Kismet repo and Angry IP Scanner `.deb` via `config/hooks/` or `config/packages.chroot/`. Mask unneeded units (ModemManager, cups, apt-daily timers, bluetooth off by default). Add the boot menu entries listed above for both GRUB (UEFI) and syslinux (BIOS).
Verify: ISO size, `systemd-analyze` time in QEMU, all tools present (`scripts/check-tools.sh` reads the manifest and runs `command -v` for each). Target < 1.5 GB.
Gate: sizes, boot time, missing tools, any package not in trixie.

## Phase 3 — Persistence + USB writer
`scripts/mkusb.sh <device>`: writes the ISO hybrid image, creates a 5 GB ext4 partition labelled `persistence` with `persistence.conf`, with a `--size` override. Include a dry-run mode and a device sanity check (refuse disks > 256 GB unless `--force`). Verify in QEMU that a file in `/home` survives reboot and that the `toram` entries still see persistence.
Gate: test results only.

## Phase 4 — Touch Mode
4a. `touchmode/` PySide6 + QML app: tile grid by category, large touch targets, each tile opens a form built from the manifest's `args`, runs the command, streams output into a pane. Buttons: open terminal (`foot`), split view (sway keybind + on-screen button), shutdown/reboot. Runs full-screen. Reads `/etc/backpack/tools.yaml` (installed from the manifest).
4b. sway config: no title bars, no floating, tiling only, bar hidden, keybindings for split/focus/close, `foot` as terminal, autostart the launcher. Install as a Wayland session `.desktop` so LightDM lists "Touch Mode"; the boot entry selects it via a kernel param (`backpack.ui=touch`) handled by a small systemd unit that sets LightDM autologin + session.
4c. eDEX-UI: clone `GitSquared/edex-ui` (archived Oct 2021) into `touchmode/edex/` as a git submodule or vendored fork, update Electron/Node deps to current, fix breakage, add a touch-friendly layout tweak, package so Touch Mode can launch it full-screen and return. If updating Electron proves disproportionate, stop and report the effort estimate before continuing.
Verify in QEMU with a virtual touchscreen (`-device virtio-tablet`). Package the app as a Debian package built in a hook so it lands in the image.
Gate: screenshot per view, package size impact on the ISO.

## Phase 5 — Polish
Boot splash, consistent branding "Backpack Live", `CLAUDE.md` + `README.md` (build, test, write-to-USB, add a tool), `make release` that outputs the ISO plus SHA256.
