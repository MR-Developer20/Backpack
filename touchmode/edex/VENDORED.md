# Vendored eDEX-UI

Source: https://github.com/GitSquared/edex-ui (archived 2021-10)
Upstream commit: 04a00c4079908788b371c6ecdefff96d0d9950f8
Vendored: 2026-10-08

Modified from upstream to build on current Electron/Node (see git history of this repo).
Original is GPL-3.0; see LICENSE.

## Changes from upstream (to run on current Electron)
- `package.json`: electron ^12.1.0 -> 37.2.0; electron-builder -> 25.1.8;
  electron-rebuild -> @electron/rebuild 3.7.1; node-abi -> ^3.70.0.
- `src/package.json`: @electron/remote -> 2.1.2; node-pty -> 1.0.0 (xterm kept at 4.x).
- `src/_boot.js`: removed `enableRemoteModule`; added `@electron/remote/main` `.enable(win.webContents)`
  after window creation. (Env-guarded EDEX_CAPTURE test hook for headless screenshots.)
- `src/_renderer.js`: `electron.remote.*` -> `remote.*` (14 refs; `remote` was already imported).
- Build: `scripts/build-edex.sh` in the `backpack-edex` container; node-pty must be rebuilt
  with `electron-rebuild --version <electron version>` (auto-detect picks the wrong version).
- Runs under `--no-sandbox` only when launched as root (the live ISO runs it as the `user`).
Verified: launches on Electron 37.2.0, node-pty terminal backend initialized, full UI renders
(terminal, system panels, network globe, filesystem browser, on-screen keyboard).

## Packaging into the ISO
- `package.json` build target set to Debian `deb` (x64); `deb.depends` use trixie t64 names
  (libgtk-3-0t64, libatspi2.0-0t64) — electron-builder's defaults use the pre-t64 names that
  do not exist in trixie, so the deb would fail to install.
- Build: `scripts/build-edex-deb.sh` in the backpack-edex container -> dist/edex-ui_*_amd64.deb,
  repacked into live/config/packages.chroot/ with corrected Depends.
- Touch tweak: default termFontSize 15 -> 18 (written on first run).
- Touch Mode gains an "eDEX" top-bar button (shown when edex-ui is on PATH) that unfullscreens
  the launcher and `swaymsg exec 'edex-ui --no-sandbox'`; eDEX is full-screen and returns on exit.
