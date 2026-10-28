"""Draws the app icons (1024x1024) with Pillow: a shopping cart with crossed legs.

Run from the repo root: python3 tools/make_icon.py          (every variant)
                        python3 tools/make_icon.py berry    (just one)
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

# Background top, background bottom, shadow tint, cart, wheels and grip, wheel hubs.
DARK = (60, 60, 72)
WHITE = (255, 255, 255)
VARIANTS = {
    "orange":   ((255, 168, 46), (240, 92, 0),   (120, 40, 0),  WHITE,          DARK,            WHITE),
    "lime":     ((184, 230, 80), (64, 160, 30),  (20, 70, 10),  WHITE,          DARK,            WHITE),
    "berry":    ((150, 150, 255), (70, 60, 200), (30, 20, 100), WHITE,          DARK,            WHITE),
    "midnight": ((70, 70, 84), (14, 14, 20),     (0, 0, 0),     (255, 122, 0),  (235, 235, 240), DARK),
}

S = 1024
K = 4  # supersample factor
W = S * K


def s(v):
    return int(v * K)


def gradient(top, bottom):
    # One pixel per diagonal step is enough; resize smooths it. (Much faster than per-pixel drawing.)
    n = 256
    small = Image.new("RGB", (n, n))
    px = small.load()
    for y in range(n):
        for x in range(n):
            t = min(1.0, max(0.0, (y * 0.75 + x * 0.25) / n))
            px[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return small.resize((W, W), Image.BICUBIC).convert("RGBA")


def draw_cart(ink, wheel, hub):
    art = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)
    dx, dy = 26, -55  # centres the cart on the icon
    ink, wheel, hub = ink + (255,), wheel + (255,), hub + (255,)

    def P(*p):
        return [(s(x + dx), s(y + dy)) for x, y in p]

    def dot(x, y, r, fill):
        d.ellipse([s(x + dx - r), s(y + dy - r), s(x + dx + r), s(y + dy + r)], fill=fill)

    # Basket: an outline with a wire grid and a light wash inside.
    basket = P((220, 330), (850, 330), (780, 610), (300, 610))
    d.polygon(basket, fill=(255, 255, 255, 110))
    for x0, x1 in ((378, 420), (535, 540), (692, 660)):
        d.line(P((x0, 330), (x1, 610)), fill=ink, width=s(24))
    d.line(P((240, 470), (815, 470)), fill=ink, width=s(24))
    d.line(basket + [basket[0]], fill=ink, width=s(44), joint="curve")
    # Handle, with a rubber grip on the bar you hold.
    d.line(P((120, 225), (190, 225), (220, 330)), fill=ink, width=s(44), joint="curve")
    d.line(P((120, 225), (172, 225)), fill=wheel, width=s(52))
    dot(120, 225, 26, wheel)
    dot(172, 225, 26, wheel)
    # Old-school crossed legs, a wheel at the foot of each.
    d.line(P((340, 610), (720, 850)), fill=ink, width=s(40))
    d.line(P((740, 610), (360, 850)), fill=ink, width=s(40))
    dot(540, 734, 16, wheel)
    for x in (360, 720):
        dot(x, 868, 74, wheel)
        dot(x, 868, 26, hub)
    return art


def draw(name):
    top, bottom, shade, ink, wheel, hub = VARIANTS[name]
    img = gradient(top, bottom)
    art = draw_cart(ink, wheel, hub)
    # Soft shadow from the artwork's own silhouette.
    shadow = Image.new("RGBA", (W, W), shade + (0,))
    shadow.putalpha(art.getchannel("A").point(lambda a: int(a * 0.35)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(20)))
    img = Image.alpha_composite(img, shadow.transform((W, W), Image.AFFINE, (1, 0, 0, 0, 1, -s(18))))
    img = Image.alpha_composite(img, art)
    return img.resize((S, S), Image.LANCZOS).convert("RGB")


def save_icon(out, dest):
    os.makedirs(dest, exist_ok=True)
    out.save(f"{dest}/icon-1024.png")
    with open(f"{dest}/Contents.json", "w") as f:
        f.write('{ "images" : [ { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ], "info" : { "author" : "xcode", "version" : 1 } }')


def make(name):
    out = draw(name)
    assets = "Grocery/Sources/Assets.xcassets"
    save_icon(out, f"{assets}/{'AppIcon' if name == 'orange' else 'AppIcon-' + name.capitalize()}.appiconset")
    # A small preview for the in-app picker.
    prev = f"{assets}/IconPreview-{name.capitalize()}.imageset"
    os.makedirs(prev, exist_ok=True)
    out.resize((240, 240), Image.LANCZOS).save(f"{prev}/preview.png")
    with open(f"{prev}/Contents.json", "w") as f:
        f.write('{ "images" : [ { "filename" : "preview.png", "idiom" : "universal" } ], "info" : { "author" : "xcode", "version" : 1 } }')
    if name == "orange":
        # The Watch app uses the main icon; keep its existing Contents.json.
        out.save("Grocery/Watch/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
    print("saved", name)


if __name__ == "__main__":
    for n in sys.argv[1:] or VARIANTS:
        make(n)
