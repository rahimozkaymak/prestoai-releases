#!/usr/bin/env python3
"""Generate a professional DMG background image for Presto AI."""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math

# DMG window: 660x428 at 1x (bounds: 200,120 to 860,548)
# Create at 2x for Retina
W1, H1 = 660, 428
W, H = W1 * 2, H1 * 2

# Create base image
img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
draw = ImageDraw.Draw(img)

# Dark gradient background with subtle purple/blue tint
for y in range(H):
    t = y / H
    r = int(18 + t * 8)
    g = int(16 + t * 6)
    b = int(28 + t * 12)
    draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

# Subtle radial glow in center-upper area
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
glow_draw = ImageDraw.Draw(glow)
cx, cy = W // 2, int(H * 0.35)
glow_draw.ellipse(
    [cx - 600, cy - 350, cx + 600, cy + 350],
    fill=(50, 40, 70, 30)
)
glow = glow.filter(ImageFilter.GaussianBlur(radius=150))
img = Image.alpha_composite(img, glow)

# Second glow for depth
glow2 = Image.new("RGBA", (W, H), (0, 0, 0, 0))
glow2_draw = ImageDraw.Draw(glow2)
glow2_draw.ellipse(
    [cx - 300, cy - 200, cx + 300, cy + 200],
    fill=(70, 55, 100, 20)
)
glow2 = glow2.filter(ImageFilter.GaussianBlur(radius=100))
img = Image.alpha_composite(img, glow2)

draw = ImageDraw.Draw(img)

# Icon positions at 2x (matching AppleScript: app at x=165, apps at x=495, y=160)
app_cx = 165 * 2  # 330
apps_cx = 495 * 2  # 990
icon_cy = 160 * 2  # 320

# Draw dashed arrow between icon positions
arrow_y = icon_cy
x1 = app_cx + 140  # after app icon
x2 = apps_cx - 140  # before apps icon

dash_len = 28
gap_len = 18
x = x1
while x < x2 - 50:
    end = min(x + dash_len, x2 - 50)
    draw.line([(x, arrow_y), (end, arrow_y)], fill=(255, 255, 255, 50), width=4)
    x += dash_len + gap_len

# Arrowhead
head_x = x2 - 40
head_size = 18
draw.polygon([
    (head_x + head_size * 2, arrow_y),
    (head_x, arrow_y - head_size),
    (head_x, arrow_y + head_size),
], fill=(255, 255, 255, 55))

# Title text - "Presto AI" at top
try:
    title_font = ImageFont.truetype("/System/Library/Fonts/SFCompact.ttf", 52)
    sub_font = ImageFont.truetype("/System/Library/Fonts/SFCompact.ttf", 28)
except:
    try:
        title_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 52)
        sub_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28)
    except:
        title_font = ImageFont.load_default()
        sub_font = ImageFont.load_default()

# Title
title = "Presto AI"
bbox = draw.textbbox((0, 0), title, font=title_font)
tw = bbox[2] - bbox[0]
draw.text(((W - tw) // 2, 55), title, fill=(255, 255, 255, 220), font=title_font)

# Subtitle instruction at bottom
sub = "Drag PrestoAI to Applications to install"
bbox2 = draw.textbbox((0, 0), sub, font=sub_font)
sw = bbox2[2] - bbox2[0]
draw.text(((W - sw) // 2, H - 100), sub, fill=(255, 255, 255, 120), font=sub_font)

# Subtle border/vignette
vignette = Image.new("RGBA", (W, H), (0, 0, 0, 0))
vig_draw = ImageDraw.Draw(vignette)
# Draw darkened edges
for i in range(40):
    alpha = int(25 * (1 - i / 40))
    vig_draw.rectangle([i, i, W - i, H - i], outline=(0, 0, 0, alpha))
img = Image.alpha_composite(img, vignette)

# Save 2x (Retina)
img_2x = img.convert("RGB")
img_2x.save("/Volumes/T7/PrestoAI/dmg-resources/background@2x.png")

# Save 1x
img_1x = img.resize((W1, H1), Image.LANCZOS).convert("RGB")
img_1x.save("/Volumes/T7/PrestoAI/dmg-resources/background@1x.png")
img_1x.save("/Volumes/T7/PrestoAI/dmg-resources/background.png")

# Create multi-resolution TIFF for DMG (with both 1x and 2x)
import subprocess
subprocess.run([
    "tiffutil", "-catnosizecheck",
    "/Volumes/T7/PrestoAI/dmg-resources/background@1x.png",
    "/Volumes/T7/PrestoAI/dmg-resources/background@2x.png",
    "-out", "/Volumes/T7/PrestoAI/dmg-resources/background.tiff"
], check=False)

# Fallback: just convert 1x to tiff if tiffutil fails
import os
if not os.path.exists("/Volumes/T7/PrestoAI/dmg-resources/background.tiff") or \
   os.path.getsize("/Volumes/T7/PrestoAI/dmg-resources/background.tiff") < 100:
    img_1x_tiff = img.resize((W1, H1), Image.LANCZOS).convert("RGB")
    img_1x_tiff.save("/Volumes/T7/PrestoAI/dmg-resources/background.tiff", "TIFF")

print(f"Created: {W}x{H} (2x), {W1}x{H1} (1x), and TIFF")
