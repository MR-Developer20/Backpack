#!/usr/bin/env python3
"""Print an ImageMagick MVG polyline of the Heighway dragon curve (the fractal on the
chapter pages of Jurassic Park, the novel), used as the one decoration in Backpack Field
Terminal artwork.  usage: dragon.py ITERATIONS STEP X Y  (X Y = top-left of the drawing)"""
import sys

it, step, ox, oy = (int(a) for a in sys.argv[1:5])
turns = [1]
for _ in range(it - 1):
    turns = turns + [1] + [1 - t for t in reversed(turns)]
x = y = 0
dx, dy = 1, 0
pts = [(0, 0), (1, 0)]
x = 1
for t in turns:
    dx, dy = (-dy, dx) if t else (dy, -dx)
    x, y = x + dx, y + dy
    pts.append((x, y))
mx, my = min(p[0] for p in pts), min(p[1] for p in pts)
print("polyline " + " ".join(f"{ox + (px - mx) * step},{oy + (py - my) * step}" for px, py in pts))
