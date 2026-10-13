#!/bin/sh
# Boot menu artwork in the Field Terminal style (GUI Mode design system):
#   - syslinux/isolinux vesamenu background (BIOS menu), 640x480, <=256 colours
#   - GRUB theme for the UEFI menu: background, selection box pieces, PF2 fonts, timeout bar
# Needs ImageMagick 6 (`convert`) and grub-mkfont (grub-common). Run from the repo root:
#   sh tools/assets/gen-bootmenu.sh
# Palette (Marc's): Dark #161616, Light #bbbbbb, Neongreen #99ff45.
set -e
FONTS=tools/assets/fonts
DISPLAY_FONT=$FONTS/ChakraPetch-Bold.ttf
TEXT=$FONTS/PlexSansCondensed-Regular.ttf
TEXT_BOLD=$FONTS/PlexSansCondensed-SemiBold.ttf
BL=live/config/bootloaders
GRUB=$BL/grub-pc
THEME=$GRUB/backpack
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

VOID='#161616'; SURFACE='#1d1d1d'; LINE='#333333'; LINE_STRONG='#757575'
INK='#ececec'; MUTED='#bbbbbb'; SIGNAL='#99ff45'

# ---------------------------------------------------------------- BIOS: vesamenu 640x480
# vesamenu draws text in 8x16 cells: with `menu vshift 11`, `menu width 66`, `menu margin 3` and `menu hshift 6`
# the menu sits in x 88..552 from y 200 (title row) down; the panel is drawn behind it and the
# timeout line prints near the bottom edge, so nothing else is drawn there.
convert -size 640x480 xc:"$VOID" "$OUT/sys-ground.png"
convert "$OUT/sys-ground.png" \
  -fill "$SURFACE" -stroke "$LINE_STRONG" -strokewidth 1 -draw "roundrectangle 64,184 575,344 10,10" \
  -stroke none -fill "$INK" -font "$DISPLAY_FONT" -pointsize 44 -annotate +64+86 'BACKPACK' \
  -fill "$SIGNAL" -font "$TEXT_BOLD" -pointsize 15 -annotate +66+112 'LIVE  /  SELECT BOOT MODE' \
  -fill "$MUTED" -font "$TEXT" -pointsize 14 -gravity northeast -annotate +64+70 'BKP-BOOT / 01' \
  -gravity northwest \
  -stroke "$LINE_STRONG" -strokewidth 1 -draw "line 64,140 575,140" \
  -stroke none -fill "$SIGNAL" -draw "rectangle 64,138 159,142" \
  -stroke none -fill "$MUTED" -font "$TEXT" -pointsize 14 -annotate +64+376 'DEBIAN 13  ·  NETWORK DISCOVERY  ·  TESTING  ·  CAPTURE' \
  "$OUT/sys.png"
convert "$OUT/sys.png" -colors 256 PNG8:"$OUT/splash.png"
cp "$OUT/splash.png" $BL/syslinux_common/splash.png
cp "$OUT/splash.png" $BL/isolinux/splash.png

# ---------------------------------------------------------------- UEFI: GRUB theme, 1024x768 design
mkdir -p "$THEME"
convert -size 1024x768 xc:"$VOID" "$OUT/grub-ground.png"
convert "$OUT/grub-ground.png" \
  -fill "$SURFACE" -stroke "$LINE_STRONG" -strokewidth 1 -draw "roundrectangle 80,236 655,628 10,10" \
  -stroke none -fill "$INK" -font "$DISPLAY_FONT" -pointsize 72 -annotate +76+118 'BACKPACK' \
  -fill "$SIGNAL" -font "$TEXT_BOLD" -pointsize 22 -annotate +80+156 'LIVE  /  SELECT BOOT MODE' \
  -fill "$MUTED" -font "$TEXT" -pointsize 17 -gravity northeast -annotate +80+96 'BKP-BOOT / 01' \
  -gravity northwest \
  -fill "$SURFACE" -stroke "$LINE" -draw "roundrectangle 688,236 943,640 10,10" \
  -stroke none -fill "$MUTED" -font "$TEXT_BOLD" -pointsize 15 -annotate +708+270 'MODES' \
  -fill "$INK" -font "$TEXT" -pointsize 18 \
  -annotate +708+306 'GUI' -annotate +708+332 'CLI' -annotate +768+306 'touch launcher' -annotate +768+332 'full-screen shell' \
  -fill "$MUTED" -font "$TEXT_BOLD" -pointsize 15 -annotate +708+384 'COPY TO RAM' \
  -fill "$INK" -font "$TEXT" -pointsize 18 \
  -annotate +708+420 'Loads about 1 GB, then' -annotate +708+444 'the USB stick can be' -annotate +708+468 'removed.' \
  -fill "$MUTED" -font "$TEXT_BOLD" -pointsize 15 -annotate +708+520 'KEYS' \
  -fill "$INK" -font "$TEXT" -pointsize 18 \
  -annotate +708+556 'Enter' -annotate +708+580 'E' -annotate +708+604 'C' -annotate +768+556 'boot' -annotate +768+580 'edit' -annotate +768+604 'console' \
  -fill "$MUTED" -font "$TEXT" -pointsize 16 -annotate +80+706 'Boots the highlighted mode when the bar runs out.' \
  -annotate +80+738 'DEBIAN 13  ·  NETWORK DISCOVERY  ·  TESTING  ·  CAPTURE' \
  "$OUT/grub.png"
convert "$OUT/grub.png" \
  -stroke "$LINE_STRONG" -strokewidth 1 -draw "line 80,196 943,196" \
  -stroke none -fill "$SIGNAL" -draw "rectangle 80,193 223,199" \
  "$THEME/background.png"

# GRUB reads only 8-bit RGB(A) PNGs (no palette), hence PNG32: on every theme piece.
# selection box: 10px rounded neon-green fill, as GRUB 9-slice pieces (select_*.png)
convert -size 20x20 xc:none -fill "$SIGNAL" -draw "roundrectangle 0,0 19,19 9,9" "$OUT/sel.png"
convert "$OUT/sel.png" -crop 10x10+0+0 +repage PNG32:"$THEME/select_nw.png"
convert "$OUT/sel.png" -crop 10x10+10+0 +repage PNG32:"$THEME/select_ne.png"
convert "$OUT/sel.png" -crop 10x10+0+10 +repage PNG32:"$THEME/select_sw.png"
convert "$OUT/sel.png" -crop 10x10+10+10 +repage PNG32:"$THEME/select_se.png"
convert -size 1x10 xc:"$SIGNAL" PNG32:"$THEME/select_n.png"; cp "$THEME/select_n.png" "$THEME/select_s.png"
convert -size 10x1 xc:"$SIGNAL" PNG32:"$THEME/select_w.png"; cp "$THEME/select_w.png" "$THEME/select_e.png"
convert -size 1x1 xc:"$SIGNAL" PNG32:"$THEME/select_c.png"

grub-mkfont -s 24 -n "Backpack Text" -o "$THEME/text-24.pf2" "$TEXT"
grub-mkfont -s 16 -n "Backpack Text" -o "$THEME/text-16.pf2" "$TEXT"
grub-mkfont -s 24 -n "Backpack Text Bold" -o "$THEME/text-bold-24.pf2" "$TEXT_BOLD"
ls -l $BL/syslinux_common/splash.png "$THEME"
