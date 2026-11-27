#!/usr/bin/env python3
"""The Daily look's contrast, every day for ten years and every band (his pick 11-26, item 90).

Reads the colour formulas and the band-table mapping straight out of RisingScale.palette(), and the band numbers and Duet
job 71 oklch tables out of RisingSteps.swift, so the check moves
with the app instead of copying it. hex() (OKLCH to sRGB) is the one part re-done here; its source is fingerprinted, and the
check fails if it changes until this file is updated to match.

Text on ground and on surface: 4.5:1. Accent on ground and surface: 4.5:1 (it is used for words). Key: 3:1 (controls and icons).
Button text on the bordered button's fill (the app tint, which is the key, laid over the surface at BUTTON_FILL): 4.5:1.
Exits 1 on any miss, or if a formula has a shape this reader does not know.
"""
import datetime, hashlib, json, math, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
scale = (ROOT / "PLDev/UI/RisingScale.swift").read_text(encoding="utf-8").replace("\r\n", "\n")
steps = (ROOT / "PLDev/UI/RisingSteps.swift").read_text(encoding="utf-8").replace("\r\n", "\n")

HEX_FINGERPRINT = "bba2897ec3ff"   # first 12 of sha256 over hex()'s source with whitespace removed


def fail(msg):
    print("check_contrast: " + msg)
    sys.exit(1)


def block(src, start, end):
    i = src.find(start)
    j = src.find(end, i + 1)
    if i < 0 or j < 0:
        fail(f"cannot find {start!r} in the Swift source")
    return src[i:j]


# hex() must be the code this file re-does
m = re.search(r"private nonisolated static func hex\(.*?\n    \}\n", scale, re.S)
if not m:
    fail("cannot find RisingScale.hex()")
hex_src = m[0]
fp = hashlib.sha256(re.sub(r"\s+", "", hex_src).encode()).hexdigest()[:12]
if fp != HEX_FINGERPRINT:
    fail(f"RisingScale.hex() changed (fingerprint {fp}); update hex() and HEX_FINGERPRINT here to match it")


def hexcolor(L, C, h):
    c = C
    while True:
        a, b = c * math.cos(h * math.pi / 180), c * math.sin(h * math.pi / 180)
        l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
        m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
        s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
        rgb = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
               -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
               -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
        if all(-0.000001 <= v <= 1.000001 for v in rgb) or c <= 0:
            out = []
            for v in rgb:
                x = min(max(v, 0), 1)
                out.append(int(round((12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055) * 255)))
            return out
        c = max(0, c - 0.005)


# Swift expression to Python: `a ?? b`, `step?.x`, `step?.x.map { ... $0 ... }`, arithmetic, f[i]
def split_top(e, op):
    parts, depth, i, last = [], 0, 0, 0
    while i < len(e):
        ch = e[i]
        if ch in "([{": depth += 1
        elif ch in ")]}": depth -= 1
        elif depth == 0 and e.startswith(op, i):
            parts.append(e[last:i]); i += len(op); last = i; continue
        i += 1
    return parts + [e[last:]]


def tr(e):
    e = e.strip()
    parts = split_top(e, "??")
    if len(parts) > 1:
        return f"_nc({tr(parts[0])}, {tr('??'.join(parts[1:]))})"
    m = re.fullmatch(r"step\?\.(\w+)\.map \{ (.*) \}", e)
    if m:
        return f"_map(S('{m[1]}'), lambda v: {tr(m[2].replace('$0', 'v'))})"
    out, i = "", 0
    while i < len(e):
        if e[i] == "(":
            depth, j = 1, i + 1
            while depth:
                depth += {"(": 1, ")": -1}.get(e[j], 0); j += 1
            out += "(" + tr(e[i + 1:j - 1]) + ")"; i = j
        else:
            out += e[i]; i += 1
    out = re.sub(r"step\?\.(\w+)", r"S('\1')", out)
    if not re.fullmatch(r"[\w\s.+\-*/()\[\],':]*", out):
        fail(f"a palette formula has a shape this check does not read: {e!r}")
    return out


pal = block(scale, "nonisolated static func palette()", "nonisolated static func preset()")
lets = {k: tr(v) for k, v in re.findall(r"let (h|c|light) = (.+)", pal)}
if set(lets) != {"h", "c", "light"}:
    fail("palette() no longer sets h, c and light the way this check reads them")


def hex_args(name):
    i = pal.find(name + ": hex(")
    if i < 0:
        fail(f"palette() has no {name}: hex(...)")
    i += len(name) + 6
    depth, j = 1, i
    while depth:
        depth += {"(": 1, ")": -1}.get(pal[j], 0); j += 1
    args = split_top(pal[i:j - 1], ",")
    if len(args) != 3:
        fail(f"{name}: hex(...) does not take three arguments")
    return [tr(a) for a in args]


roles = {r: hex_args(r) for r in ("ground", "text", "key", "accent", "surface")}

