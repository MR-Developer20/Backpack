#!/bin/sh
# Branding in the Backpack Field Terminal style (same system as the GUI Mode launcher and the
# boot menus, see tools/assets/gen-bootmenu.sh):
#   - wallpaper / login-screen background, 1920x1080 -> /usr/share/backgrounds/backpack.png
#   - plymouth boot splash: logo (splash.png) and the copy-to-RAM bar (bar.png, barbg.png)
# Needs ImageMagick 6 and python3. Run from the repo root: sh tools/assets/gen-branding.sh
# One family (JetBrains Mono), chamfered corners (top-right + bottom-left), no glows or gradients.
set -e
FONTS=tools/assets/fonts
REG=$FONTS/JetBrainsMono-Regular.ttf
BOLD=$FONTS/JetBrainsMono-Bold.ttf
XBOLD=$FONTS/JetBrainsMono-ExtraBold.ttf
INC=live/config/includes.chroot
PLY=$INC/usr/share/plymouth/themes/backpack
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

VOID='#07090a'; GRID='#2a3438'; GRID_STRONG='#5a6b70'
INK='#e6ede8'; MUTED='#8d9c96'; ACID='#c6ff1a'; CYAN='#2fd8e8'; AMBER='#ffb000'; SIGNAL='#ff3d6e'
cut() { echo "polygon $1,$2 $(($3-$5)),$2 $3,$(($2+$5)) $3,$4 $(($1+$5)),$4 $1,$(($4-$5))"; }

# ---------------------------------------------------------------- wallpaper 1920x1080
# The dragon curve (iteration 13) sits on the right in grid-strong; the cover band and the
# wordmark on the left. The GUI launcher covers it; it shows behind the login screen and in sway.
python3 tools/assets/dragon.py 13 6 1124 159 > "$OUT/dragon.mvg"
convert -size 1920x1080 xc:"$VOID" \
  -fill none -stroke "$GRID_STRONG" -strokewidth 1 -draw "$(cat "$OUT/dragon.mvg")" \
  -stroke none -fill "$ACID" -draw "$(cut 160 400 703 440 20)" \
  -fill "$CYAN" -draw "$(cut 719 400 959 440 20)" \
  -fill "$SIGNAL" -draw "$(cut 975 420 1103 440 6)" \
  -fill "$INK" -font "$XBOLD" -pointsize 96 -kerning 7.7 -annotate +152+568 'BACKPACK//LIVE' \
  -fill "$MUTED" -font "$BOLD" -pointsize 18 -kerning 2.9 -annotate +160+616 'DEBIAN 13 // NETWORK // DATA // FIELD TOOLS' \
  -kerning 0 -font "$REG" -pointsize 22 -annotate +160+664 'Network and data tools, sized for a thumb.' \
  -depth 8 PNG24:"$INC/usr/share/backgrounds/backpack.png"

# ---------------------------------------------------------------- plymouth
# logo: band + wordmark + metadata strip on transparent; the script fills the screen with void
convert -size 640x200 xc:none \
  -fill "$ACID" -draw "$(cut 0 0 319 23 12)" \
  -fill "$CYAN" -draw "$(cut 331 0 471 23 12)" \
  -fill "$AMBER" -draw "$(cut 483 0 567 23 8)" \
  -fill "$SIGNAL" -draw "$(cut 579 11 639 23 6)" \
  -fill "$INK" -font "$XBOLD" -pointsize 62 -kerning 5 -annotate +-4+112 'BACKPACK//LIVE' \
  -fill "$MUTED" -font "$BOLD" -pointsize 14 -kerning 2.2 -annotate +0+160 'DEBIAN 13 // STARTING' \
  -depth 8 PNG32:"$PLY/splash.png"
convert -size 1x1 xc:"$ACID" -depth 8 PNG24:"$PLY/bar.png"
convert -size 1x1 xc:"$GRID" -depth 8 PNG24:"$PLY/barbg.png"
ls -l "$INC/usr/share/backgrounds/backpack.png" "$PLY"/*.png
