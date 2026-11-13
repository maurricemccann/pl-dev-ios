# Blender headless: heart1.glb -> heart1.usdz, standing upright (the page rotates the model +90 degrees about X: its GLB up is -Z),
# half the triangles. Run: blender --factory-startup -b --python heart_to_usdz.py -- in.glb out.usdz
import bpy, sys, math
a = sys.argv[sys.argv.index("--") + 1:]
src, dst = a[0], a[1]
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=src)
roots = [o for o in bpy.data.objects if o.parent is None]
holder = bpy.data.objects.new("upright", None)
bpy.context.scene.collection.objects.link(holder)
for o in roots: o.parent = holder
holder.rotation_euler = (math.pi / 2, 0, 0)
for o in bpy.data.objects:
    if o.type == 'MESH':
        bpy.context.view_layer.objects.active = o
        m = o.modifiers.new("d", 'DECIMATE'); m.ratio = 0.5
        bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.wm.usd_export(filepath=dst, export_materials=True, generate_preview_surface=True, export_textures_mode='NEW', overwrite_textures=True, usdz_downscale_size='1024')
print("OK", dst)
