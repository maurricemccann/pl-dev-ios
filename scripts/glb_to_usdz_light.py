# Blender headless: heavy glb -> light usdz (decimated). Run: blender --factory-startup -b --python glb_to_usdz_light.py -- in.glb out.usdz 0.05
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
src, dst, ratio = a[0], a[1], float(a[2])
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=src)
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new("dec", 'DECIMATE'); m.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.wm.usd_export(filepath=dst, export_animation=True, export_materials=True, export_armatures=True,
                      generate_preview_surface=True, export_textures_mode='NEW', overwrite_textures=True, usdz_downscale_size='1024')
print("OK", dst)
