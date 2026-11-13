#!/usr/bin/env python3
"""Draws the nCAM launcher icon and writes every Android icon file.

    python tools/make_icon.py                       One UI style (the default)
    python tools/make_icon.py --style classic       the first, more detailed design
    python tools/make_icon.py --preview icon.png    also save a large preview sheet

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
Everything important stays inside it. Edit the STYLES section to change the look.
"""
import argparse
import os
import sys

try:
    from PIL import Image, ImageChops, ImageDraw
except ImportError:
    sys.exit("Pillow is needed: pip install pillow")

# ---------------------------------------------------------------- STYLES
STYLES = {
    # Samsung One UI look: a soft diagonal gradient, and one bold, flat, white glyph
    # with generous rounding and no fine detail. The lens is a hole that shows the
    # background through, with a white ring inside it.
    "oneui": {
        "background": ("#4FA3FF", "#1259D9"),  # top-left -> bottom-right
        "body": "#FFFFFF",
        "body_box": (32.0, 43.0, 76.0, 72.5),  # left, top, right, bottom
        "body_radius": 9.0,
        "mount_box": (45.8, 36.0, 62.2, 46.0),
        "mount_radius": 3.7,
        "centre": (54.0, 57.5),  # lens centre
        "lens_hole": 10.2,  # radius of the see-through lens opening
        "ring": (6.1, 3.3),  # white ring inside the lens: outer, inner radius
        "rec_dot": (69.2, 49.0, 2.3),  # x, y, radius
        "rec_colour": "#FF4A3D",
        "signal_radii": (4.8, 7.8, 10.8),  # radio arcs around the record dot
        "signal_width": 1.7,
    },
    # The first design: flat blue, a dark lens with a shaded blue glass.
    "classic": {
        "background": ("#1565C0", "#1565C0"),
        "body": "#FFFFFF",
        "body_box": (26.0, 38.0, 82.0, 76.0),
        "body_radius": 9.0,
        "mount_box": (45.0, 30.0, 63.0, 40.0),
        "mount_radius": 3.0,
        "centre": (54.0, 57.0),
        "lens": {  # detailed lens instead of a hole
            "outer": (15.0, "#0D1B2A"),
            "ring": (11.5, "#1E3A5F"),
            "glass": (8.0, "#7CC4FF", "#1E6FD9"),  # radius, centre colour, edge colour
            "highlight": (50.6, 53.4, 2.4),
        },
        "rec_dot": (74.0, 45.5, 3.4),
        "rec_colour": "#FF3B30",
        "signal_radii": (3.8, 6.6, 9.4),
        "signal_width": 1.7,
    },
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


def signal_arcs(draw, style, fill):
    """Draw three upper-right radio arcs around the record indicator."""
    x, y, _ = style["rec_dot"]
    width = max(1, round(style["signal_width"] * S))
    for radius in style["signal_radii"]:
        draw.arc(px(x - radius, y - radius, x + radius, y + radius),
                 start=270, end=360, fill=fill, width=width)


def radial(draw, x, y, r, inner, outer, steps=60):
    """A disc that fades from `outer` at its edge to `inner` at its centre."""
    a, b = hex_rgb(outer), hex_rgb(inner)
    for i in range(steps):
        t = i / (steps - 1)
        colour = tuple(round(a[k] + (b[k] - a[k]) * t) for k in range(3))
        circle(draw, x, y, r * (1 - t * 0.85), colour + (255,))


def background(style):
    """Full-canvas diagonal gradient (or a flat colour when both ends match)."""
    a, b = (hex_rgb(c) for c in style["background"])
    if a == b:
        return Image.new("RGBA", (MASTER, MASTER), a + (255,))
    # Build a small diagonal ramp and scale it up: smooth and fast.
    n = 256
    ramp = Image.new("RGB", (n, n))
    pixels = ramp.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            pixels[x, y] = tuple(round(a[k] + (b[k] - a[k]) * t) for k in range(3))
    return ramp.resize((MASTER, MASTER), Image.BICUBIC).convert("RGBA")


def body_mask(style):
    """The camera body and mount as a greyscale mask."""
    mask = Image.new("L", (MASTER, MASTER), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle(px(*style["mount_box"]), radius=style["mount_radius"] * S, fill=255)
    d.rounded_rectangle(px(*style["body_box"]), radius=style["body_radius"] * S, fill=255)
    return mask


def foreground(style):
    """The camera, on a transparent canvas."""
    cx, cy = style["centre"]
    mask = body_mask(style)
    md = ImageDraw.Draw(mask)
    if "lens_hole" in style:
        circle(md, cx, cy, style["lens_hole"], 0)  # see-through opening
        outer, inner = style["ring"]
        circle(md, cx, cy, outer, 255)
        circle(md, cx, cy, inner, 0)
    img = Image.new("RGBA", (MASTER, MASTER), hex_rgb(style["body"]) + (0,))
    img.putalpha(mask)
    d = ImageDraw.Draw(img)
    lens = style.get("lens")
    if lens:
        circle(d, cx, cy, lens["outer"][0], lens["outer"][1])
        circle(d, cx, cy, lens["ring"][0], lens["ring"][1])
        r, centre_colour, edge_colour = lens["glass"]
        radial(d, cx, cy, r, centre_colour, edge_colour)
        circle(d, *lens["highlight"], (255, 255, 255, 220))
    signal_arcs(d, style, style["rec_colour"])
    circle(d, *style["rec_dot"], style["rec_colour"])
    return img


def monochrome(style):
    """One-colour shape for themed icons: Android tints the opaque parts."""
    cx, cy = style["centre"]
    mask = body_mask(style)
    d = ImageDraw.Draw(mask)
    if "lens_hole" in style:
        circle(d, cx, cy, style["lens_hole"], 0)
        outer, inner = style["ring"]
        circle(d, cx, cy, outer, 255)
        circle(d, cx, cy, inner, 0)
    else:
        circle(d, cx, cy, style["lens"]["outer"][0], 0)
        circle(d, cx, cy, style["lens"]["glass"][0] + 1.0, 255)
    signal_arcs(d, style, 0)  # radio detail as cutouts in themed icons
    circle(d, *style["rec_dot"], 0)  # record dot as a hole
    white = Image.new("RGBA", (MASTER, MASTER), (255, 255, 255, 0))
    white.putalpha(mask)
    return white


def squircle_mask(size, power=SQUIRCLE_POWER):
    """Superellipse |x|^n + |y|^n <= 1, drawn 4x and scaled down for smooth edges."""
    big = size * 4 if size < 1024 else size
    steps = 720
    half = big / 2.0
    points = []
    import math
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
    ap.add_argument("--style", choices=sorted(STYLES), default="oneui")
    ap.add_argument("--preview", help="also save a preview sheet to this PNG file")
    ap.add_argument("--preview-only", action="store_true",
                    help="with --preview: do not touch the app's icon files")
    a = ap.parse_args()
    style = STYLES[a.style]

    bg = background(style)
    fg = foreground(style)
    mono = monochrome(style)
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
    print("Icons (%s style) written to %s" % (a.style, RES))


if __name__ == "__main__":
    main()
