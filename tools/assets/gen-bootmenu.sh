#!/bin/sh
# Boot menu artwork in the Backpack Field Terminal style (the GUI Mode look):
#   - syslinux/isolinux vesamenu background (BIOS menu), 640x480, <=256 colours
#   - GRUB theme for the UEFI menu: background, selection box pieces, PF2 fonts, timeout bar
# Needs ImageMagick 6 (`convert`) and grub-mkfont (grub-common). Run from the repo root:
#   sh tools/assets/gen-bootmenu.sh
# One family (JetBrains Mono, OFL), no rounded corners: containers are chamfered top-right and
# bottom-left. Colours: void #07090a, hull #0e1214, grid #2a3438, grid-strong #5a6b70,
# ink #e6ede8, ink-muted #8d9c96, acid #c6ff1a, cyan #2fd8e8, amber #ffb000, signal #ff3d6e.
set -e
FONTS=tools/assets/fonts
REG=$FONTS/JetBrainsMono-Regular.ttf
BOLD=$FONTS/JetBrainsMono-Bold.ttf
XBOLD=$FONTS/JetBrainsMono-ExtraBold.ttf
BL=live/config/bootloaders
GRUB=$BL/grub-pc
THEME=$GRUB/backpack
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

VOID='#07090a'; HULL='#0e1214'; GRID='#2a3438'; GRID_STRONG='#5a6b70'
INK='#e6ede8'; MUTED='#8d9c96'; ACID='#c6ff1a'; CYAN='#2fd8e8'; AMBER='#ffb000'; SIGNAL='#ff3d6e'

# cut X0 Y0 X1 Y1 C: an ImageMagick polygon with the top-right and bottom-left corners cut by C
cut() { echo "polygon $1,$2 $(($3-$5)),$2 $3,$(($2+$5)) $3,$4 $(($1+$5)),$4 $1,$(($4-$5))"; }

# ---------------------------------------------------------------- BIOS: vesamenu 640x480
# vesamenu draws text in 8x16 cells: with `menu vshift 11`, `menu width 66`, `menu margin 3` and `menu hshift 6`
# the menu sits in x 88..552 from y 200 (title row) down; the panel is drawn behind it and the
# timeout line prints near the bottom edge, so nothing else is drawn there.
convert -size 640x480 xc:"$VOID" \
  -fill "$HULL" -stroke "$GRID_STRONG" -strokewidth 1 -draw "$(cut 64 184 575 344 14)" \
  -stroke none -fill "$ACID" -draw "$(cut 64 40 351 60 8)" \
  -fill "$CYAN" -draw "$(cut 359 40 455 60 8)" \
  -fill "$AMBER" -draw "$(cut 463 40 527 60 6)" \
  -fill "$SIGNAL" -draw "$(cut 535 48 575 60 4)" \
  -fill "$INK" -font "$XBOLD" -pointsize 34 -annotate +62+114 'BACKPACK//LIVE' \
  -fill "$MUTED" -font "$BOLD" -pointsize 11 -annotate +65+140 'SEC.00 // BOOT // 4 MODES' \
  -stroke "$GRID" -strokewidth 1 -draw "line 64,156 575,156" \
  -stroke none -fill "$MUTED" -font "$REG" -pointsize 12 -annotate +64+376 'DEBIAN 13 // NETWORK // DATA // FIELD TOOLS' \
  -depth 8 "$OUT/sys.png"
convert "$OUT/sys.png" -colors 256 PNG8:"$OUT/splash.png"
cp "$OUT/splash.png" $BL/syslinux_common/splash.png
cp "$OUT/splash.png" $BL/isolinux/splash.png
cp "$OUT/splash.png" $GRUB/splash.png   # plain-background fallback in grub.cfg

# ---------------------------------------------------------------- UEFI: GRUB theme, 1024x768 design
mkdir -p "$THEME"
# amber block with void hazard stripes (Marathon caution marking), as on the design system cover
convert -size 104x32 xc:"$AMBER" -fill "$VOID" \
  -draw "polygon -32,32 -24,32 8,0 0,0" -draw "polygon -16,32 -8,32 24,0 16,0" \
  -draw "polygon 0,32 8,32 40,0 32,0" -draw "polygon 16,32 24,32 56,0 48,0" \
  -draw "polygon 32,32 40,32 72,0 64,0" -draw "polygon 48,32 56,32 88,0 80,0" \
  -draw "polygon 64,32 72,32 104,0 96,0" -draw "polygon 80,32 88,32 120,0 112,0" \
  -draw "polygon 96,32 104,32 136,0 128,0" \
  \( -size 104x32 xc:black -fill white -draw "$(cut 0 0 103 31 8)" \) \
  -alpha off -compose CopyOpacity -composite PNG32:"$OUT/hazard.png"
