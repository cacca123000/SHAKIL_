"""Draws the Shakil Cam app icon (1024x1024 PNG). Requires Pillow.

Usage: python3 scripts/make_icon.py [output.png]
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 1024
CX = CY = S / 2
OUT = sys.argv[1] if len(sys.argv) > 1 else "ShakilCam/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def radial(inner, outer, center, radius):
    img = Image.new("RGBA", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            t = min(1.0, math.hypot(x - center[0], y - center[1]) / radius)
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(4))
    return img


def circle_mask(r):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse([CX - r, CY - r, CX + r, CY + r], fill=255)
    return m


img = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(img)
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=(int(24 - 18 * t), int(24 - 18 * t), int(28 - 20 * t), 255))

glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([CX - 410, CY - 410, CX + 410, CY + 410], outline=(255, 200, 10, 140), width=40)
img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(30)))

img.paste(radial((58, 58, 64, 255), (14, 14, 16, 255), (CX - 120, CY - 160), 620), (0, 0), circle_mask(388))

d = ImageDraw.Draw(img)
d.ellipse([CX - 396, CY - 396, CX + 396, CY + 396], outline=(255, 204, 10, 255), width=16)
for i in range(120):
    a = math.radians(i * 3)
    d.line([(CX + 352 * math.cos(a), CY + 352 * math.sin(a)), (CX + 378 * math.cos(a), CY + 378 * math.sin(a))],
           fill=(8, 8, 9, 255), width=4)
d.ellipse([CX - 340, CY - 340, CX + 340, CY + 340], fill=(9, 9, 11, 255))
d.ellipse([CX - 300, CY - 300, CX + 300, CY + 300], outline=(38, 38, 44, 255), width=6)

img.paste(radial((40, 52, 120, 255), (2, 2, 8, 255), (CX - 60, CY - 70), 300), (0, 0), circle_mask(262))

rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(rim)
rd.arc([CX - 255, CY - 255, CX + 255, CY + 255], 200, 320, fill=(150, 90, 255, 200), width=10)
rd.arc([CX - 255, CY - 255, CX + 255, CY + 255], 20, 140, fill=(40, 220, 200, 170), width=10)
img = Image.alpha_composite(img, rim.filter(ImageFilter.GaussianBlur(6)))

d = ImageDraw.Draw(img)
hexagon = [(CX + 92 * math.cos(math.radians(60 * i + 30)), CY + 92 * math.sin(math.radians(60 * i + 30))) for i in range(6)]
d.polygon(hexagon, fill=(4, 4, 8, 255), outline=(255, 204, 10, 255), width=8)

hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
hd.ellipse([CX - 175, CY - 190, CX - 75, CY - 110], fill=(255, 255, 255, 170))
hd.arc([CX - 220, CY - 220, CX + 220, CY + 220], 195, 250, fill=(255, 255, 255, 90), width=14)
img = Image.alpha_composite(img, hl.filter(ImageFilter.GaussianBlur(10)))
ImageDraw.Draw(img).ellipse([CX + 70, CY + 80, CX + 104, CY + 114], fill=(255, 255, 255, 60))

rec = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(rec).ellipse([S - 205, 105, S - 125, 185], fill=(255, 59, 48, 255))
img = Image.alpha_composite(img, rec.filter(ImageFilter.GaussianBlur(18)))
img = Image.alpha_composite(img, rec)

img.convert("RGB").save(OUT)
print("Icon written to", OUT)
