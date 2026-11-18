# Blender headless: a Mixamo move (FBX, rig only, any Mixamo character) re-fitted onto HIS GlyphGuy v4 rig, written as a light clip usdz.
# Run: blender --factory-startup -b --python retarget_mixamo_usdz.py -- glyphguy-v4-world.glb in.fbx out_dir clip-name [--keep-hips-height]
#
# Why not copy rotations: the Mixamo rig's bones rest at other angles than his (measured S350: up to 171 deg at the hands, 32 at the
# feet), so each bone's turn is moved over relative to its own rest, in world space: target = (source pose * source rest^-1) * target rest.
# Hips travel is dropped (the game moves him), except its height change when --keep-hips-height (landing dips), scaled to his size.
# The body inside is decimated to 2% with no materials (the app only borrows the motion), as glyph_clip_usdz.py --light.
# Raw Mixamo FBX never enter a repo (licence); only the usdz this writes does.
import bpy, sys, os
from mathutils import Matrix

a = sys.argv[sys.argv.index("--") + 1:]
glb, fbx, out, name = a[0], a[1], a[2], a[3]
keep_h = "--keep-hips-height" in a
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
tgt = next(o for o in bpy.data.objects if o.type == "ARMATURE")
for act in list(bpy.data.actions): bpy.data.actions.remove(act)
bpy.ops.import_scene.fbx(filepath=fbx)
src = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o != tgt)
sact = src.animation_data.action
f0, f1 = (int(x) for x in sact.frame_range)
key = lambda n: n.replace(":", "").replace("mixamorig", "")
smap = {key(b.name): b.name for b in src.pose.bones}
order = [pb for pb in tgt.pose.bones]          # parents come before children in Blender's list
order.sort(key=lambda pb: len(pb.parent_recursive))
pairs = [(pb, src.pose.bones[smap[key(pb.name)]]) for pb in order if key(pb.name) in smap]
missing = [pb.name for pb in order if key(pb.name) not in smap]
if missing:
    sys.exit("retarget_mixamo_usdz: no source bone for " + ", ".join(missing))

def world_rest(ob, pb): return (ob.matrix_world @ pb.bone.matrix_local).to_quaternion()
rest = {pb.name: (world_rest(src, sp), world_rest(tgt, pb)) for pb, sp in pairs}
hips_t, hips_s = tgt.pose.bones[pairs[0][0].name], pairs[0][1]
scale = (tgt.matrix_world @ hips_t.bone.head_local).z / max((src.matrix_world @ hips_s.bone.head_local).z, 1e-6)

print("RESULT rotation modes before", sorted(set(pb.rotation_mode for pb in tgt.pose.bones)))
for pb in tgt.pose.bones: pb.rotation_mode = "QUATERNION"   # the keys below are quaternions; a bone left in Euler would ignore them
tgt.animation_data_create(); tact = bpy.data.actions.new(name); tgt.animation_data.action = tact
sc = bpy.context.scene
for f in range(f0, f1 + 1):
    sc.frame_set(f)
    for pb, sp in pairs:
        srest, trest = rest[pb.name]
        spose = (src.matrix_world @ sp.matrix).to_quaternion()
        want = (spose @ srest.inverted()) @ trest                          # the source bone's turn from rest, laid on his rest
        cur = tgt.matrix_world @ pb.matrix
        loc = cur.to_translation()
        if pb is hips_t and keep_h:
            dz = ((src.matrix_world @ sp.matrix).to_translation().z - (src.matrix_world @ hips_s.bone.head_local).z) * scale
            loc = (tgt.matrix_world @ hips_t.bone.head_local); loc.z += dz
        elif pb is hips_t:
            loc = tgt.matrix_world @ hips_t.bone.head_local
        pb.matrix = tgt.matrix_world.inverted() @ Matrix.LocRotScale(loc, want, cur.to_scale())
        bpy.context.view_layer.update()
        pb.keyframe_insert("rotation_quaternion", frame=f)
        if pb is hips_t: pb.keyframe_insert("location", frame=f)
    if "--debug" in a:
        def up(ob, b): m = ob.matrix_world @ b.matrix; return tuple(round(x, 2) for x in (m.to_quaternion() @ __import__("mathutils").Vector((0, 1, 0))))
        hd_s, hd_t = src.pose.bones[smap["Head"]], tgt.pose.bones[[pb.name for pb, _ in pairs if key(pb.name) == "Head"][0]]
        sp_s, sp_t = src.pose.bones[smap["Spine"]], tgt.pose.bones[[pb.name for pb, _ in pairs if key(pb.name) == "Spine"][0]]
        print("RESULT f", f, "head src", up(src, hd_s), "tgt", up(tgt, hd_t), "spine src", up(src, sp_s), "tgt", up(tgt, sp_t))

# playback check: read the stored move back and compare each bone with what the bake set (fails loud past 5 degrees)
import math
want_by = {}
for f in range(f0, f1 + 1):
    sc.frame_set(f)
    want_by[f] = {pb.name: ((spm := (src.matrix_world @ sp.matrix).to_quaternion()) @ rest[pb.name][0].inverted()) @ rest[pb.name][1] for pb, sp in pairs}
bad = []
for f in range(f0, f1 + 1):
    sc.frame_set(f)
    for pb, _ in pairs:
        got = (tgt.matrix_world @ pb.matrix).to_quaternion()
        d = math.degrees(got.rotation_difference(want_by[f][pb.name]).angle)
        if d > 5 and d < 355: bad.append((f, pb.name, round(d)))
print("RESULT playback check:", "OK" if not bad else f"{len(bad)} bone-frames off, worst {sorted(bad, key=lambda x: -x[2])[:4]}")
if bad: sys.exit("retarget_mixamo_usdz: playback does not match the bake")
bpy.data.objects.remove(src, do_unlink=True)
if "--render" in a:                                   # eyes: his full body at three points of the move, side and front, before it is shrunk
    rdir = a[a.index("--render") + 1]; os.makedirs(rdir, exist_ok=True)
    from mathutils import Vector
    sc.render.engine = "BLENDER_WORKBENCH"; sc.render.resolution_x, sc.render.resolution_y = 360, 480
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "SINGLE"
    pts = [o.matrix_world @ Vector(c) for o in bpy.data.objects if o.type == "MESH" for c in o.bound_box]
    ctr = sum(pts, Vector()) / len(pts); h = max(p.z for p in pts) - min(p.z for p in pts)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = h * 1.25
    for f in (f0, (f0 + f1) // 2, f0 + (f1 - f0) // 4):
        sc.frame_set(f)
        for view, off in (("side", Vector((h * 4, 0, 0))), ("front", Vector((0, -h * 4, 0))), ("q", Vector((h * 3, -h * 3, h * 0.8)))):
            cam.location = ctr + off
            cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = os.path.join(rdir, f"{name}-{view}-f{f}.png"); bpy.ops.render.render(write_still=True)
for o in [o for o in bpy.data.objects if o.type == "MESH"]:
    o.data.materials.clear()
    m = o.modifiers.new("light", "DECIMATE"); m.ratio = 0.02
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
sc.frame_start, sc.frame_end = f0, max(f1, f0 + 1)
os.makedirs(out, exist_ok=True)
dst = os.path.join(out, "clip-" + name + ".usdz")
bpy.ops.wm.usd_export(filepath=dst, export_animation=True, export_materials=True, export_armatures=True,
                      generate_preview_surface=False, export_textures_mode='NEW', overwrite_textures=True, usdz_downscale_size='1024')
print("RESULT OK", dst, f0, f1, "hips scale", round(scale, 3))
