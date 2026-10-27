"""Draws the app icon (1024x1024) with Pillow. Run: python3 tools/make_icon.py"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

# Color variants: background top, background bottom, fruit rind, fruit flesh, segments.
VARIANTS = {
    "orange":   ((255, 168, 46), (240, 92, 0),    (90, 190, 35),  (160, 225, 60),  (236, 250, 200)),
    "lime":     ((184, 230, 80), (64, 160, 30),   (110, 190, 40), (160, 220, 60),  (240, 252, 210)),
    "berry":    ((150, 150, 255), (70, 60, 200),  (190, 70, 190), (225, 110, 215), (255, 225, 250)),
    "midnight": ((70, 70, 84), (14, 14, 20),      (255, 122, 0),  (255, 150, 20),  (255, 238, 205)),
}
name = sys.argv[1] if len(sys.argv) > 1 else "orange"
TOP, BOTTOM, RIND, FLESH, SEGMENT = VARIANTS[name]
PITH = tuple(int(c + (255 - c) * 0.72) for c in RIND)

S = 1024
K = 4  # supersample factor
W = S * K


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# Background: vivid orange, lighter toward the top left
top, bottom = TOP, BOTTOM
# One pixel per diagonal step is enough; resize smooths it. (Much faster than per-pixel drawing.)
N = 256
small = Image.new("RGB", (N, N))
sp = small.load()
for y in range(N):
    for x in range(N):
        t = min(1.0, max(0.0, (y * 0.75 + x * 0.25) / N))
        sp[x, y] = lerp(top, bottom, t)
bg = small.resize((W, W), Image.BICUBIC)
img = bg.convert("RGBA")


def s(v):
    return int(v * K)


def layer():
    return Image.new("RGBA", (W, W), (0, 0, 0, 0))


art = layer()
d = ImageDraw.Draw(art)

# Bag body with rounded bottom corners
d.rounded_rectangle([s(272), s(400), s(752), s(880)], radius=s(46), fill=(255, 255, 255, 255))
d.rectangle([s(272), s(400), s(752), s(600)], fill=(255, 255, 255, 255))

# Folded top lip, warm cream
d.rounded_rectangle([s(270), s(372), s(754), s(430)], radius=s(18), fill=(255, 240, 220, 255))

# Handles
for cx in (420, 604):
    d.arc([s(cx - 70), s(250), s(cx + 70), s(440)], 180, 360, fill=(255, 255, 255, 255), width=s(26))

# Fruit slice on the bag front
cx, cy, r = 512, 650, 150
d.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=RIND + (255,))
d.ellipse([s(cx - r + 22), s(cy - r + 22), s(cx + r - 22), s(cy + r - 22)], fill=PITH + (255,))
d.ellipse([s(cx - r + 36), s(cy - r + 36), s(cx + r - 36), s(cy + r - 36)], fill=FLESH + (255,))
for i in range(8):
    a = math.radians(i * 45 + 22.5)
    x1, y1 = cx + math.cos(a) * 20, cy + math.sin(a) * 20
    x2, y2 = cx + math.cos(a) * (r - 40), cy + math.sin(a) * (r - 40)
    d.line([s(x1), s(y1), s(x2), s(y2)], fill=SEGMENT + (255,), width=s(14))
d.ellipse([s(cx - 22), s(cy - 22), s(cx + 22), s(cy + 22)], fill=SEGMENT + (255,))

# Soft shadow from the artwork's own silhouette
shadow = Image.new("RGBA", (W, W), (120, 40, 0, 0))
shadow.putalpha(art.getchannel("A").point(lambda a: int(a * 0.38)))
shadow = shadow.filter(ImageFilter.GaussianBlur(s(24)))

# Enlarge about the centre of the artwork (x 258-766, y 250-880) and centre it on the canvas
scale, art_cx, art_cy = 1.14, 512, 560
def place(layer_img):
    m = (1 / scale, 0, art_cx - 512 / scale, 0, 1 / scale, art_cy - 512 / scale)
    return layer_img.transform(layer_img.size, Image.AFFINE, tuple(v if i in (0, 4) else v * K for i, v in enumerate(m)),
                               resample=Image.BICUBIC)
img = Image.alpha_composite(img, place(shadow).transform((W, W), Image.AFFINE, (1, 0, 0, 0, 1, -s(22))))
img = Image.alpha_composite(img, place(art))

out = img.resize((S, S), Image.LANCZOS).convert("RGB")
import os
folder = "AppIcon" if name == "orange" else "AppIcon-" + name.capitalize()
dest = f"Grocery/Sources/Assets.xcassets/{folder}.appiconset"
os.makedirs(dest, exist_ok=True)
out.save(f"{dest}/icon-1024.png")
with open(f"{dest}/Contents.json", "w") as f:
    f.write('{ "images" : [ { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ], "info" : { "author" : "xcode", "version" : 1 } }')
# a small preview for the in-app picker
prev = f"Grocery/Sources/Assets.xcassets/IconPreview-{name.capitalize()}.imageset"
os.makedirs(prev, exist_ok=True)
out.resize((240, 240), Image.LANCZOS).save(f"{prev}/preview.png")
with open(f"{prev}/Contents.json", "w") as f:
    f.write('{ "images" : [ { "filename" : "preview.png", "idiom" : "universal" } ], "info" : { "author" : "xcode", "version" : 1 } }')
print("saved", name)