# the bands' numbers, read from RisingSteps.swift
bands = {}
for name in ("heavy", "hot", "low", "stuck", "steady", "rising", "lit"):
    i = steps.find(f"static let {name} = RisingStep(")
    if i < 0:
        fail(f"RisingSteps.swift has no {name} step")
    i = steps.find("(", i) + 1
    depth, j = 1, i
    while depth:
        depth += {"(": 1, ")": -1}.get(steps[j], 0); j += 1
    args = steps[i:j - 1]
    vals = {}
    for k in ("hue", "chroma", "light", "turn", "pop"):
        m = re.search(rf"\b{k}: (-?[\d.]+|nil)", args)
        vals[k] = None if (m is None or m[1] == "nil") else float(m[1])
    m = re.search(r"\boklch: (\[\[[-\d., \[\]]*\]\])", args)
    vals["oklch"] = json.loads(m[1]) if m else []
    bands[name] = vals


def lum(rgb):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = map(ch, rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def seed(day):
    d = hashlib.sha256(("pldev-" + day).encode()).digest()
    return [int.from_bytes(d[i * 4:i * 4 + 4], "big") / 4294967296 for i in range(8)]


table = re.search(r'HousePalette\(name: "th-daily", ground: x\[(\d)\], text: x\[(\d)\], key: x\[(\d)\], accent: x\[(\d)\], surface: x\[(\d)\]\)', pal)
if not table or "o.count == 5" not in pal:
    fail("palette() no longer maps a band's oklch table the way this check reads it")
table_roles = dict(zip(("ground", "text", "key", "accent", "surface"), map(int, table.groups())))


def palette(day, step):
    if step is not None and len(step["oklch"]) == 5:   # the band's own table wins, as in palette()
        return {r: hexcolor(*step["oklch"][i]) for r, i in table_roles.items()}
    env = {"f": seed(day), "S": lambda k: None if step is None else step[k],
           "_nc": lambda a, b: a if a is not None else b, "_map": lambda a, fn: None if a is None else fn(a)}
    for k in ("h", "c", "light"):
        env[k] = eval(lets[k], env)
    return {r: hexcolor(*[eval(a, env) for a in args]) for r, args in roles.items()}


BUTTON_FILL = 0.22   # shortcut: SwiftUI's .bordered fill is the tint at roughly this alpha in dark mode; measure on device if it changes


def with_button(p):
    p = dict(p)
    p["button"] = [round(s * (1 - BUTTON_FILL) + k * BUTTON_FILL) for s, k in zip(p["surface"], p["key"])]
    return p


assert abs(ratio([255] * 3, [0] * 3) - 21) < 1e-9 and hexcolor(1, 0, 0) == [255] * 3   # the maths itself

NEEDS = [("text", "ground", 4.5), ("text", "surface", 4.5), ("accent", "ground", 4.5), ("accent", "surface", 4.5),
         ("key", "ground", 3.0), ("key", "surface", 3.0), ("key", "button", 4.5)]
start = datetime.date(2026, 11, 1)
misses, worst = [], {}
for n in range(3650):
    day = (start + datetime.timedelta(days=n)).isoformat()
    for band, step in [("none", None)] + list(bands.items()):
        p = with_button(palette(day, step))
        for fg, bg, need in NEEDS:
            r = ratio(p[fg], p[bg])
            k = (band, fg, bg)
            worst[k] = min(worst.get(k, 99), r)
            if r < need:
                misses.append(f"{day} {band}: {fg} on {bg} {r:.2f} < {need}")

# the card under text must be near opaque over the curves (his 424 screenshot): the surface opacity each card style draws
# at the Daily look's see-through (Theme.swift PLSurface.styled), at least 0.85 for every band
m = re.search(r"t\.through = ([0-9.]+)", scale)
if not m:
    fail("cannot find the Daily look's t.through in RisingScale.preset()")
through = float(m[1])
backing = {"frosted": max(0, 0.5 - through) * 1.8, "clear": max(0, 0.5 - through) * 1.8,
           "solid": 1 - through * 0.6, "outline": (1 - through) * 0.8}
for name in ("heavy", "hot", "low", "stuck", "steady", "rising", "lit"):
    blk = block(steps, f"private static let {name} = RisingStep(", "oklch:")
    cm = re.search(r"card: \.(\w+)", blk)
    style = cm[1] if cm else "frosted"
    o = backing.get(style)
    if o is None:
        fail(f"{name}: card style {style} has no known surface opacity")
    print(f"card    {name:7} {style:8} surface opacity {o:.2f}")
    if o < 0.85:
        misses.append(f"{name}: card surface opacity {o:.2f} < 0.85 ({style})")

for (band, fg, bg), r in sorted(worst.items()):
    print(f"lowest {band:7} {fg:6} on {bg:7} {r:5.2f}")
if misses:
    print("\n".join(misses[:40]))
    fail(f"{len(misses)} colour pairs under their contrast floor across 3,650 days")
print("check_contrast: 3,650 days x 8 looks, every pair at or above its floor")
