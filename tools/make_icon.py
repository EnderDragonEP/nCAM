#!/usr/bin/env python3
"""Draws the nCAM launcher icon and writes every Android icon file.

    python tools/make_icon.py                       write the icons into the app
    python tools/make_icon.py --preview icon.png    also save a large preview sheet
    python tools/make_icon.py --preview icon.png --preview-only
                                                    preview without touching the app

Needs Pillow (pip install pillow). Run from anywhere; paths are relative to this file.

What it writes under android/app/src/main/res/:
  mipmap-<density>/ic_launcher_background.png   adaptive icon background (Android 8+)
  mipmap-<density>/ic_launcher_foreground.png   adaptive icon picture
  mipmap-<density>/ic_launcher_monochrome.png   themed-icon shape (Android 13+)
  mipmap-<density>/ic_launcher.png              squircle fallback
  mipmap-<density>/ic_launcher_round.png        round fallback
  mipmap-anydpi-v26/ic_launcher.xml, ic_launcher_round.xml

The drawing is done in the adaptive icon's own units: a 108 x 108 canvas of which
the launcher may show as little as the central circle of radius 33 (the "safe zone").
Everything important stays inside it. Edit the DESIGN section to change the look.
"""
import argparse
import math
import os
import sys

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:
    sys.exit("Pillow is needed: pip install pillow")

# ---------------------------------------------------------------- DESIGN
# Samsung One UI 9 look: a bright diagonal gradient and one chunky, soft white glyph.
# The mount melts into the body (no sharp step), corners are almost pill shaped, the
# glyph is gently shaded and sits on a soft shadow. The record dot sends out two Wi-Fi
# arcs.
#
# The glyph is drawn slightly above the canvas centre: its shadow and the bump of the
# mount add visual weight below and above, and this balances it optically.
DESIGN = {
    "background": ("#5BB2FF", "#1C5FE0"),  # top-left -> bottom-right
    "glyph_shade": ("#FFFFFF", "#E2EBFF"),  # glyph top -> bottom
    "body_box": (30.0, 41.5, 78.0, 71.5),  # left, top, right, bottom
    "body_radius": 12.5,
    "mount_box": (45.0, 37.0, 59.0, 45.5),
    "mount_radius": 4.5,
    "smooth": 1.1,  # how softly the mount blends into the body
    "shadow": (0.0, 2.2, 2.6, "#0A2A6B", 0.30),  # dx, dy, blur, colour, opacity
    "centre": (52.5, 57.0),  # lens centre
    "lens_hole": 10.5,  # radius of the see-through lens opening
    "ring": (6.2, 3.0),  # ring inside the lens: outer, inner radius
    "rec_dot": (68.5, 49.5, 2.6),  # x, y, radius
    "signal_radii": (5.6, 9.0),  # Wi-Fi arcs around the record dot
    "signal_width": 2.1,
    # Shading. Each of these lines can be removed to switch that effect off.
    "bg_glow": (22.0, 14.0, 72.0, "#FFFFFF", 0.38),  # x, y, radius, colour, strength
    "bg_depth": (104.0, 108.0, 80.0, "#0B2A8C", 0.35),  # darker corner, same format
    "glyph_rim": (1.6, 1.6, "#8FA9E3", 0.75),  # inner shade at the bottom edge:
    #   offset, blur, colour, strength
    "glyph_gloss": (1.0, 1.0, "#FFFFFF", 0.9),  # light rim along the top edge
    "lens_depth": (2.2, 1.8, "#0A2A6B", 0.55),  # recess shade inside the lens opening
    "ring_shade": ("#FFFFFF", "#D5E2FF"),  # lens ring, top -> bottom
    "accent_shade": ("#FF7B6B", "#E5302A"),  # red dot and arcs, top -> bottom
}
# One UI's icon shape: a superellipse. Higher = squarer corners.
SQUIRCLE_POWER = 5.0
# ------------------------------------------------------------------------

