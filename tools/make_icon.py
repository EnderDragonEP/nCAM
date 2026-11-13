#!/usr/bin/env python3
"""Draws the nCAM launcher icon and writes every Android icon file.

    python tools/make_icon.py                      write the icons into the app
    python tools/make_icon.py --preview icon.png   also save a large preview sheet

Needs Pillow (pip install pillow). Run from anywhere; paths are relative to this file.

What it writes under android/app/src/main/res/:
  mipmap-<density>/ic_launcher_foreground.png   adaptive icon picture (Android 8+)
  mipmap-<density>/ic_launcher_monochrome.png   themed-icon shape (Android 13+)
  mipmap-<density>/ic_launcher.png              square fallback
  mipmap-<density>/ic_launcher_round.png        round fallback
  mipmap-anydpi-v26/ic_launcher.xml, ic_launcher_round.xml
  values/ic_launcher_background.xml             background colour

The drawing is done in the adaptive icon's own units: a 108 x 108 canvas of which
the launcher may show as little as the central circle of radius 33 (the "safe zone").
Everything important stays inside it. Edit the DESIGN section to change the look.
"""
import argparse
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow is needed: pip install pillow")

# ---------------------------------------------------------------- DESIGN
BACKGROUND = "#1565C0"  # the app's blue (also its default theme seed)
BODY = "#FFFFFF"
LENS_OUTER = "#0D1B2A"
LENS_RING = "#1E3A5F"
GLASS_EDGE = "#1E6FD9"
GLASS_CENTRE = "#7CC4FF"
REC = "#FF3B30"

CENTRE = (54.0, 57.0)  # lens centre
BODY_BOX = (26.0, 38.0, 82.0, 76.0)  # left, top, right, bottom
BODY_RADIUS = 9.0
MOUNT_BOX = (45.0, 30.0, 63.0, 40.0)  # the windscreen mount on top
MOUNT_RADIUS = 3.0
LENS_R = 15.0
RING_R = 11.5
GLASS_R = 8.0
HIGHLIGHT = (50.6, 53.4, 2.4)  # x, y, radius
REC_DOT = (74.0, 45.5, 3.4)  # x, y, radius
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


def radial(draw, x, y, r, inner, outer, steps=60):
    """A disc that fades from `outer` at its edge to `inner` at its centre."""
    a, b = hex_rgb(outer), hex_rgb(inner)
    for i in range(steps):
        t = i / (steps - 1)
        colour = tuple(round(a[k] + (b[k] - a[k]) * t) for k in range(3))
        circle(draw, x, y, r * (1 - t * 0.85), colour + (255,))


def foreground():
    """The camera, on a transparent canvas."""
    img = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(px(*MOUNT_BOX), radius=MOUNT_RADIUS * S, fill=BODY)
    d.rounded_rectangle(px(*BODY_BOX), radius=BODY_RADIUS * S, fill=BODY)
    cx, cy = CENTRE
    circle(d, cx, cy, LENS_R, LENS_OUTER)
    circle(d, cx, cy, RING_R, LENS_RING)
    radial(d, cx, cy, GLASS_R, GLASS_CENTRE, GLASS_EDGE)
    circle(d, *HIGHLIGHT, (255, 255, 255, 220))
    circle(d, *REC_DOT, REC)
    return img


def monochrome():
    """One-colour shape for themed icons: Android tints the opaque parts."""
    img = Image.new("L", (MASTER, MASTER), 0)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(px(*MOUNT_BOX), radius=MOUNT_RADIUS * S, fill=255)
    d.rounded_rectangle(px(*BODY_BOX), radius=BODY_RADIUS * S, fill=255)
    cx, cy = CENTRE
    circle(d, cx, cy, LENS_R, 0)  # lens opening
    circle(d, cx, cy, GLASS_R + 1.0, 255)  # glass
    circle(d, *REC_DOT, 0)  # record dot as a hole
    white = Image.new("RGBA", (MASTER, MASTER), (255, 255, 255, 0))
    white.putalpha(img)
    return white


def composite(fg):
    img = Image.new("RGBA", (MASTER, MASTER), hex_rgb(BACKGROUND) + (255,))
    img.alpha_composite(fg)
    return img


def legacy(full, size, round_):
    """Pre-Android-8 style icon: the visible 72 x 72 middle, masked."""
    lo, hi = round(18 * S), round(90 * S)
    crop = full.crop((lo, lo, hi, hi))
    mask = Image.new("L", crop.size, 0)
    md = ImageDraw.Draw(mask)
    if round_:
        md.ellipse((0, 0, crop.width - 1, crop.height - 1), fill=255)
    else:
        md.rounded_rectangle(
            (0, 0, crop.width - 1, crop.height - 1), radius=crop.width * 0.22, fill=255
        )
    out = Image.new("RGBA", crop.size, (0, 0, 0, 0))
    out.paste(crop, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


ADAPTIVE = """<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tools/make_icon.py -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""


def preview(fg, mono, path):
    """Large sheet: full icon, as a circle, as a squircle, and the themed version."""
    full = composite(fg)
    tile = 360
    sheet = Image.new("RGBA", (tile * 4 + 50, tile + 20), (238, 238, 238, 255))
    shots = [
        full.resize((tile, tile), Image.LANCZOS),
        legacy(full, tile, round_=True),
        legacy(full, tile, round_=False),
    ]
    themed = Image.new("RGBA", (MASTER, MASTER), (215, 227, 255, 255))
    tint = Image.new("RGBA", (MASTER, MASTER), (16, 47, 96, 255))
    themed.paste(tint, (0, 0), mono)
    shots.append(legacy(themed, tile, round_=True))
    for i, shot in enumerate(shots):
        sheet.alpha_composite(shot, (10 + i * (tile + 10), 10))
    sheet.convert("RGB").save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--preview", help="also save a preview sheet to this PNG file")
    a = ap.parse_args()

    fg = foreground()
    mono = monochrome()
    full = composite(fg)

    for density, (layer, icon) in DENSITIES.items():
        folder = os.path.join(RES, "mipmap-" + density)
        os.makedirs(folder, exist_ok=True)
        fg.resize((layer, layer), Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher_foreground.png"))
        mono.resize((layer, layer), Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher_monochrome.png"))
        legacy(full, icon, round_=False).save(os.path.join(folder, "ic_launcher.png"))
        legacy(full, icon, round_=True).save(os.path.join(folder, "ic_launcher_round.png"))
        print("  %-8s layers %dpx, icons %dpx" % (density, layer, icon))

    write(os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"), ADAPTIVE)
    write(os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher_round.xml"), ADAPTIVE)
    write(os.path.join(RES, "values", "ic_launcher_background.xml"),
          '<?xml version="1.0" encoding="utf-8"?>\n'
          "<!-- Generated by tools/make_icon.py -->\n"
          "<resources>\n"
          '    <color name="ic_launcher_background">%s</color>\n'
          "</resources>\n" % BACKGROUND)
    print("Icons written to %s" % RES)

    if a.preview:
        preview(fg, mono, a.preview)
        print("Preview saved to %s" % os.path.abspath(a.preview))


if __name__ == "__main__":
    main()
