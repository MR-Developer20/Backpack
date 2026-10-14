# Backpack Live — project notes for Claude sessions

Bootable Debian 13 (trixie) live USB with network discovery/testing tools. The original
build spec with the fixed decisions is `docs/SPEC.md`. User-facing docs: `README.md`.

## Decisions (fixed)
- Debian trixie amd64, `live-build`, zstd squashfs, `--apt-recommends false`, no installer.
- Two modes. **GUI Mode** (default): PySide6/QML tile launcher under sway (Wayland) in a LightDM
  autologin session, `foot` terminal. **CLI Mode**: `systemd.unit=multi-user.target`, no display server.
  The LXQt/X11 "Desktop" mode was removed (no xserver-xorg; GUI tools run via xwayland).
- Boot entries: GUI Mode / CLI Mode, each also as `toram`. GUI = `backpack.ui=touch` (the kernel
  param, the `backpack-touch` deb, the `backpack-touch` session and `touchmode/` keep the old
  internal "touch" name; only the user-facing label changed).
- Persistence: 5 GB ext4 labelled `persistence`, targeted dirs `/home /var/lib/backpack /etc/NetworkManager`.
- Upstream: Kismet apt repo (trixie suite exists), Angry IP Scanner `.deb` 3.10.0 + `openjdk-21-jre`.

## Build host notes (the machine this was developed on; adapt as needed)
- Ubuntu 25.10. Its `live-build` is the ancient 3.0 fork → **Docker path**: `Dockerfile`
  (debian:trixie + live-build), run `--privileged`. `USE_DOCKER=1` is the Makefile default.
- `sudo` needs a password: run privileged things via the user's terminal panel, not Bash.
- QEMU + OVMF run on the host: `/usr/share/OVMF/OVMF_CODE_4M.fd`, `OVMF_VARS_4M.fd`.
- User is in the `docker` group (added at install; use `sg docker -c '…'` if the login shell predates it).

## Layout
```
manifest/tools.yaml            single source of truth for tools (schema in file header)
scripts/gen-package-list.py    validate YAML → live/config/package-lists/backpack.list.chroot
scripts/check-tools.sh         command -v for every manifest cmd; prints MISSING: lines
scripts/fetch-upstream.sh      upstream .debs → live/config/packages.chroot, keys → config/archives
scripts/test-qemu.sh           boot ISO in QEMU (BIOS/UEFI/direct-kernel), waits for selftest marker
scripts/mkusb.sh               write USB or test image + persistence partition
live/auto/{config,build,clean} live-build config
touchmode/                     PySide6/QML GUI Mode app + sway config + session files (phase 4)
scripts/build-touchmode-deb.sh dpkg-deb -> live/config/packages.chroot/backpack-touch_*.deb (run by make build)
build/                         ignored: ISO, logs, cache, test images
```

