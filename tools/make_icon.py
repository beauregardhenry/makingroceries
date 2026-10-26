"""Draws the app icon (1024x1024) with Pillow. Run: python3 tools/make_icon.py"""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 1024
K = 4  # supersample factor
W = S * K


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# Background: vivid orange, lighter toward the top left
bg = Image.new("RGB", (W, W))
px = bg.load()
top, bottom = (255, 168, 46), (240, 92, 0)
for y in range(W):
    for x in range(0, W, 1):
        t = min(1.0, max(0.0, (y * 0.75 + x * 0.25) / W))
        px[x, y] = lerp(top, bottom, t)
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

# Orange slice on the bag front
cx, cy, r = 512, 650, 150
d.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=(255, 122, 0, 255))
d.ellipse([s(cx - r + 22), s(cy - r + 22), s(cx + r - 22), s(cy + r - 22)], fill=(255, 255, 255, 255))
d.ellipse([s(cx - r + 36), s(cy - r + 36), s(cx + r - 36), s(cy + r - 36)], fill=(255, 150, 20, 255))
for i in range(8):
    a = math.radians(i * 45 + 22.5)
    x1, y1 = cx + math.cos(a) * 20, cy + math.sin(a) * 20
    x2, y2 = cx + math.cos(a) * (r - 40), cy + math.sin(a) * (r - 40)
    d.line([s(x1), s(y1), s(x2), s(y2)], fill=(255, 238, 205, 255), width=s(14))
d.ellipse([s(cx - 22), s(cy - 22), s(cx + 22), s(cy + 22)], fill=(255, 238, 205, 255))

# Leaf sprouting from the bag top
ld = d
pts = []
for i in range(0, 101):
    t = i / 100
    x = 0 + 150 * t
    y = -math.sin(t * math.pi) * 62
    pts.append((x, y))
upper = pts
lower = [(x, -y * 0.45) for x, y in reversed(pts)]
shape = upper + lower
ox, oy, ang = 520, 392, -38
rot = math.radians(ang)
shape = [
    (ox + x * math.cos(rot) - y * math.sin(rot), oy + x * math.sin(rot) + y * math.cos(rot))
    for x, y in shape
]
ld.polygon([(s(x), s(y)) for x, y in shape], fill=(76, 175, 80, 255))

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
out.save("Grocery/Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
print("saved")
