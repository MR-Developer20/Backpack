#!/bin/sh
# Generate the GUI Mode top-bar icons (96x96 PNG, white on transparent) and the plymouth
# progress-bar pixels. Run inside the backpack-edex container (has ImageMagick):
#   docker run --rm -v "$PWD":/work backpack-edex sh /work/tools/assets/gen-icons.sh
set -e
cd /work/touchmode/backpack_touch/icons
S=96; C='#e6edf3'
# terminal: rounded frame + prompt
convert -size ${S}x${S} xc:none -stroke "$C" -strokewidth 6 -fill none -draw "roundrectangle 10,16 86,80 8,8" \
  -fill "$C" -stroke none -font DejaVu-Sans-Mono-Bold -pointsize 34 -gravity center -annotate +0+2 '>_' terminal.png
# split: two panes
convert -size ${S}x${S} xc:none -stroke "$C" -strokewidth 6 -fill none -draw "roundrectangle 8,16 44,80 6,6" -draw "roundrectangle 52,16 88,80 6,6" split.png
# exit split: one pane + X
convert -size ${S}x${S} xc:none -stroke "$C" -strokewidth 6 -fill none -draw "roundrectangle 8,16 88,80 6,6" \
  -draw "line 36,36 60,60" -draw "line 60,36 36,60" exitsplit.png
# wifi: three arcs + dot (arcs drawn as circles then bottom half masked)
convert -size ${S}x${S} xc:none -stroke "$C" -strokewidth 6 -fill none \
  -draw "arc 8,20 88,100 210,330" -draw "arc 22,34 74,86 210,330" -draw "arc 36,48 60,72 210,330" \
  -fill "$C" -stroke none -draw "circle 48,78 48,84" wifi.png
# reboot: circular arrow
convert -size ${S}x${S} xc:none -stroke "$C" -strokewidth 7 -fill none -draw "arc 16,16 80,80 300,240" \
  -fill "$C" -stroke none -draw "polygon 70,10 86,30 62,32" reboot.png
# power: circle with gap + bar
convert -size ${S}x${S} xc:none -stroke "$C" -strokewidth 7 -fill none -draw "arc 16,20 80,84 300,240" \
  -stroke "$C" -draw "line 48,10 48,46" power.png
# settings: gear (8 teeth around a ring with a hole)
T=""; for a in 0 45 90 135 180 225 270 315; do T="$T -draw 'translate 48,48 rotate $a rectangle -7,-42 7,-26'"; done
eval convert -size ${S}x${S} xc:none -fill "'$C'" -stroke none $T -fill none -stroke "'$C'" -strokewidth 8 \
  -draw "'circle 48,48 48,22'" -strokewidth 6 -draw "'circle 48,48 48,38'" settings.png
# eDEX: from the vendored project, scaled
convert /work/touchmode/edex/media/linuxIcons/128x128.png -resize ${S}x${S} edex.png
# keyboard: frame + key dots
convert -size 96x96 xc:none -stroke '#e6edf3' -strokewidth 5 -fill none -draw "roundrectangle 6,24 90,72 6,6" \
  -fill '#e6edf3' -stroke none \
  -draw "rectangle 18,34 24,40" -draw "rectangle 30,34 36,40" -draw "rectangle 42,34 48,40" -draw "rectangle 54,34 60,40" -draw "rectangle 66,34 72,40" \
  -draw "rectangle 18,46 24,52" -draw "rectangle 30,46 36,52" -draw "rectangle 42,46 48,52" -draw "rectangle 54,46 60,52" -draw "rectangle 66,46 72,52" \
  -draw "rectangle 26,58 70,64" keyboard.png
# plymouth progress bar pixels
P=/work/live/config/includes.chroot/usr/share/plymouth/themes/backpack
convert -size 1x1 xc:'#2ec4b6' "$P/bar.png"
convert -size 1x1 xc:'#223038' "$P/barbg.png"
ls -l *.png "$P"/bar*.png | awk '{print $5, $9}'