UNITS = 108.0
MASTER = 1728  # master render size in pixels (16 per unit), downscaled later
S = MASTER / UNITS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# Launcher sizes per density: (adaptive layer px, legacy icon px)
DENSITIES = {
    "mdpi": (108, 48),
    "hdpi": (162, 72),
    "xhdpi": (216, 96),
    "xxhdpi": (324, 144),
    "xxxhdpi": (432, 192),
}


def px(*values):
    return [v * S for v in values]


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def circle(draw, x, y, r, fill):
    draw.ellipse(px(x - r, y - r, x + r, y + r), fill=fill)


def new_mask():
    return Image.new("L", (MASTER, MASTER), 0)


def signal_arcs(draw, d, fill):
    """Wi-Fi style arcs to the upper right of the record dot, with round ends."""
    x, y, _ = d["rec_dot"]
    w = d["signal_width"]
    for radius in d["signal_radii"]:
        draw.arc(px(x - radius, y - radius, x + radius, y + radius),
                 start=270, end=360, fill=fill, width=max(1, round(w * S)))
        mid = radius - w / 2
        for angle in (270, 360):
            a = math.radians(angle)
            circle(draw, x + mid * math.cos(a), y + mid * math.sin(a), w / 2, fill)


def smooth_union(mask, units):
    """Blend the shapes in a mask into one soft outline (no sharp inside corners)."""
    blurred = mask.filter(ImageFilter.GaussianBlur(units * S))
    # Re-threshold with a narrow soft edge so the outline stays crisp.
    return blurred.point(lambda v: 0 if v < 124 else 255 if v > 132 else (v - 124) * 32)


def vertical_gradient(top, bottom):
    a, b = hex_rgb(top), hex_rgb(bottom)
    ramp = Image.new("RGB", (1, 256))
    for yy in range(256):
        t = yy / 255
        ramp.putpixel((0, yy), tuple(round(a[k] + (b[k] - a[k]) * t) for k in range(3)))
    return ramp.resize((MASTER, MASTER), Image.BICUBIC).convert("RGBA")


def soft_light(x, y, radius, colour, strength):
    """A colour that fades out from (x, y): a glow, or a darkening with a dark colour."""
    n = 256
    alpha = Image.new("L", (n, n))
    k = n / UNITS
    for yy in range(n):
        for xx in range(n):
            dist = ((xx / k - x) ** 2 + (yy / k - y) ** 2) ** 0.5 / radius
            t = max(0.0, 1.0 - dist)
            alpha.putpixel((xx, yy), round(255 * strength * t * t * (3 - 2 * t)))
    layer = Image.new("RGBA", (MASTER, MASTER), hex_rgb(colour) + (0,))
    layer.putalpha(alpha.resize((MASTER, MASTER), Image.BICUBIC))
    return layer


def shifted(mask, dx, dy):
    """The mask moved by (dx, dy) units, empty where it moved away."""
    out = new_mask()
    out.paste(mask, (round(dx * S), round(dy * S)))
    return out


def tinted(mask, colour, strength, blur=0.0):
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur * S))
    layer = Image.new("RGBA", (MASTER, MASTER), hex_rgb(colour) + (0,))
    layer.putalpha(mask.point(lambda v: round(v * strength)))
    return layer


def filled(mask, top, bottom):
    """The mask filled with a top-to-bottom gradient."""
    layer = vertical_gradient(top, bottom)
    layer.putalpha(mask)
    return layer


def edge_shade(mask, offset, blur, colour, strength):
    """Soft shade along the glyph's inside edge: the bottom edge for a positive
    offset, the top edge for a negative one."""
    rim = ImageChops.subtract(mask, shifted(mask, 0, -offset))
    soft = rim.filter(ImageFilter.GaussianBlur(blur * S))
    return tinted(ImageChops.multiply(soft, mask), colour, strength)


