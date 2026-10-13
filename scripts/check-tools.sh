#!/bin/sh
# Verify every command in the manifest is on PATH. Usage: check-tools.sh [--runtime] [manifest]
#   --runtime  also check the programs GUI Mode and CLI Mode call outside the manifest (sway, nmcli,
#              chvt, ...); only meaningful in the chroot or on the booted live system
# Works on the build host, in the chroot, and on the booted live system.
set -u
RUNTIME=0
[ "${1:-}" = "--runtime" ] && { RUNTIME=1; shift; }
MANIFEST="${1:-/etc/backpack/tools.yaml}"
[ -f "$MANIFEST" ] || MANIFEST="$(dirname "$0")/../manifest/tools.yaml"
GEN="$(dirname "$0")/gen-package-list.py"
[ -f "$GEN" ] || GEN=/usr/local/lib/backpack/gen-package-list.py

# Called by touchmode/ (runner.py, settings.py, sysmon.py, toram.py, sway.config, bin/) and the
# CLI Mode motd. Keep in sync when the GUI starts calling a new program.
RUNTIME_CMDS="sway swaymsg swaybg foot wvkbd-mobintl backpack-touch backpack-touch-session lightdm
python3 nmcli sudo systemctl chvt pkill pgrep dmidecode mount umount sh"

has() { command -v "$1" >/dev/null 2>&1 || [ -x "/usr/sbin/$1" ] || [ -x "/sbin/$1" ]; }

total=0; present=0
CMDS="$(python3 "$GEN" --manifest "$MANIFEST" --print-cmds)" || { echo "MISSING: (cannot read manifest $MANIFEST)"; echo "TOOLS: 0/0 present"; exit 1; }
for cmd in $(printf '%s\n' "$CMDS" | awk '{print $2}' | sort -u); do
  total=$((total+1))
  if has "$cmd"; then present=$((present+1)); else echo "MISSING: $cmd"; fi
done
echo "TOOLS: $present/$total present"
ok=0; [ "$present" -eq "$total" ] || ok=1

if [ "$RUNTIME" = 1 ]; then
  rtotal=0; rpresent=0
  for cmd in $RUNTIME_CMDS; do
    rtotal=$((rtotal+1))
    if has "$cmd"; then rpresent=$((rpresent+1)); else echo "MISSING-RUNTIME: $cmd"; fi
  done
  echo "RUNTIME: $rpresent/$rtotal present"
  [ "$rpresent" -eq "$rtotal" ] || ok=1
fi
exit $ok
