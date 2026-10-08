# NetToolkit Live

A bootable Debian 13 ("trixie") live USB for network discovery and testing — think
"Hiren's BootCD, but Linux with network tools." x86_64, BIOS and UEFI.

Three ways to use it, chosen from the boot menu:

- **Desktop (LXQt)** — a full graphical desktop with NetworkManager and the tools installed.
- **Terminal** — boots to a multi-user console, no X.
- **Touch Mode** — a full-screen, touch-friendly tile launcher (PySide6/QML under sway) that
  builds a form for each tool and streams its output. Includes a terminal, split view, and an
  optional [eDEX-UI](https://github.com/GitSquared/edex-ui) sci-fi terminal.

Each entry also has a **copy to RAM** (`toram`) variant that runs entirely from memory so the
USB stick can be removed after boot.

## Tools

Discovery, connectivity, capture, wireless, throughput, and DNS/HTTP tools — nmap, arp-scan,
netdiscover, tcpdump, tshark/wireshark, iperf3, mtr, hping3, kismet, aircrack-ng, Angry IP
Scanner, and more. The full list with per-tool commands lives in
[`manifest/tools.yaml`](manifest/tools.yaml) and is installed on the image at
`/etc/nettoolkit/tools.yaml`.

Default login: user **`user`**, password **`live`**, passwordless `sudo`.

## Build

The build runs `live-build` inside a privileged `debian:trixie` Docker container (the default),
so it works on any host with Docker. QEMU and OVMF are used from the host for testing.

```bash
make build          # -> build/nettoolkit.iso   (full log: build/logs/build.log)
make test-bios      # boot the ISO in QEMU (BIOS) and wait for the in-guest self-test
make test-uefi      # same, UEFI (OVMF)
make test-persist   # persistence matrix (BIOS/UEFI x normal/toram)
make release        # staged ISO + SHA256SUMS in build/release/
```

Build on a native Debian/Ubuntu host without Docker by passing `USE_DOCKER=0` (needs
`live-build` >= 2023 and root). On Ubuntu this will not work — its `live-build` is a dead fork.

First build pulls ~1 GB of packages and takes roughly 8-12 minutes; later builds reuse the
package cache.

## Write to a USB stick

```bash
make mkusb DEV=/dev/sdX            # writes the ISO + a 5 GB persistence partition
make mkusb DEV=/dev/sdX SIZE=10G   # larger persistence
scripts/mkusb.sh --dry-run /dev/sdX   # print every command without touching the disk
```

`mkusb.sh` refuses disks larger than 256 GB without `--force`, refuses the running system disk,
and asks you to type the device name to confirm. **It erases the target disk.**

## Persistence

The writer adds a 5 GB ext4 partition labelled `persistence` holding a `persistence.conf` that
unions these directories across reboots (targeted, not a full `/` overlay):

- `/home` — your files and app settings
- `/var/lib/nettoolkit` — tool data
- `/etc/NetworkManager` — saved network connections

Persistence works with the `toram` boot entries too. Boot with the `persistence` parameter
(already set by default). To wipe persistence, reformat or relabel that partition.

## Add a tool

Everything is driven by one file, `manifest/tools.yaml`. To add a tool:

1. Add an entry (schema is documented at the top of the file). Use `packages:` for a Debian
   package, or `source: {type: upstream, ...}` for an upstream `.deb` or apt repo.
2. Regenerate the package list and the installed manifest:

   ```bash
   make manifest      # rewrites live/config/package-lists/nettoolkit.list.chroot
   ```

3. `make build`. For an upstream `.deb` or apt key, `make fetch` downloads and checksum-verifies
   it first (`make build` runs it automatically).

The same entry drives the Touch Mode tile, its input form, and this documentation — there is no
second place to edit.

## Boot menu entries

| Entry | Kernel parameters |
|---|---|
| Desktop (LXQt) | *(default)* |
| Terminal | `systemd.unit=multi-user.target` |
| Touch Mode | `nettoolkit.ui=touch` |
| … copy to RAM | the above plus `toram` |

## Layout

See [`CLAUDE.md`](CLAUDE.md) for the repository layout, build internals, and notes.

## Licenses

NetToolkit Live packages third-party software under their own licenses. The vendored eDEX-UI
fork is GPL-3.0 (see `touchmode/edex/LICENSE`).
