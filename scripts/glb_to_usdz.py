# Blender headless: glb -> usdz. Run: blender --factory-startup -b --python glb_to_usdz.py -- in.glb out.usdz
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
src, dst = a[0], a[1]
bpy.ops.wm.read_factory_settings(use_empty=True) if False else None
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=src)
bpy.ops.wm.usd_export(filepath=dst, export_animation=True, export_materials=True, export_armatures=True,
                      generate_preview_surface=True, export_textures_mode='NEW', overwrite_textures=True, usdz_downscale_size='1024')
print("OK", dst)
