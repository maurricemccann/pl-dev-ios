# Blender headless: his clip pack (glyphguy-v4-clips.glb) -> one skeleton-only USDZ per clip, on the world model's own bone names.
# Run: blender --factory-startup -b --python clips_to_usdz.py -- world.glb clips.glb outdir
import bpy, sys, os
a = sys.argv[sys.argv.index("--") + 1:]
world, clips, out = a
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=world)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
before = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=clips)
new = [x for x in bpy.data.actions if x not in before]
# the exporter writes a clip only when a skinned mesh is bound to the skeleton, and only well when it is his real skinning:
# keep the model's own meshes (weights intact) but decimate them to almost nothing, so each clip is the animation and not 6 MB of mesh
stub = None
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    md = o.modifiers.new('dec', 'DECIMATE'); md.ratio = 0.02
    with bpy.context.temp_override(object=o, active_object=o): bpy.ops.object.modifier_apply(modifier=md.name)
    stub = stub or o
for o in list(bpy.data.objects):          # drop the clip pack's own objects; keep the world model
    if o.type == 'ARMATURE' and o is not arm: bpy.data.objects.remove(o)
names = [b.name for b in arm.pose.bones]
colon = any(':' in n for n in names)
os.makedirs(out, exist_ok=True)
if not arm.animation_data: arm.animation_data_create()
for act in new:
    fcs = []
    if hasattr(act, 'fcurves'): fcs = list(act.fcurves)
    else:   # Blender 5: layered actions, curves live in channelbags per slot
        for l in act.layers:
            for st in l.strips:
                for cb in st.channelbags: fcs += list(cb.fcurves)
    for fc in fcs:
        if colon and 'mixamorig:' not in fc.data_path: fc.data_path = fc.data_path.replace('["mixamorig', '["mixamorig:')
    arm.animation_data.action = act
    if hasattr(arm.animation_data, 'action_slot') and act.slots: arm.animation_data.action_slot = act.slots[0]
    s, e = act.frame_range
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = int(s), int(e)
    for o in bpy.data.objects: o.select_set(False)
    arm.select_set(True); bpy.context.view_layer.objects.active = arm
    for o in bpy.data.objects:
        if o.type == 'MESH': o.select_set(True)
    p = os.path.join(out, "clip-" + act.name.replace(" ", "-") + ".usdz")
    bpy.ops.wm.usd_export(filepath=p, selected_objects_only=True, export_animation=True, export_armatures=True, export_materials=False)
    print("CLIP", act.name, len(fcs), int(s), int(e), os.path.getsize(p) if os.path.exists(p) else "MISSING")