def background(d):
    """Diagonal gradient with a soft glow and a darker corner."""
    a, b = (hex_rgb(c) for c in d["background"])
    n = 256
    ramp = Image.new("RGB", (n, n))
    pixels = ramp.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            pixels[x, y] = tuple(round(a[k] + (b[k] - a[k]) * t) for k in range(3))
    img = ramp.resize((MASTER, MASTER), Image.BICUBIC).convert("RGBA")
    if d.get("bg_depth"):
        img.alpha_composite(soft_light(*d["bg_depth"]))
    if d.get("bg_glow"):
        img.alpha_composite(soft_light(*d["bg_glow"]))
    return img


def body_mask(d):
    """The camera body and mount, blended into one outline."""
    mask = new_mask()
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(px(*d["mount_box"]), radius=d["mount_radius"] * S, fill=255)
    draw.rounded_rectangle(px(*d["body_box"]), radius=d["body_radius"] * S, fill=255)
    return smooth_union(mask, d["smooth"]) if d.get("smooth") else mask


def ring_mask(d):
    cx, cy = d["centre"]
    outer, inner = d["ring"]
    mask = new_mask()
    draw = ImageDraw.Draw(mask)
    circle(draw, cx, cy, outer, 255)
    circle(draw, cx, cy, inner, 0)
    return mask


def accent_mask(d):
    """The record dot and its Wi-Fi arcs."""
    mask = new_mask()
    draw = ImageDraw.Draw(mask)
    signal_arcs(draw, d, 255)
    circle(draw, *d["rec_dot"], 255)
    return mask


def foreground(d):
    """The camera, on a transparent canvas."""
    cx, cy = d["centre"]
    mask = body_mask(d)
    circle(ImageDraw.Draw(mask), cx, cy, d["lens_hole"], 0)  # see-through opening

    img = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    if d.get("shadow"):
        dx, dy, blur, colour, opacity = d["shadow"]
        img.alpha_composite(tinted(mask, colour, opacity, blur), (round(dx * S), round(dy * S)))

    shade = d.get("glyph_shade", ("#FFFFFF", "#FFFFFF"))
    img.alpha_composite(filled(mask, *shade))
    if d.get("glyph_rim"):
        img.alpha_composite(edge_shade(mask, *d["glyph_rim"]))
    if d.get("glyph_gloss"):
        off, blur, colour, strength = d["glyph_gloss"]
        img.alpha_composite(edge_shade(mask, -off, blur, colour, strength))

    if d.get("lens_depth"):
        # The opening looks recessed: shade along its top inside edge.
        off, blur, colour, strength = d["lens_depth"]
        hole = new_mask()
        circle(ImageDraw.Draw(hole), cx, cy, d["lens_hole"], 255)
        crescent = ImageChops.subtract(hole, shifted(hole, 0, off))
        soft = crescent.filter(ImageFilter.GaussianBlur(blur * S))
        img.alpha_composite(tinted(ImageChops.multiply(soft, hole), colour, strength))

    img.alpha_composite(filled(ring_mask(d), *d.get("ring_shade", shade)))
    img.alpha_composite(filled(accent_mask(d), *d.get("accent_shade", ("#FF4A3D", "#FF4A3D"))))
    return img


def monochrome(d):
    """One-colour shape for themed icons: Android tints the opaque parts."""
    cx, cy = d["centre"]
    mask = body_mask(d)
    circle(ImageDraw.Draw(mask), cx, cy, d["lens_hole"], 0)
    mask = ImageChops.lighter(mask, ring_mask(d))
    # Arcs and dot: cut out where they cross the body, solid where they are outside it.
    mask = ImageChops.difference(mask, accent_mask(d))
    white = Image.new("RGBA", (MASTER, MASTER), (255, 255, 255, 0))
    white.putalpha(mask)
    return white


