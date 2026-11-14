#!/usr/bin/env python3
"""Draws the placeholder icons: a plain dark square with a light ring and dot. No brand asset.

Usage: python3 scripts/make_icons.py   (needs Pillow; run from anywhere)
Writes the three toolbar icons of the Safari extension. The app icon (gold heart mark, glass heart in its centre,
his ruling 11-13) is drawn from the pl-os heart mark and committed as PNGs; this script no longer touches it. Run it again only if the mark changes; the PNGs are committed.
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DARK = (22, 22, 26)
LIGHT = (236, 236, 240)


def mark(size, alpha):
    """Drawn at four times the size, then reduced, so the edges are smooth."""
    big = size * 4
    img = Image.new("RGBA" if alpha else "RGB", (big, big), DARK + ((255,) if alpha else ()))
    d = ImageDraw.Draw(img)
    c = big / 2
    r = big * 0.30
    d.ellipse([c - r, c - r, c + r, c + r], outline=LIGHT, width=max(2, int(big * 0.055)))
    r = big * 0.09
    d.ellipse([c - r, c - r, c + r, c + r], fill=LIGHT)
    return img.resize((size, size), Image.LANCZOS)


def main():
    out = {
        "PLDevSafari/Resources/icon-48.png": (48, True),
        "PLDevSafari/Resources/icon-96.png": (96, True),
        "PLDevSafari/Resources/icon-128.png": (128, True),
    }
    for rel, (size, alpha) in out.items():
        path = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        mark(size, alpha).save(path, "PNG")
        check = Image.open(path)
        assert check.size == (size, size) and (check.mode == "RGBA") == alpha, f"{rel}: wrong size or mode"
        print(f"{rel}: {size} px, {check.mode}")


if __name__ == "__main__":
    main()
