"""Put his baked GlyphGuy clips onto his own model, in one glb (stdlib only).

  python scripts/merge_glyph_clips.py <model.glb> <clips.glb> <out.glb>

The clips glb (pl-curves-gallery public/glyphguy/glyphguy-v4-clips.glb) holds 24 animations baked onto the v4 rig, bones only,
with three.js-cleaned names (mixamorigHips). The model glb (glyphguy-v4-world.glb, the source of PL DEV's usdz) names the same
bones mixamorig:Hips. This appends every clip animation to the model, retargeting each channel to the model node of the same
name with the colon removed. Fails loud if any channel finds no node.
"""
import json, struct, sys


def read(p):
    b = open(p, "rb").read()
    assert b[:4] == b"glTF", p + " is not a glb"
    jl = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20 + jl])
    o = 20 + jl
    bin_ = b""
    if o < len(b):
        bl, bt = struct.unpack_from("<II", b, o)
        assert bt == 0x004E4942, "second chunk is not BIN"
        bin_ = b[o + 8:o + 8 + bl]
    return j, bin_


def pad(b, n=4, fill=b"\x00"):
    return b + fill * ((n - len(b) % n) % n)


def merge(model, clips):
    (m, mb), (c, cb) = model, clips
    key = lambda s: (s or "").replace(":", "")
    by_name = {key(n.get("name")): i for i, n in enumerate(m["nodes"])}
    mb = pad(mb)
    base = len(mb)
    view0, acc0 = len(m.get("bufferViews", [])), len(m.get("accessors", []))
    for v in c["bufferViews"]:
        v = dict(v); v["buffer"] = 0; v["byteOffset"] = v.get("byteOffset", 0) + base
        m.setdefault("bufferViews", []).append(v)
    for a in c["accessors"]:
        a = dict(a)
        if "bufferView" in a: a["bufferView"] += view0
        m.setdefault("accessors", []).append(a)
    missing = set()
    for an in c["animations"]:
        an = json.loads(json.dumps(an))
        for s in an["samplers"]:
            s["input"] += acc0; s["output"] += acc0
        for ch in an["channels"]:
            nm = key(c["nodes"][ch["target"]["node"]].get("name"))
            if nm not in by_name: missing.add(nm); continue
            ch["target"]["node"] = by_name[nm]
        m.setdefault("animations", []).append(an)
    if missing:
        sys.exit("merge_glyph_clips: no model node for " + ", ".join(sorted(missing)))
    allb = mb + cb
    m["buffers"] = [{"byteLength": len(allb)}]
    return m, allb


def write(p, j, b):
    js = pad(json.dumps(j, separators=(",", ":")).encode(), fill=b" ")
    b = pad(b)
    total = 12 + 8 + len(js) + 8 + len(b)
    with open(p, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(b), 0x004E4942)); f.write(b)


if __name__ == "__main__":
    mdl, clp, out = sys.argv[1:4]
    j, b = merge(read(mdl), read(clp))
    write(out, j, b)
    j2, b2 = read(out)   # self-check: it reads back, every animation targets a skinned model node
    names = [n.get("name") for n in j2["nodes"]]
    assert len(j2["animations"]) == len(read(clp)[0]["animations"]) + len(read(mdl)[0].get("animations", []))
    assert all(names[ch["target"]["node"]].startswith("mixamorig:") for a in j2["animations"] for ch in a["channels"])
    print("OK", out, len(j2["animations"]), "animations,", len(b2), "bytes of data")