## Commands
```
make manifest      # regenerate package list + /etc/backpack/tools.yaml include
make fetch         # download/verify upstream debs + keys
make build         # full ISO → build/backpack.iso (log: build/logs/build.log)
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
- `lb config` symlinks live-build's own hooks into `live/config/hooks/{live,normal}/` (targets under
  /usr/share/live/build, which only exists in the container). They are gitignored: tracking them
  dangles on every other host and broke CI's syntax loop. Project hooks are `0xxx-*.hook.chroot`.
- `.dockerignore` excludes `live/` and `build/` (root-owned cache breaks `docker build`).
- BIOS menu is syslinux/isolinux (template has `timeout 0`; overridden in
  `live/config/bootloaders/{isolinux,syslinux}/`). UEFI menu is GRUB (`bootloaders/grub-pc/grub.cfg`).
- Do NOT re-run `lb binary` alone: it re-enters the chroot and apt breaks (apt-utils/apt version skew). Use `make clean build` (package cache in live/cache makes it ~8 min).
- QEMU: `scripts/test-qemu.sh [--uefi] [--headless] [--direct --append "..."] [--disk IMG] [--touch]`;
  serial log `build/logs/serial-<tag>.log`, screenshots `build/shots/<tag>.png`. Selftest unit
  (`backpack-selftest`, VM-only, writes to ttyS0) prints BOOTTIME / TOOLS / MISSING / PERSIST-MARKER-*.
- `--apt-recommends false` drops live-config's Recommends: **`user-setup` is required** or the
  live user is never created (LightDM then tries the greeter, nothing autologs in). base.list.chroot
  lists it explicitly. Debug a running VM without rebuilding: `scripts/test-qemu.sh --keep-alive 150`
  in the background, then `scripts/qemu-type.sh 'cmd > /dev/ttyS0\n'` (switch tty with
  `echo "sendkey ctrl-alt-f2" | socat - UNIX-CONNECT:build/qemu-mon.sock`).
- (phase 3) ISO is an MBR isohybrid (p1 = ISO9660, p2 = EFI nested inside p1); `sfdisk --append`
  adds p3. Image mode formats via `mkfs.ext4 -E offset=... -d <dir>` so no root/loop needed.
  live-boot finds the `persistence`-labelled partition on any disk, including with `toram`.
  `scripts/test-persist.sh` = 6 boots (bios/uefi x normal,normal,toram) on a fresh image.
- (phase 4) GUI Mode (was "Touch Mode") = `backpack-touch` deb: python package in /usr/lib/python3/dist-packages,
  `/usr/bin/backpack-touch-session` (sway -c /etc/backpack/sway.config), wayland-sessions
  entry `backpack-touch`, unit `backpack-ui.service` (ConditionKernelCommandLine
  backpack.ui=touch) writes lightdm.conf.d/60-backpack-touch.conf before lightdm starts.
  Test the app without an ISO: `docker run ... backpack-qt` (tools/docker/Dockerfile.qt) with
  QT_QPA_PLATFORM=offscreen BACKPACK_DEMO=<tool-id> BACKPACK_SCREENSHOT=<png>
  BACKPACK_MANIFEST=manifest/tools.yaml PYTHONPATH=touchmode. In QEMU: `make test-touch`
  (kernel params backpack.ui=touch + backpack.demo=<id> auto-open and run a tool).
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
- (phase 5) Branding + splash: tools/assets/gen-branding.sh (ImageMagick + python3, run from the repo root) writes the
  Backpack Field Terminal wallpaper (JetBrains Mono, dragon curve from tools/assets/dragon.py) and plymouth art straight
  into includes.chroot (wallpaper -> /usr/share/backgrounds/backpack.png, greeter bg via
  lightdm-gtk-greeter.conf.d, /etc/issue + /etc/motd; the LXQt skel went with Desktop mode). Boot menus branded:
  syslinux stdmenu.cfg colors + splash.png + "Backpack Live" title; GRUB background_image.
  Plymouth theme "backpack" (script module, splash.png) set in hook 0300 + update-initramfs.
  Plymouth cost: +74 MiB (plymouth-label pulls pango/cairo/fonts) but **no boot-time regression**
  (BIOS desktop 21.1s vs 21.4s before). `splash` added to bootappend.
- `make release` -> build/release/backpack-live-<UTCdate>-amd64.iso + SHA256SUMS (scripts/release.sh).
- Final ISO: 1023 MiB (target < 1.5 GB). README.md documents build/test/USB/add-a-tool/persistence.

- (ventoy diagnosis) Reproduced the user's failure with REAL Ventoy 1.1.17 in QEMU UEFI.
  Per Ventoy boot mode: Normal mode FAILS ("error: cannot load image / you need to load the
  kernel first"); Grub2 mode FAILS (guest resets); Memdisk mode BOOTS to the desktop.
  Root cause: Ventoy's bundled GRUB cannot load the Debian trixie kernel's EFI image; memdisk
  loads the whole ISO to RAM and uses the ISO's own bootloader. Not an ISO defect (direct boot
  and `make mkusb` work). Repro tooling: tools/ventoy/make-ventoy-usb.sh (+ copy-iso-to-ventoy-img.sh).
  QEMU needs -m 2G here (host ~3 GB free).

- (ventoy variant) `make ventoy` (scripts/make-ventoy-iso.sh) strips the `persistence` boot param
  from grub.cfg + isolinux/live.cfg and repacks build/backpack.iso -> build/backpack-ventoy.iso
  via `xorriso -boot_image any replay` (seconds, no full rebuild; El Torito/isohybrid preserved).
  For Ventoy use (memdisk mode); does NOT fix Ventoy normal/grub2 mode (that is the Ventoy GRUB
  vs trixie-kernel issue). Verified: boot structure identical to the source ISO; BIOS boot runs.

- (modes) Desktop (LXQt) mode removed; "Terminal" -> "CLI Mode", "Touch Mode" -> "GUI Mode".
  `desktop.list.chroot` is gone; `gui.list.chroot` (was touch.list.chroot) carries sway/Qt/foot plus
  `lightdm` + `lightdm-gtk-greeter` (lightdm Depends on a greeter; it never shows with autologin).
  lightdm.conf.d/50-backpack.conf autologs straight into `backpack-touch`; `backpack-ui.service`
  still writes 60-backpack-touch.conf on `backpack.ui=touch` (harmless duplicate, keeps selftest
  TOUCH-CONF + `backpack.demo=` working). Selftest prints GUI-SESSION instead of DESKTOP-SESSION.
  Not rebuilt/booted in this change: verify with `make clean build && make test-bios test-touch`.
- (ventoy SOLUTION) `make ventoy` (scripts/make-ventoy-iso.sh) now produces build/ventoy-dist/:
  the persistence-stripped ISO + `ventoy/ventoy.json` with Ventoy's **auto_memdisk** plugin
  (`{"auto_memdisk":["/backpack-ventoy.iso"]}`) + README-VENTOY.txt. The user copies BOTH to
  the Ventoy drive root; Ventoy then boots this ISO straight into memdisk mode (no manual menu),
  which is the only mode that loads the trixie kernel. VERIFIED in real Ventoy 1.1.17 (QEMU UEFI):
  selecting the ISO goes directly to "memdisk mode boot ... Loading ISO file to memory"; memdisk
  then boots the live system (SELFTEST-DONE confirmed separately). Full combined boot needs
  guest RAM for a 1 GB ISO-to-RAM load (fine on real HW; this host's ~3 GB free is marginal).
  Ventoy repro tooling: tools/ventoy/ (make-ventoy-usb.sh, add-auto-memdisk-json.sh, loopback-emul.sh).

- (touch mode v2) Top bar is responsive: `compact` (now measured, see "command lines on buttons") collapses the tool buttons to
  icon-only (the top-bar icons are vector glyphs in touchmode/backpack_touch/qml/Icon.qml:
  QtQuick.Shapes, 24-unit SVG paths scaled in JS with pixel snapping, named via TouchButton's `icon.name`;
  no PNGs are shipped); Reboot/Shutdown are always icon-only; the
  "Touch Mode" subtitle needs >= 1400 px. `portrait` (height > width) stacks tiles over the tool
  pane (GridLayout columns 1) and makes Split use `splitv` (terminal BELOW) instead of `splith`.
  Split is single-instance: foot is launched with `--app-id backpack-split`; System polls
  `swaymsg -t get_tree` every 1.5 s for that app_id, so the button reads "Exit split" (kills it)
  and reverts if the user closes the terminal themselves. Terminal button = fullscreen foot
  (`--app-id backpack-term`, sway `for_window ... fullscreen enable`); `exit` returns.
  On-screen keyboard = `wvkbd-mobintl` started hidden by sway.config; SIGUSR2 shows / SIGUSR1
  hides (System.showKeyboard/hideKeyboard); text fields call showKeyboard on focus. It uses the
  wlroots virtual-keyboard protocol so it types into foot/eDEX too (it is NOT a Qt IM).
  Wi-Fi overlay (WifiOverlay.qml + Wifi QObject) drives `nmcli` async: scan (-t fields
  IN-USE,SSID,SIGNAL,SECURITY), connect (dev wifi connect SSID password PW), disconnect, forget.
  Test hooks: BACKPACK_SIZE=WxH (offscreen window size), BACKPACK_DEMO_WIFI=1 (open overlay).
- (toram progress) includes.chroot/lib/live/boot/9990-toram-todisk.sh overrides live-boot's copy:
  `backpack_copy_progress` runs `cp -a` in the background and polls `du -sk` of the tmpfs,
  sending `plymouth message --text=toram:<pct>` once per percent; the backpack plymouth theme
  draws those as a bar (bar.png/barbg.png scaled) + "Copying to memory NN%". Non-toram messages
  still render as text. Verify with scripts/test-toram-progress.sh (frames in build/shots/toram-*.png).
  The override must be re-derived if live-boot's script changes (it is a patched copy).

- (repo layout for GitHub) `tools/docker/` = Dockerfile.qt (offscreen Qt tests), Dockerfile.edex
  (Node/Electron toolchain) + edex-deb.sh; `tools/ventoy/` = real-Ventoy reproduction scripts;
  `tools/assets/` = icon/branding generators; `docs/SPEC.md` = original spec; `docs/screenshots/`.
  The eDEX fork source is tracked (its node_modules/dist/prebuild-src and upstream screenshots are
  not); rebuild its deb with scripts/build-edex-deb.sh. CI (.github/workflows/ci.yml) validates
  the manifest, syntax, and that the touch deb builds — it does not build the ISO.
- (touch mode v2 verified, QEMU) landscape icon+label bar; keyboard shows and the launcher shrinks
  above it; Wi-Fi overlay opens (VM has no Wi-Fi adapter, so scan/connect are untested on real HW);
  split tiles foot beside (640/640) and Exit split restores; portrait boot
  (`QEMU_RES=800x1280 scripts/test-qemu.sh --touch ...`) stacks the panes and split puts foot
  BELOW (800x640 each); copy-to-RAM shows the plymouth bar (frames at 64% and 100%).
  Don't put `pkill ... qemu-system` at the top of a Bash call that also starts a VM: its non-zero
  exit (no process) or the kill aborts the rest of the call. Kill in a separate call.
- (gui tabs + settings) Manifest categories are grouped into GUI tabs by `SECTIONS` in
  touchmode/backpack_touch/manifest.py: Network = the six network categories, Data = `disks`,
  `recovery`, `files`, `transfer` (also listed in scripts/gen-package-list.py CATEGORIES). Reboot/
  Shutdown moved from the top bar into SettingsSheet.qml (gear button). Settings QObject
  (settings.py): `uiScale` 0.75–1.6 saved to ~/.config/backpack/gui.json and bound to
  `Theme.scale`; every size in QML comes from Theme (`Theme.s(px)`), and `compact` triggers at
  `width < Theme.s(1100)`. **Load to RAM** = `sudo -n python3 -m backpack_touch.toram run`: copies
  the squashfs behind live-boot's read-only loop device into a tmpfs at /run/backpack-ram, swaps the
  loop's backing file with the LOOP_CHANGE_FD ioctl (same size + RO loop required), then unmounts
  /run/live/medium; a persistence partition on the stick keeps it busy (message says so). Verified
  with a real squashfs loop mount in a container (data intact after deleting the original file);
  not yet run on a booted ISO. `toram status` (JSON) works unprivileged; with boot-time `toram`
  the image already sits on tmpfs, so the button reads "Running from RAM". **Switch to CLI Mode**
  = `sudo -n sh -c 'systemctl isolate multi-user.target && chvt 1'` (untested on the ISO).
  Test hooks: BACKPACK_UI_SCALE, BACKPACK_DEMO_SETTINGS=1, BACKPACK_DEMO_SECTION=data.
- (system monitor) sysmon.py SysMonitor samples /proc/stat + /proc/meminfo every 1 s (60-sample
  history) for UsageMeter.qml (top bar, hidden below Theme.s(720) wide) and SysMonitorSheet.qml
  (UsageGraph.qml Canvas graphs). CPU model/cores from /proc/cpuinfo; RAM modules from
  `sudo -n dmidecode -t 17` (dmidecode added to gui.list.chroot + deb Depends), parsed by
  parse_dmidecode_memory (empty slots skipped). Adding the meter moved `compact` to
  width < Theme.s(1400). Test hook: BACKPACK_DEMO_MONITOR=1.
- (extra tab) The eDEX top-bar button is gone; eDEX-UI is the `edex-ui` manifest tool in category
  `extra` (Extra tab; app tiles show only an Open button, no form or output), marked `optional: true` with `packages: []`: manifest.load() drops optional
  tools whose command is missing (so the tab disappears without the deb) and `--print-cmds` /
  check-tools.sh skip them. GUI tools now launch via `sh -c "swaymsg fullscreen disable; exec …"`
  like the terminal buttons.
  LTris (Debian `ltris`, GPL-2+, cmd `/usr/games/ltris` since /usr/games may be off the session PATH)
  and GNOME Web (Debian `epiphany-browser`, GPL-3+, WebKitGTK, Wayland-native) are regular Extra tools, so the tab shows even when the eDEX deb was not built (make build and
  release.yml don't build it). Both float and resize (sway.config for_window: LTris centred at its own
  size by X11 class, GNOME Web app_id org.gnome.Epiphany filling the screen, floating not `fullscreen` so its address bar stays; a 6px acid/hull border to drag,
  floating_modifier $mod normal); not yet checked on a booted ISO.
- (backpack field terminal look) GUI Mode is styled after Marc's "Backpack Field Terminal" design
  system (https://claude.ai/artifact/QBvYFJMqGGPx2XKYYL6tm2; the other "Field Terminal" system
  and a Settings switch between looks were dropped at his request). Theme.qml holds its tokens:
  void/hull/acid/cyan/amber/signal palette, one font (JetBrains Mono, `fonts-jetbrains-mono`),
  `accent` follows `Theme.section` (acid in Network/Extra, cyan in Data). Chamfer.qml (QtQuick.Shapes,
  `qml6-module-qtquick-shapes`) draws the cut top-right/bottom-left corners for panels, tiles,
  buttons and fields (cutSm/cutMd/cutLg) with `Shape.CurveRenderer` (Qt >= 6.6; analytic AA, no
  layer texture: a layer over a fractional-width item gets stretched sub-pixel and blurs the right
  edge) and snaps its size to whole pixels; text-sized buttons/chips/tabs ceil() their widths and
  the sheets round their centred position so every 1px border lands on one pixel. Verify with a
  pixel scan of offscreen screenshots: all 1px box edges must be exact token colours. Icons and the
  empty-state dragon are vector (Icon.qml / EmptyState.qml Shapes), and the section-tab micro strip
  is always visible (no `compact` condition). Section tabs are label + `SEC.NN // count` strip with an
  underline; chips 48px; tile meta strip = N ACTIONS / GUI / ROOT // TTY; empty tool pane =
  EmptyState.qml (24px scan grid + dragon curve). Buttons: TouchButton filled when `color` is not
  panelAlt; outline variants via `borderColor` + `textColor` (Stop/Reboot/Shut down = signal,
  CLI Mode = amber); `selected: true` = the design's 2px accent border (toggled chips, Split,
  Keyboard, the gear while Settings is open, the selected tile and Wi-Fi row; a focused text field
  likewise); keyboard focus = 2px acid ring 2px outside. One filled primary per view (Run / Connect /
  Load to RAM / Open); command and choice chips are outline-selected. UI size range 0.75–1.6, the
  slider applies live. Sheets (Settings, System monitor, Wi-Fi) share Sheet.qml (scrim over the whole
  window via `parent: Overlay.overlay`, hull panel cut-lg padded space-6, title + micro facts strip,
  scrolls with BpScrollBar placed in the right padding) and SheetHeading.qml (uppercase label +
  hairline). Reboot / Shut down / Switch to CLI Mode confirm inside the sheet (`ask` state; the confirm
  button is signal-filled, the consequence is spelled out); no separate dialog. Status line under the
  tool pane is a micro uppercase strip (LAUNCHED / RUNNING / EXIT n / ERROR // …). BpScrollBar.qml =
  square 6px handle, hidden unless the content scrolls. Top bar drops the wordmark below width
  Theme.s(960) and the meter below Theme.s(880). Theme property names must not start with `on` +
  capital (QML reads them as signal handlers): hence `inkOnAccent` / `inkOnDanger`. Test hook:
  BACKPACK_DEMO_ASK=reboot|poweroff|cli (with BACKPACK_DEMO_SETTINGS=1) opens a confirm state.
- (command lines on buttons) Design rule: every button that runs a command shows it under its label in
  `command` type (Theme.commandFont = 12px mono, regular, letter-spacing 0, never uppercased; ink-muted
  on a plain button, the label colour at 75% on a filled one, 0.8 on an outline one); buttons that only
  change the screen (tabs, category chips, Close, Cancel, Settings, Wi-Fi) show none. TouchButton has
  `command` (+ `commandMaxWidth`, elided) and `fullWidth` (its width with label + command); Chip.qml is
  the design's 48px chip (uppercase `label` over the command, left-aligned, 2px accent border when
  selected) used for the action chips and the choice chips of a form. One source of truth per line:
  manifest.preview(cmd, values[, placeholders]) builds the display string the way build_argv builds
  argv (same `sudo -n` euid rule, shell quoting, `<name>` for an empty required field, every value a
  `<name>` slot with placeholders=True = the chip's `template`); runner.commandLine() returns it and
  Main.updateRunLine() re-runs it on ToolForm.changed / chip / tool change; the Run row echoes it as
  `$ …` (phosphor) beside the micro status strip (LAUNCHED also for gui/tty tools, which now emit
  `started`); Stop shows `kill -TERM <pid>` with runner.pid. Settings: Load to RAM = settings.ramCommand,
  Switch to CLI Mode = settings.cliCommand (`[sudo -n ]backpack-cli-mode`, a 2-line sh script in
  touchmode/bin shipped by the deb: `systemctl isolate multi-user.target && chvt 1`), Reboot/Shut down =
  system.rebootCommand/poweroffCommand (`[sudo -n ]systemctl reboot|poweroff`; the live user has
  passwordless sudo) and the Python runs exactly those strings. Wi-Fi: real nmcli lines (Rescan shows
  the `-t -f …` scan line), SSID shell-quoted (WifiOverlay.quoted), password as dots once typed,
  `<device>` placeholder; Connect is disabled with a message on 802.1X networks. Top bar: Terminal/Split/
  Keyboard show `foot --app-id …` / `pkill -f backpack-split` (Exit split now kills foot that way) /
  `pkill -USR1|USR2 -x wvkbd-mobintl` (the `swaymsg fullscreen disable; swaymsg exec` plumbing around
  foot is not shown); toggling buttons give TouchButton `altText`/`altCommand` so `fullWidth` is the
  wider state and the bar never re-tiers on a toggle. Form labels come
  from the manifest's optional arg `label` (`Ping only` for -sn; default = name with `_` as spaces);
  the flag switch is touch-tall with a chamfered track and shows its flag in command type.
  The top bar is MEASURED, not thresholded (Main.qml): tiers barMeterOnly < barWordmark < barLabels <
  barSettings < barMeter are sums of implicit widths that do not depend on the tier chosen (no binding
  loop): tabs (an Item wrapping a Row + Repeater) + five icon buttons + the compact meter; + the whole
  "BACKPACK//LIVE" wordmark (TextMetrics; it is never shortened, only dropped); + the four tool buttons'
  `fullWidth` (`compact` = width < barLabels, ~1902px at 1.0x: 1920x1080 shows the commands); + the
  Settings label; + the meter's percentages. Settings sheet is acid whatever the section; `extra`'s cat
  colour is acid (tokens.json has no cat-extra); meter/graph numbers are micro, the graph has no area
  fill; wrapped small text uses lineHeight Theme.smallLine (21px). The form Flickable (capped at 40% of
  the pane) has a BpScrollBar. Verified offscreen at 1024, 1280, 1800, 1920, 2048, 2200, 2560,
  portrait 800x1280 and 0.75/1.3/1.6x (logs clean, pixel scan clean). Offscreen gotcha: the
  `offscreen` platform uses the SOFTWARE scenegraph, where a Shape (Chamfer) inside a clipped
  Flickable is NOT clipped (a Rectangle is): a form row cut by the 40% cap shows through the Run
  row in screenshots (rsync at 1280x800). Not a product defect (the ISO renders with the RHI
  backend); check such artefacts in QEMU before chasing them.
- (release workflow) `.github/workflows/release.yml`: tag `v*` -> `make build` + `scripts/release.sh`
  (VERSION=tag names the ISO) and `scripts/build-usb-writer.sh` (GUI as .deb + AppImage in build/dist/)
  -> GitHub release with SHA256SUMS; workflow_dispatch builds artifacts only. The USB writer is not
  self-contained: it uses the host's python3-gi/GTK 4. Its AppRun copies the scripts out of the
  AppImage mount before running, because pkexec'd root cannot read a user FUSE mount.
  ISO job speedups: no runner disk cleanup (it cost 2-3 min), live/cache/packages.* kept in
  actions/cache (monthly key; tag runs can only read caches saved on main, so run release once on
  main to seed it), lb output followed live + build-log artifact, 45 min timeout. PRs build the
  ISO only when release.yml or scripts/release.sh changed.
- (boot menu, Backpack Field Terminal) BIOS + UEFI menus restyled to the GUI Mode look "Backpack Field Terminal"
  (JetBrains Mono, acid/cyan, chamfered corners). Art is generated by `tools/assets/gen-bootmenu.sh` (ImageMagick +
  grub-mkfont; OFL JetBrains Mono in tools/assets/fonts/): syslinux 640x480 splash.png + stdmenu.cfg colours, and a GRUB theme in
  bootloaders/grub-pc/backpack/ (background, select_*.png 9-slice, text-*.pf2). GRUB reads only 8-bit RGB(A)
  PNGs (no palette, no 16-bit: a 16-bit background shows colour fringes; write PNG24:/PNG32:), GRUB script has no `&&` (loadfont takes several files), font refs in
  theme.txt are "<-n name> Regular <size>". The progress_bar keeps ~28px height whatever `height` says.
  vesamenu item text is always the VGA bitmap font. Verified in QEMU with stand-in ISOs only (isolinux
  BIOS, grub-mkrescue + OVMF); not yet in a real `make build` (check grub-pc/backpack/ lands in /boot/grub).
- (usb writer app) `tools/usb-writer/app` = standalone writer for Linux/Windows/macOS (Go + Wails v2.12,
  plain HTML/CSS/JS frontend in `frontend/dist`, Field Terminal tokens copied into `style.css`).
  `flash/` writes the ISO, appends p3 to the image's MBR (1 MiB aligned, like `sfdisk --append`) and
  formats it with its own ext3 writer (`flash/ext3.go`: Windows/macOS have no mkfs.ext4); tests run
  `e2fsck -fn` on the result. Same binary is the CLI and the elevated worker: the window re-runs itself
  via pkexec (Linux) / osascript admin prompt (macOS) with `--yes --json FILE` and tails FILE; the
  Windows .exe is requireAdministrator (`build/windows/wails.exe.manifest`) and writes in-process.
  UI previews without a build: `NODE_PATH=$(npm root -g) node preview/shoot.mjs OUTDIR` (fake Go side).
  `update/` = updater: GitHub `releases/latest` of MR-Developer20/backpack (unauthenticated: it only works while the repo is public; while private the update button and "Download ISO" row stay hidden),
  picks `Backpack_USB_Writer-*-{linux-x86_64,windows-x86_64.exe,macos-universal.zip}` + the `.iso`, verifies
  against the release's SHA256SUMS, and swaps the binary (Linux rename over, Windows rename to .old,
  macOS replaces the .app bundle). Asset names come from release.yml's stage step: keep them in sync.
  The repo-wide `build/` ignore is undone in the app's `.gitignore` (Wails keeps packaging inputs there).
  The writer judges an image by content, never by extension: InspectISO (also called by flash.Run, so the
  CLI too) names ELF/PE/Mach-O/zip files ("a Linux program, not an ISO") because people pick the
  extension-less Linux writer asset off the release page; the picker offers "All files"; update.ISOAsset
  only matches `backpack-live-*.iso`. Downloads (update/fetch.go) use 8 ranged connections for files >= 64 MB
  (GitHub's CDN caps each connection), resume a dropped part, fall back to one stream on a 200.
  macOS: Go's File.Sync is fcntl(F_FULLFSYNC), which /dev/rdiskN refuses (ENOTTY), so the darwin device
  flushes with fsync and ignores ENOTTY/ENOTSUP. CI job `usb-writer-app-macos` runs test/mac-smoke.sh: the
  Wails-built binary as root (env -i, --json) against an hdiutil-attached image; results are posted as a CI
  annotation because job logs (blob storage) are not readable from cloud sessions. The elevated worker
  reports every failure through its --json file; its stdout/stderr go to output.log, shown when no result.
  macOS TCC keeps a root process started via osascript's password prompt out of ~/Downloads AND off removable
  drives (open /dev/rdiskN: "operation not permitted"), although `sudo` from Terminal works. So on macOS the window
  writes in-process (inProcess() in elevate_darwin.go) and flash/device_darwin.go opens the drive through
  /usr/libexec/authopen (-stdoutpipe: macOS's password dialog, fd passed back over a socketpair) whenever a plain
  open is refused. CI can only test authopen as root (TestAuthOpen); the dialog path needs a real Mac.
  Linux: window icon = embedded build/appicon.png (linux.Options.Icon); GTK_THEME=Adwaita:dark unless set (dark title
  bar like Windows/macOS); pkexec exit 126 = dismissed, 127 = no polkit agent / not allowed (shown as such); after a
  write the stick is unmounted again and powered off (udisksctl power-off, else eject), like macOS ejects. ISO
  downloads go to XDG_DOWNLOAD_DIR (user-dirs.dirs) when set. CI writes a loop device as root (TestLoopDevice,
  BACKPACK_TEST_LOOP; `allowLoop` lets openDisk take a loop device in tests only).
- (launcher fixes, 2026-10-14) Terminal / Keyboard / Wi-Fi left the top bar for a SESSION group in
  SettingsSheet.qml (act("terminal"|"keyboard"|"wifi") closes the sheet first); the bar is now tabs + Split +
  meter + gear, so portrait 800px keeps the CPU/RAM meter (tier sums in Main.qml count 2 icon buttons).
  UI size range 0.5–1.6 (settings.SCALE_MIN; the design token ui-scale-min is still 0.75). Orientation =
  Dropdown.qml (styled ComboBox, options show their command) bound to settings.rotation, saved in gui.json and
  applied at launcher start: `swaymsg output <name> transform normal|90|180|270` + `input type:touch|tablet_tool
  map_to_output <name>` (wlroots then rotates touch coordinates too). Sheet.qml pins the Flickable's
  contentWidth to its width: before, a row whose buttons wanted more (Wi-Fi's Rescan command line was sized
  from its own row) widened the whole ColumnLayout and everything on the right was clipped; rows of buttons
  in sheets are Flows with commandMaxWidth from Sheet.contentWidth. Wi-Fi: the password field has its own
  line (it shared a row with Show/Connect/Forget and their command lines and was squeezed to 0 px, so Connect
  stayed disabled); saved profiles (`nmcli -t -f NAME,TYPE con show`) show SAVED and connect without a password
  via `nmcli con up id SSID`. On-screen keyboard: System.watchInput installs an event filter on the window;
  text fields call system.fieldFocused(), which shows wvkbd only if the last press was TouchBegin/TabletPress
  or a mouse press whose device is a touchscreen/pen (runner.pressed_by_touch). IPv4 label: sysmon.ipv4
  (UDP-connect source address, else `ip -4 -o addr show scope global`, every 3 s) at Theme.ipFont (8px floor:
  4px was asked for but cannot be read) flush in the window's top-right corner. eDEX: `make edex-deb`
  (Dockerfile.edex image + scripts/build-edex.sh + scripts/build-edex-deb.sh) now runs inside `make build`
  (EDEX=0 skips; a failure only warns). Test hooks: BACKPACK_DEMO_WIFI_SELECT=<ssid>, BACKPACK_DEMO_IPV4=<addr>.
  None of this is booted on the ISO yet.
