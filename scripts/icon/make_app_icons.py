#!/usr/bin/env python3
"""Draws every PL DEV app icon: a metal bar with his heart mark in Liquid Glass, thick enough to read at 60 pt and 29 pt.

Usage: python scripts/icon/make_app_icons.py [--only name] [--preview]   (run from the repo root; needs Chrome and Pillow)

His ruling (11-14, build 152 on his phone: "Logo isn't on app icon"): a gold bar with his heart mark in Liquid Glass in the
centre. The first drawing had the glass as a thin pale outline that vanished at home-screen size, so here the glass body is
thick (the mark is dilated), it sits bigger in the frame, and a dark amber edge and shadow separate it from the metal.
The mark is the pl-os heart (pl-os public/logo.svg, kept beside this file as mark-symbol.svgfrag). Chrome renders the SVG
(its lighting filters give the glass); Pillow only reads the result back and writes the opaque 1024 PNGs.
"""
import argparse
import os
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "PLDev", "Resources", "Assets.xcassets")
HERE = os.path.dirname(os.path.abspath(__file__))
CHROME = next((p for p in (r"C:\Program Files\Google\Chrome\Application\chrome.exe", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "google-chrome", "chromium") if os.path.exists(p) or "/" not in p and "\\" not in p), None)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexs(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v)))) for v in c)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def light(h, t):
    return hexs(mix(rgb(h), (255, 255, 255), t))


def dark(h, t):
    return hexs(mix(rgb(h), (0, 0, 0), t))


# name -> (outer ground, metal key, glass tint, mode)
GOLD = "#c9a84c"
VARIANTS = {
    "gold": dict(path="AppIcon.appiconset/icon-1024.png", ground=None, key=GOLD, gold=True),
    "gold-dark": dict(path="AppIcon.appiconset/icon-1024-dark.png", ground=None, key=GOLD, gold=True, shade=0.42),
    "gold-tinted": dict(path="AppIcon.appiconset/icon-1024-tinted.png", ground=None, key=GOLD, gold=True, gray=True),
    "obsidian-gold": dict(path="AppIcon-ObsidianGold.appiconset/icon.png", ground="#0e0c08", key="#c9a84c"),
    "void-ember": dict(path="AppIcon-VoidEmber.appiconset/icon.png", ground="#0a0807", key="#d4550a"),
    "deep-indigo": dict(path="AppIcon-DeepIndigo.appiconset/icon.png", ground="#080810", key="#6a7fd4"),
    "bone-oxblood": dict(path="AppIcon-BoneOxblood.appiconset/icon.png", ground="#f0ece4", key="#7c1f1f"),
    "home-screen": dict(path="AppIcon-HomeScreen.appiconset/icon.png", ground="#5a1f0e", key="#b85536"),
}


