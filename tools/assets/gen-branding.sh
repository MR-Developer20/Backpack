#!/bin/sh
set -e
cd /work/branding
# Palette matches the Touch Mode theme (bg #0f1419, accent #2ec4b6)
# 1) Wallpaper / greeter background 1920x1080
convert -size 1920x1080 \
  gradient:'#0b1016'-'#0f1b22' \
  -fill '#13303a' -draw "circle 1500,250 1500,80" \
  -blur 0x90 \
  \( -size 1920x1080 xc:none -fill '#1a2630' \
     -draw "line 0,720 1920,560" -draw "line 0,780 1920,900" -blur 0x1 \) -compose over -composite \
  -gravity center -font DejaVu-Sans-Bold -pointsize 120 -fill '#e6edf3' -annotate +0-40 'NetToolkit' \
  -font DejaVu-Sans -pointsize 56 -fill '#2ec4b6' -annotate +0+70 'LIVE' \
  -pointsize 24 -fill '#8b9bb0' -annotate +0+740 'network discovery  ·  testing  ·  capture' \
  wallpaper.png
# 2) Boot splash 640x480 (syslinux vesamenu background, GRUB bg)
convert -size 640x480 xc:'#0b1016' \
  -gravity center -font DejaVu-Sans-Bold -pointsize 44 -fill '#e6edf3' -annotate +0-20 'NetToolkit' \
  -font DejaVu-Sans -pointsize 22 -fill '#2ec4b6' -annotate +0+28 'LIVE' \
  splash.png
# 3) A 16-color PNG variant for syslinux vesamenu (needs <= 256 colors, 640x480)
convert splash.png -resize 640x480 -colors 256 PNG8:splash-boot.png
ls -l *.png | awk '{print $5, $9}'
