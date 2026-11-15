#!/usr/bin/env python3
"""Fails when a section of the bundled toolkit JSON is missing, mis-shaped or empty.

Why (11-14): the Swift read papers, gestures and the Quick menu as bare arrays, but the toolkit wraps each as
{"_about": ..., "<inner>": [...]}. They loaded empty, so the New canvas Stock dropdown had nothing to select, and nothing noticed.
Each row below is (section, inner key or None for a bare list, minimum count). Keep it in step with NativeToolkit.swift.
Run: python3 scripts/check_toolkit.py     (also in the logic workflow)
"""
import json, os, sys

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "PLDev", "Sections", "Paint", "Native", "NativeToolkit.json")
EXPECT = [
    ("packs", None, 4), ("kitPalettes", None, 3),
    ("canvases", "presets", 3), ("papers", "papers", 2), ("gestures", "gestures", 3),
    ("quickmenu", "profiles", 1), ("study", "exercises", 1), ("names", "qualities", 3), ("colourSense", "families", 1),
]


def main():
    d = json.load(open(PATH, encoding="utf-8"))
    bad = []
    for section, inner, least in EXPECT:
        v = d.get(section)
        rows = v if inner is None else (v.get(inner) if isinstance(v, dict) else None)
        if not isinstance(rows, list):
            bad.append("%s%s is not a list (found %s)" % (section, "" if inner is None else "." + inner, type(v).__name__))
        elif len(rows) < least:
            bad.append("%s%s has %d, needs at least %d" % (section, "" if inner is None else "." + inner, len(rows), least))
    for k in ("defaults", "schema"):
        if not isinstance(d.get(k), dict) or not d[k]:
            bad.append("%s is missing or empty" % k)
    hb = json.load(open(os.path.join(os.path.dirname(PATH), "NativeHandbook.json"), encoding="utf-8"))
    if not isinstance(hb, dict) or not isinstance(hb.get("chapters"), list) or len(hb["chapters"]) < 10:
        bad.append("NativeHandbook.json: chapters is not a list of at least 10")
    if bad:
        print("TOOLKIT SHAPE CHECK FAILED:\n  " + "\n  ".join(bad))
        sys.exit(1)
    print("toolkit shape ok: " + ", ".join("%s=%d" % (s, len((d[s] if i is None else d[s][i]))) for s, i, _ in EXPECT))


if __name__ == "__main__":
    main()