def squircle_mask(size, power=SQUIRCLE_POWER):
    """Superellipse |x|^n + |y|^n <= 1, drawn 4x and scaled down for smooth edges."""
    big = size * 4 if size < 1024 else size
    steps = 720
    half = big / 2.0
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = abs(c) ** (2 / power) * (1 if c >= 0 else -1)
        y = abs(s) ** (2 / power) * (1 if s >= 0 else -1)
        points.append((half + x * (half - 0.5), half + y * (half - 0.5)))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask if big == size else mask.resize((size, size), Image.LANCZOS)


def legacy(full, size, round_):
    """Icon for launchers without adaptive icons: the visible 72 x 72 middle, masked
    to a circle or to the One UI squircle."""
    lo, hi = round(18 * S), round(90 * S)
    crop = full.crop((lo, lo, hi, hi))
    if round_:
        mask = Image.new("L", crop.size, 0)
        ImageDraw.Draw(mask).ellipse((0, 0, crop.width - 1, crop.height - 1), fill=255)
    else:
        mask = squircle_mask(crop.width)
    out = crop.copy()
    out.putalpha(ImageChops.multiply(crop.getchannel("A"), mask))
    return out.resize((size, size), Image.LANCZOS)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


ADAPTIVE = """<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tools/make_icon.py -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""


def preview(full, mono, path):
    """Large sheet: full canvas, squircle (Samsung), circle, themed version, and the
    squircle at real launcher size."""
    tile = 360
    sheet = Image.new("RGBA", (tile * 4 + 50 + 120, tile + 20), (238, 238, 238, 255))
    themed = Image.new("RGBA", (MASTER, MASTER), (215, 227, 255, 255))
    tint = Image.new("RGBA", (MASTER, MASTER), (16, 47, 96, 255))
    themed.paste(tint, (0, 0), mono)
    shots = [
        full.resize((tile, tile), Image.LANCZOS),
        legacy(full, tile, round_=False),
        legacy(full, tile, round_=True),
        legacy(themed, tile, round_=False),
    ]
    for i, shot in enumerate(shots):
        sheet.alpha_composite(shot, (10 + i * (tile + 10), 10))
    # Real sizes, to judge legibility on the home screen.
    x = 10 + 4 * (tile + 10) + 10
    sheet.alpha_composite(legacy(full, 96, round_=False), (x, 30))
    sheet.alpha_composite(legacy(full, 64, round_=False), (x + 16, 150))
    sheet.alpha_composite(legacy(full, 48, round_=False), (x + 24, 240))
    sheet.convert("RGB").save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--preview", help="also save a preview sheet to this PNG file")
    ap.add_argument("--preview-only", action="store_true",
                    help="with --preview: do not touch the app's icon files")
    a = ap.parse_args()

    bg = background(DESIGN)
    fg = foreground(DESIGN)
    mono = monochrome(DESIGN)
    full = bg.copy()
    full.alpha_composite(fg)

    if a.preview:
        preview(full, mono, a.preview)
        print("Preview saved to %s" % os.path.abspath(a.preview))
        if a.preview_only:
            return

    for density, (layer, icon) in DENSITIES.items():
        folder = os.path.join(RES, "mipmap-" + density)
        os.makedirs(folder, exist_ok=True)
        bg.resize((layer, layer), Image.LANCZOS).convert("RGB").save(
            os.path.join(folder, "ic_launcher_background.png"))
        fg.resize((layer, layer), Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher_foreground.png"))
        mono.resize((layer, layer), Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher_monochrome.png"))
        legacy(full, icon, round_=False).save(os.path.join(folder, "ic_launcher.png"))
        legacy(full, icon, round_=True).save(os.path.join(folder, "ic_launcher_round.png"))
        print("  %-8s layers %dpx, icons %dpx" % (density, layer, icon))

    write(os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"), ADAPTIVE)
    write(os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher_round.xml"), ADAPTIVE)
    # Older versions of this script wrote a flat background colour here.
    old = os.path.join(RES, "values", "ic_launcher_background.xml")
    if os.path.exists(old):
        os.remove(old)
    print("Icons written to %s" % RES)


if __name__ == "__main__":
    main()