def svg(v):
    key = v["key"]
    if v.get("gold"):   # the original bullion stops, kept so the default icon stays itself
        bar = ["#fbe9a6", "#e9c868", "#c9982f", "#e4bd58", "#9c6c18"]
        panel = ["#f3d77f", "#d4a640", "#b7832a"]
        outer = bar
    else:
        bar = [light(key, .55), light(key, .25), key, light(key, .2), dark(key, .45)]
        panel = [light(key, .3), key, dark(key, .22)]
        g = v["ground"]
        outer = [light(g, .10), light(g, .04), g, light(g, .05), dark(g, .35)]
    shade = v.get("shade", 0)
    if shade:
        bar = [dark(c, shade) for c in bar]; panel = [dark(c, shade) for c in panel]; outer = [dark(c, shade) for c in outer]
    if v.get("gray"):   # tinted appearance: iOS maps the luminance to the user's tint, so keep a dark bar and a bright mark
        outer = ["#2a2a2a", "#222", "#1b1b1b", "#202020", "#101010"]
        panel = ["#5a5a5a", "#444", "#303030"]
    sym = open(os.path.join(HERE, "mark-symbol.svgfrag"), encoding="utf8").read()
    S = 832; X = 512 - S / 2; Y = 512 - S / 2 + 6
    # glass: dilate the thin ribbon so it has a body, then a white fill, a specular sheen from the top left, a bright rim
    # inside the edge and a dark amber edge + shadow underneath so it separates from the metal at 60 pt
    dark_edge = "#2a1500" if not v.get("gray") else "#000"
    return f"""<html><body style="margin:0;background:#000"><svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs>
 <linearGradient id="bar" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="{outer[0]}"/><stop offset=".22" stop-color="{outer[1]}"/><stop offset=".48" stop-color="{outer[2]}"/><stop offset=".7" stop-color="{outer[3]}"/><stop offset="1" stop-color="{outer[4]}"/></linearGradient>
 <linearGradient id="panel" x1="0" y1="0" x2="0.3" y2="1"><stop offset="0" stop-color="{panel[0]}"/><stop offset=".5" stop-color="{panel[1]}"/><stop offset="1" stop-color="{panel[2]}"/></linearGradient>
 <linearGradient id="hi" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".9"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".7"/></linearGradient>
 <filter id="brush" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.0015 0.35" numOctaves="2" seed="7"/><feColorMatrix values="0 0 0 0 1  0 0 0 0 .95  0 0 0 0 .8  0 0 0 .22 0"/><feComposite in2="SourceGraphic" operator="in"/></filter>
 {sym}
 <filter id="glass" x="-20%" y="-20%" width="140%" height="140%">
  <feMorphology in="SourceAlpha" operator="dilate" radius="5.5" result="a"/>
  <feGaussianBlur in="a" stdDeviation="3" result="a3"/>
  <feGaussianBlur in="a" stdDeviation="16" result="sh0"/><feOffset in="sh0" dx="8" dy="20" result="sh1"/>
  <feFlood flood-color="{dark_edge}" flood-opacity=".8"/><feComposite in2="sh1" operator="in" result="shadow"/>
  <feMorphology in="a" operator="dilate" radius="3" result="aBig"/>
  <feFlood flood-color="{dark_edge}" flood-opacity=".75"/><feComposite in2="aBig" operator="in" result="edgeDark"/>
  <feFlood flood-color="#fffaf0" flood-opacity=".52"/><feComposite in2="a" operator="in" result="body"/>
  <feSpecularLighting in="a3" surfaceScale="10" specularConstant="1.3" specularExponent="20" lighting-color="#fff" result="s"><feDistantLight azimuth="235" elevation="38"/></feSpecularLighting>
  <feComposite in="s" in2="a" operator="in" result="spec"/>
  <feMorphology in="a" operator="erode" radius="2.4" result="inner"/>
  <feComposite in="a" in2="inner" operator="out" result="rim"/>
  <feFlood flood-color="#fff" flood-opacity="1"/><feComposite in2="rim" operator="in" result="rimW"/>
  <feOffset in="rim" dx="-2" dy="-3" result="rim2"/><feFlood flood-color="{dark_edge}" flood-opacity=".5"/><feComposite in2="rim2" operator="in" result="rimD"/>
  <feMerge><feMergeNode in="shadow"/><feMergeNode in="edgeDark"/><feMergeNode in="body"/><feMergeNode in="rimD"/><feMergeNode in="spec"/><feMergeNode in="rimW"/></feMerge>
 </filter>
</defs>
<rect width="1024" height="1024" fill="url(#bar)"/>
<rect width="1024" height="1024" fill="#fff" filter="url(#brush)"/>
<rect x="78" y="78" width="868" height="868" rx="120" fill="url(#panel)"/>
<rect x="78" y="78" width="868" height="868" rx="120" fill="#fff" filter="url(#brush)" opacity=".8"/>
<rect x="80" y="80" width="864" height="864" rx="118" fill="none" stroke="url(#hi)" stroke-width="7"/>
<use href="#m" x="{X}" y="{Y}" width="{S}" height="{S}" fill="#fff" filter="url(#glass)"/>
</svg></body></html>"""


def render(name, v, outdir):
    html = os.path.join(outdir, name + ".html")
    png = os.path.join(outdir, name + ".png")
    open(html, "w", encoding="utf8").write(svg(v))
    prof = os.path.join(outdir, "chrome-profile")
    subprocess.run([CHROME, "--headless=new", "--user-data-dir=" + prof, "--window-size=1024,1024", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--screenshot=" + png, "file:///" + html.replace("\\", "/")],
                   check=True, capture_output=True, timeout=120)
    im = Image.open(png).convert("RGB")
    assert im.size == (1024, 1024), im.size
    if v.get("gray"):
        im = im.convert("L").convert("RGB")
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--preview", action="store_true", help="write full previews into the temp folder, not into the asset catalogue")
    a = ap.parse_args()
    if not CHROME:
        sys.exit("Chrome not found")
    out = tempfile.mkdtemp(prefix="pl-icons-")
    for name, v in VARIANTS.items():
        if a.only and a.only != name:
            continue
        im = render(name, v, out)
        dest = os.path.join(out, "preview-" + name + ".png") if a.preview else os.path.join(ASSETS, v["path"])
        im.save(dest, "PNG", optimize=True)
        # the sizes he will actually see: 180 px = 60 pt @3x, 87 px = 29 pt @3x, 60 and 29 px at 1x
        strip = Image.new("RGB", (180 + 87 + 60 + 29 + 50, 190), (24, 24, 24)); x = 10
        for s in (180, 87, 60, 29):
            strip.paste(im.resize((s, s), Image.LANCZOS), (x, 5)); x += s + 10
        strip.save(os.path.join(out, "preview-strip-" + name + ".png"))  # in the temp folder, never committed
        print(name, "->", dest, im.size, im.mode)


if __name__ == "__main__":
    main()
