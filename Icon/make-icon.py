#!/usr/bin/env python3
"""Render Winndow's app icon: a full-bleed volt-blue square (macOS rounds it) with a white window snapped into panes,
the LW pentagon mark (Logan Winn's brand mark, Icon/lw-mark-white.png) in the left pane.
Writes Icon/icon-1024.png and Icon/AppIcon.icns. Needs Pillow; iconutil ships with macOS."""
import os, shutil, subprocess
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
S = 4                       # supersample for smooth edges
N = 1024 * S
VOLT = (46, 43, 255)        # Signal palette accent #2E2BFF
WHITE = (255, 255, 255)

def sq(v): return int(v * S)

canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
# Full bleed: macOS 26 applies its own rounded mask to a full-square icon and puts
# any other shape on a gray plate.
body = (0, 0, N, N)
mask = Image.new("L", (N, N), 255)

# Volt-blue tile with a gentle top-to-bottom shade of the same blue.
grad = Image.new("RGBA", (N, N))
gd = ImageDraw.Draw(grad)
top, bottom = (66, 63, 255), (34, 31, 222)
for y in range(N):
    t = min(max((y - body[1]) / (body[3] - body[1]), 0), 1)
    gd.line([(0, y), (N, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
tile = Image.new("RGBA", (N, N), (0, 0, 0, 0))
tile.paste(grad, (0, 0), mask)
canvas.alpha_composite(tile)

# The window: white frame, left pane filled (snapped half), right side split into two panes.
d = ImageDraw.Draw(canvas)
wx0, wy0, wx1, wy1 = sq(139), sq(201), sq(885), sq(823)
r, stroke, gap = sq(57), sq(27), sq(25)
mid = (wx0 + wx1) // 2
d.rounded_rectangle((wx0, wy0, mid - gap // 2, wy1), r, fill=WHITE)
for y0, y1 in ((wy0, (wy0 + wy1) // 2 - gap // 2), ((wy0 + wy1) // 2 + gap // 2, wy1)):
    pane = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(pane).rounded_rectangle((mid + gap // 2, y0, wx1, y1), r, fill=(255, 255, 255, 46), outline=WHITE, width=stroke)
    canvas.alpha_composite(pane)

# LW pentagon mark, recolored to volt blue, centered in the white pane.
mark = Image.open(os.path.join(HERE, "lw-mark-white.png")).convert("RGBA")
mark = mark.crop(mark.getchannel("A").getbbox())
pw = (mid - gap // 2) - wx0
size = int(pw * 0.80)
mark = mark.resize((size, int(mark.height * size / mark.width)), Image.LANCZOS)
blue = Image.new("RGBA", mark.size, VOLT + (255,))
blue.putalpha(mark.getchannel("A"))
canvas.alpha_composite(blue, (wx0 + (pw - mark.width) // 2, (wy0 + wy1 - mark.height) // 2))

icon = canvas.resize((1024, 1024), Image.LANCZOS)
icon.save(os.path.join(HERE, "icon-1024.png"))

iconset = os.path.join(HERE, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
for px in (16, 32, 128, 256, 512):
    icon.resize((px, px), Image.LANCZOS).save(f"{iconset}/icon_{px}x{px}.png")
    icon.resize((px * 2, px * 2), Image.LANCZOS).save(f"{iconset}/icon_{px}x{px}@2x.png")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(HERE, "AppIcon.icns")], check=True)
shutil.rmtree(iconset)
print("wrote Icon/icon-1024.png and Icon/AppIcon.icns")
