# Blender headless: one usdz per clip from the merged glb (merge_glyph_clips.py), each the whole GlyphGuy with that one move.
# Run: blender --factory-startup -b --python glyph_clip_usdz.py -- merged.glb out_dir clip1 [clip2 ...]
# Written as clip-<name>.usdz, the names PLWHeroFigure already loads. Same export settings as glb_to_usdz.py (which made the model).
import bpy, sys, os
a = sys.argv[sys.argv.index("--") + 1:]
src, out, names = a[0], a[1], a[2:]
os.makedirs(out, exist_ok=True)
for name in names:
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    act = bpy.data.actions.get(name) or next((x for x in bpy.data.actions if x.name.startswith(name)), None)
    if act is None:
        sys.exit("glyph_clip_usdz: no action " + name + " in " + ", ".join(x.name for x in bpy.data.actions))
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None):
        ad.action_slot = act.slots[0]
    for t in list(ad.nla_tracks): ad.nla_tracks.remove(t)
    f0, f1 = (int(x) for x in act.frame_range)
    sc = bpy.context.scene; sc.frame_start, sc.frame_end = f0, max(f1, f0 + 1)
    dst = os.path.join(out, "clip-" + name + ".usdz")
    bpy.ops.wm.usd_export(filepath=dst, export_animation=True, export_materials=True, export_armatures=True,
                          generate_preview_surface=True, export_textures_mode='NEW', overwrite_textures=True, usdz_downscale_size='1024')
    print("RESULT OK", dst, f0, f1)
