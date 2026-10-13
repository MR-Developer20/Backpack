# Backpack Live

[![ci](../../actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)

A bootable Debian 13 ("trixie") live USB for network discovery and testing — think
"Hiren's BootCD, but Linux with network tools." x86_64, BIOS and UEFI.

Two ways to use it, chosen from the boot menu:

- **GUI Mode** (default) — a full-screen, touch-friendly tile launcher (PySide6/QML under sway)
  that builds a form for each tool and streams its output. Every button shows the command it
  runs, and the line above the output is exactly what Run executes. Tools sit in tabs: **Network**
  (discovery, connectivity, capture, wireless, throughput, DNS/HTTP), **Data** (disks, recovery,
  files, transfer) and **Extra** (other software, such as the optional
  [eDEX-UI](https://github.com/GitSquared/edex-ui) sci-fi terminal; the tab only appears when
  something in it is installed). The **Settings** button (gear, top right) holds a UI size slider (0.75–1.6×,
  applies as you drag, remembered across boots with persistence), **Load to RAM** (moves the running
  system into memory so the stick can be unplugged, no reboot), **Switch to CLI Mode**, Reboot and
  Shut down; the last three ask once more inside the sheet before acting.
  A CPU/RAM meter in the top bar opens a system monitor with live graphs plus the CPU model,
  core count, RAM capacity and installed memory modules.
  Top bar: full-screen terminal, split view
  (one terminal beside the launcher, or below it in portrait; the button becomes "Exit split"),
  a phone-style on-screen keyboard and a Wi-Fi scan/connect overlay. When the launcher is narrow
  (split view, portrait, or a large UI size) the top bar collapses to icons.
- **CLI Mode** — boots to a multi-user console, no display server.

Each entry also has a **copy to RAM** (`toram`) variant that runs entirely from memory so the
USB stick can be removed after boot; the boot splash shows a progress bar while it copies.

## Screenshots

| Boot menu (UEFI) | Boot splash |
|---|---|
| ![boot menu](docs/screenshots/boot-menu-uefi.png) | ![boot splash](docs/screenshots/boot-splash.png) |

| GUI Mode — Network tab | Tool running |
|---|---|
| ![network tab](docs/screenshots/gui-network.png) | ![tool running](docs/screenshots/gui-tool-running.png) |

| Data tab | Settings |
|---|---|
| ![data tab](docs/screenshots/gui-data.png) | ![settings](docs/screenshots/gui-settings.png) |

| Wi-Fi | System monitor |
|---|---|
| ![wifi](docs/screenshots/gui-wifi.png) | ![system monitor](docs/screenshots/gui-monitor.png) |

| Portrait | eDEX-UI (Extra tab) |
|---|---|
| ![portrait](docs/screenshots/gui-portrait.png) | ![edex](docs/screenshots/edex-ui.png) |

## Tools

Discovery, connectivity, capture, wireless, throughput, and DNS/HTTP tools — nmap, arp-scan,
netdiscover, tcpdump, tshark/wireshark, iperf3, mtr, hping3, kismet, aircrack-ng, Angry IP
Scanner, and more. The full list with per-tool commands lives in
[`manifest/tools.yaml`](manifest/tools.yaml) and is installed on the image at
`/etc/backpack/tools.yaml`.

Default login: user **`user`**, password **`live`**, passwordless `sudo`.

## Build

The build runs `live-build` inside a privileged `debian:trixie` Docker container (the default),
so it works on any host with Docker. QEMU and OVMF are used from the host for testing.

```bash
make build          # -> build/backpack.iso   (full log: build/logs/build.log)
make test-bios      # boot the ISO in QEMU (BIOS) and wait for the in-guest self-test
make test-uefi      # same, UEFI (OVMF)
make test-persist   # persistence matrix (BIOS/UEFI x normal/toram)
make release        # staged ISO + SHA256SUMS in build/release/
```

Build on a native Debian/Ubuntu host without Docker by passing `USE_DOCKER=0` (needs
`live-build` >= 2023 and root). On Ubuntu this will not work — its `live-build` is a dead fork.

First build pulls ~1 GB of packages and takes roughly 8-12 minutes; later builds reuse the
package cache.

### eDEX-UI (optional)

The eDEX-UI tile in GUI Mode's Extra tab needs the `edex-ui` Debian package, built from the vendored and
modernized fork in `touchmode/edex/` (Electron 37). It is not built by `make build`; build it
once and it is picked up by the next `make build`:

```bash
docker build -t backpack-edex -f tools/docker/Dockerfile.edex tools/docker
scripts/build-edex-deb.sh        # -> live/config/packages.chroot/edex-ui_*.deb
```

Without it the image still builds; the tile (and the Extra tab, while eDEX-UI is its only entry) simply does not appear.

### Releases

Pushing a version tag builds everything on GitHub Actions (`.github/workflows/release.yml`) and
publishes a GitHub release with the ISO, the USB writer (`.deb` + AppImage) and `SHA256SUMS`:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Running the workflow by hand (Actions → release → Run workflow) builds the same files as
workflow artifacts without publishing. The release ISO is a plain `make build`, so it has no
eDEX-UI.

## Write to a USB stick

```bash
make mkusb DEV=/dev/sdX            # writes the ISO + a 5 GB persistence partition
make mkusb DEV=/dev/sdX SIZE=10G   # larger persistence
make mkusb DEV=/dev/sdX KEEP=1     # update the system only, keep the existing persistence
make mkusb-gui                     # same thing in a small GTK4 window (password via pkexec)
make usb-writer                    # package that window as build/dist/*.deb + AppImage
scripts/mkusb.sh --dry-run /dev/sdX   # print every command without touching the disk
```

`mkusb.sh` refuses disks larger than 256 GB without `--force`, refuses the running system disk,
and asks you to type the device name to confirm. **It erases the target disk.**

### Backpack USB Writer for Linux, Windows and macOS

Each release also carries a standalone writer, one file per system, styled like GUI Mode
(source: `tools/usb-writer/app`, Go + Wails):

| System | File | Notes |
| --- | --- | --- |
| Linux | `Backpack_USB_Writer-<ver>-linux-x86_64` | `chmod +x` and run; asks for your password (pkexec). Needs WebKitGTK 4.1 (`libwebkit2gtk-4.1-0`, stock on Ubuntu 22.04+ / Debian 12+ desktops). |
| Windows | `Backpack_USB_Writer-<ver>-windows-x86_64.exe` | Asks for Administrator when it opens. Uses the WebView2 runtime built into Windows 10/11. |
| macOS | `Backpack_USB_Writer-<ver>-macos-universal.zip` | Unzip, then right-click the app and choose Open the first time (it is not signed). Asks for an administrator password when writing. |

It writes the ISO, then creates the `persistence` partition itself (ext3 with the same
`persistence.conf`, so it works on systems without `mkfs.ext4`), or updates the system and keeps
an existing persistence partition. The same file is also a command-line writer:

```bash
backpack-usb-writer --list
sudo backpack-usb-writer --iso backpack-live-v1.2.0-amd64.iso --size 8G /dev/sdX     # Linux
sudo backpack-usb-writer --iso backpack.iso --keep-persistence /dev/disk4            # macOS
backpack-usb-writer.exe --iso backpack.iso --size 8G \\.\PhysicalDrive2              # Windows, as Administrator
```

It checks GitHub for a newer release when it opens. **Update to vX** downloads the writer for
your system, checks it against the release's `SHA256SUMS` and replaces the program (then
**Restart to finish**); **Download vX ISO** saves the release's ISO into Downloads and selects it.
From a terminal: `backpack-usb-writer --update` and `backpack-usb-writer --download-iso`.

Build it with `make usb-writer-app` (needs Go and, on Linux, `libgtk-3-dev libwebkit2gtk-4.1-dev`).

Without a checkout, you can also install the GTK **Backpack USB Writer** from a release: the `.deb`
(`sudo apt install ./backpack-usb-writer_*_all.deb`, then start it from the app menu) or the
AppImage (`chmod +x` and run). Both use the system's GTK 4, so the AppImage needs `python3-gi`
and `gir1.2-gtk-4.0` (stock on Ubuntu 24.04+ / Debian trixie desktops).

## Ventoy

Ventoy's normal and grub2 modes cannot load this image's kernel (`error: cannot load image`);
only Ventoy's **memdisk** mode works. `make ventoy` produces `build/ventoy-dist/` with the ISO
plus a `ventoy/ventoy.json` (`auto_memdisk`) that makes Ventoy boot it in memdisk mode
automatically — copy both to the Ventoy drive. Memdisk runs from RAM, so there is no
persistence that way; use a dedicated stick (`make mkusb`) for persistence. See `CLAUDE.md`
for the full diagnosis.

## Persistence

The writer adds a 5 GB ext4 partition labelled `persistence` holding a `persistence.conf` that
unions these directories across reboots (targeted, not a full `/` overlay):

- `/home` — your files and app settings
- `/var/lib/backpack` — tool data
- `/etc/NetworkManager` — saved network connections

Persistence works with the `toram` boot entries too. Boot with the `persistence` parameter
(already set by default). To wipe persistence, reformat or relabel that partition.

## Add a tool

Everything is driven by one file, `manifest/tools.yaml`. To add a tool:

1. Add an entry (schema is documented at the top of the file). Use `packages:` for a Debian
   package, or `source: {type: upstream, ...}` for an upstream `.deb` or apt repo.
2. Regenerate the package list and the installed manifest:

   ```bash
   make manifest      # rewrites live/config/package-lists/backpack.list.chroot
   ```

3. `make build`. For an upstream `.deb` or apt key, `make fetch` downloads and checksum-verifies
   it first (`make build` runs it automatically).

The same entry drives the GUI Mode tile, its input form, and this documentation — there is no
second place to edit.

## Boot menu entries

| Entry | Kernel parameters |
|---|---|
| GUI Mode *(default)* | `backpack.ui=touch` |
| CLI Mode | `systemd.unit=multi-user.target` |
| … copy to RAM | the above plus `toram` |

## Layout

See [`CLAUDE.md`](CLAUDE.md) for the repository layout, build internals, and notes.

## Licenses

This repository's own scripts, configuration and the GUI Mode app: see `LICENSE`.
The vendored eDEX-UI fork in `touchmode/edex/` is GPL-3.0 (its `LICENSE` file). The built
image packages Debian and third-party software under their respective licenses.
