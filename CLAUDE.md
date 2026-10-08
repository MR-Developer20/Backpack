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
touchmode/                     PySide6 Touch Mode app (phase 4)
build/                         ignored: ISO, logs, cache, test images
```

## Commands
```
make manifest      # regenerate package list + /etc/nettoolkit/tools.yaml include
make fetch         # download/verify upstream debs + keys
make build         # full ISO → build/nettoolkit.iso (log: build/logs/build.log)
make test-bios / test-uefi / test-persist
make mkusb DEV=/dev/sdX [SIZE=5G]
make release
```

## Gotchas log
- (phase 1) Ubuntu live-build unusable → Docker. Kismet has a trixie suite. ipscan deb depends
  on `openjdk-25-jre | openjdk-21-jre | java-runtime (>= 21)`; we ship openjdk-21-jre.