convert -size 1024x768 xc:"$VOID" \
  -fill "$ACID" -draw "$(cut 80 56 471 88 14)" \
  -fill "$CYAN" -draw "$(cut 483 56 671 88 14)" \
  -fill "$SIGNAL" -draw "$(cut 803 72 943 88 6)" \
  "$OUT/hazard.png" -geometry +687+56 -composite \
  -fill "$INK" -font "$XBOLD" -pointsize 60 -annotate +76+164 'BACKPACK//LIVE' \
  -fill "$MUTED" -font "$BOLD" -pointsize 15 -annotate +80+198 'SEC.00 // BOOT // SELECT A MODE' \
  -stroke "$GRID" -strokewidth 1 -draw "line 80,216 943,216" \
  -fill "$HULL" -stroke "$GRID_STRONG" -draw "$(cut 80 236 655 628 20)" \
  -fill "$HULL" -stroke "$GRID" -draw "$(cut 688 236 943 640 20)" \
  -stroke none -fill "$MUTED" -font "$BOLD" -pointsize 13 -annotate +708+272 'MODES' \
  -fill "$INK" -font "$REG" -pointsize 15 \
  -annotate +708+304 'GUI' -annotate +708+328 'CLI' -annotate +752+304 'touch launcher' -annotate +752+328 'full-screen shell' \
  -fill "$MUTED" -font "$BOLD" -pointsize 13 -annotate +708+380 'COPY TO RAM' \
  -fill "$INK" -font "$REG" -pointsize 15 \
  -annotate +708+412 'Loads about 1 GB,' -annotate +708+436 'then the USB stick' -annotate +708+460 'can be removed.' \
  -fill "$MUTED" -font "$BOLD" -pointsize 13 -annotate +708+512 'KEYS' \
  -fill "$INK" -font "$REG" -pointsize 15 \
  -annotate +708+544 'Enter' -annotate +708+568 'E' -annotate +708+592 'C' -annotate +776+544 'boot' -annotate +776+568 'edit' -annotate +776+592 'console' \
  -fill "$MUTED" -font "$REG" -pointsize 14 -annotate +80+706 'Boots the highlighted mode when the bar runs out.' \
  -font "$BOLD" -pointsize 12 -annotate +80+738 'DEBIAN 13 // NETWORK // DATA // FIELD TOOLS' \
  -depth 8 PNG24:"$THEME/background.png"

# GRUB reads only 8-bit-per-channel RGB(A) PNGs (no palette, no 16-bit: colour fringes), hence PNG24:/PNG32:.
# selection box: acid fill chamfered top-right and bottom-left, as GRUB 9-slice pieces (select_*.png)
convert -size 20x20 xc:none -fill "$ACID" -draw "polygon 0,0 12,0 19,7 19,19 7,19 0,12" "$OUT/sel.png"
convert "$OUT/sel.png" -crop 10x10+0+0 +repage PNG32:"$THEME/select_nw.png"
convert "$OUT/sel.png" -crop 10x10+10+0 +repage PNG32:"$THEME/select_ne.png"
convert "$OUT/sel.png" -crop 10x10+0+10 +repage PNG32:"$THEME/select_sw.png"
convert "$OUT/sel.png" -crop 10x10+10+10 +repage PNG32:"$THEME/select_se.png"
convert -size 1x10 xc:"$ACID" PNG32:"$THEME/select_n.png"; cp "$THEME/select_n.png" "$THEME/select_s.png"
convert -size 10x1 xc:"$ACID" PNG32:"$THEME/select_w.png"; cp "$THEME/select_w.png" "$THEME/select_e.png"
convert -size 1x1 xc:"$ACID" PNG32:"$THEME/select_c.png"

grub-mkfont -s 22 -n "Backpack Mono" -o "$THEME/text-22.pf2" "$REG"
grub-mkfont -s 16 -n "Backpack Mono" -o "$THEME/text-16.pf2" "$REG"
grub-mkfont -s 22 -n "Backpack Mono Bold" -o "$THEME/text-bold-22.pf2" "$BOLD"
ls -l $BL/syslinux_common/splash.png "$THEME"
