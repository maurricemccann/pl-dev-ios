#!/usr/bin/env python3
"""The distinctness test for the themes: 24 of them (15 house, 9 Fun), and no two share more than three of
palette, title face, text face, card style, shape, wallpaper, motion. `--lines` prints the 24 one-liners."""
import itertools, os, re, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "PLDev")
src = open(os.path.join(root, "UI", "Themes.swift"), encoding="utf-8").read()
block = src[src.index("static let builtIn: [PLThemePreset]"):src.index("var chosenWall")]
IOS_FONTS = {"AvenirNext", "Futura", "Georgia", "HelveticaNeue"}   # installed on every iPhone, nothing to bundle
SHAPE = {"0.01": "sharp", "0.1": "sharp", "0.125": "sharp", "0.25": "sharp", "0.5": "cut", "1": "house", "1.125": "house", "1.5": "round", "2": "round", "0.375": "cut", "1.375": "round"}  # ui-themes px values (S353)


def value(body, name, default=None):
    m = re.search(r"\b%s: (house\(\"[^\"]+\"\)|\"[^\"]*\"(?: \+ art \+ \"[^\"]*\")?|[\w.]+)" % name, body)
    return m.group(1).strip('"') if m else default


themes = []
for body in block.split(".init(")[1:]:
    t = {k: value(body, k) for k in ("id", "title", "palette", "face", "text", "dark")}
    rest = body[body.index(" card: "):]
    t.update({k: value(rest, k).lstrip(".") for k in ("card", "radius", "wall", "look", "tile")})
    t["motion"] = "still" if value(body, "calm") == "true" else "moving"
    t["fun"] = value(body, "fun") == "true"
    themes.append(t)

N = len(themes)
assert N == 40, N   # 15 house, 13 Fun, 12 packs
assert sum(t["fun"] for t in themes) == 13, "13 Fun"
for key in ("id", "palette", "wall"):
    assert len({t[key] for t in themes}) == N, "two themes share a " + key
house = [t for t in themes if not t["id"].startswith("pack-")]   # the packs reuse a few faces, as approved
assert len({t["face"] for t in house}) == len(house), "two themes share a face"
SEVEN = ("palette", "face", "text", "card", "radius", "wall", "motion")
for a, b in itertools.combinations(themes, 2):
    same = [k for k in SEVEN if a[k] == b[k]]
    assert len(same) <= 3, (a["id"], b["id"], same)
fonts = os.listdir(os.path.join(root, "Resources", "Fonts"))
for t in themes:
    for token in (t["face"], t["text"]):
        if token.startswith("bundle:") and token != "bundle:system" and token[7:].split("-")[0] not in IOS_FONTS:
            stem = token[7:].split("-")[0]
            assert any(f.startswith(stem) for f in fonts), "not bundled: " + token
    assert t["radius"] in SHAPE, (t["id"], t["radius"])

if "--lines" in sys.argv:
    def face(token):
        m = re.search(r'([\w-]+)\.(?:ttf|otf)', token)
        return m.group(1) if m else token.replace("bundle:", "")

    def wall(spec):
        kind = spec.split("|")[0]
        m = re.search(r'_(\d+)\.\w+', spec)
        if m:
            return "archive piece ..." + m.group(1) + " (" + kind + ")"
        return "his curves" if spec == "curves" else spec.replace("|", " ").replace(" + art + ", "")

    for t in themes:
        print("- **%s**: palette %s, %s; titles %s; text %s; %s cards; %s corners, %s tiles with the %s look; wall %s; %s." % (
            t["title"], t["palette"].replace("th-", ""), "dark" if t["dark"] == "true" else "light", face(t["face"]), face(t["text"]),
            t["card"], SHAPE[t["radius"]], t["tile"], t["look"], wall(t["wall"]), t["motion"]))
print("themes ok: %d, no pair shares more than 3 of 7" % N, file=sys.stderr)
