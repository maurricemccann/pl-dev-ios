# GlyphGirl from his GlyphGuy v4 world model, by the `buildHer` recipe (pl-curves-gallery scripts/glyphguy/glyph-rig.js): the body (rect9) and the
# head-and-torso parts are reshaped into a triangle (narrow at the top, flared at the hem) and the two arm strokes move in to the new shoulders.
# The skeleton is NOT touched, so every clip made for GlyphGuy plays on her unchanged (a clip rewrites joint translations, so moving bones would not hold).
# Run: blender --factory-startup -b --python derive_glyphgirl.py -- in.glb out.usdz [preview.png]
import bpy, sys, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
src, dst = a[0], a[1]
preview = a[2] if len(a) > 2 else None
NECK, FLARE, ARM_GAP = 0.3, 0.86, 1.3           # buildHer defaults

for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=src)
bpy.context.view_layer.update()
mesh = {o.name: o for o in bpy.data.objects if o.type == 'MESH'}
body = mesh["rect9"]
parts = [mesh["rect9"], mesh["UV SphereASSEMBLY"]]

def world(o): return [o.matrix_world @ v.co for v in o.data.vertices]
w = world(body)                                  # Blender: x across, z up (three.js: x across, y up)
lo, hi = min(v.z for v in w), max(v.z for v in w)
xl, xh = min(v.x for v in w), max(v.x for v in w)
szx = xh - xl; half = szx / 2; cx = (xl + xh) / 2
sw = szx * 0.11; topW = szx * NECK; hemW = szx * FLARE
smooth = lambda a_: a_ * a_ * (3 - 2 * a_)
for o in parts:
    inv = o.matrix_world.inverted()
    for v in o.data.vertices:
        p = o.matrix_world @ v.co
        t = min(1, max(0, (p.z - lo) / (hi - lo)))
        want = hemW + (topW - hemW) * t
        d = p.x - cx
        a_ = min(1, abs(d) / half)
        p.x += math.copysign(1, d) * (want - half) * smooth(a_) if d != 0 else 0
        v.co = inv @ p
    o.data.update()

shift = szx * 0.5 - topW - sw * ARM_GAP
for name in ("path14", "path16"):               # the arm strokes move in; their bones stay, see the header
    o = mesh[name]; inv = o.matrix_world.inverted()
    mx = sum((o.matrix_world @ v.co).x for v in o.data.vertices) / len(o.data.vertices)
    dirx = math.copysign(1, cx - mx)
    for v in o.data.vertices:
        p = o.matrix_world @ v.co; p.x += dirx * shift; v.co = inv @ p
    o.data.update()
for o in mesh.values(): o.data.calc_loop_triangles()
print("SHIFT", shift, "szx", szx, "height", hi - lo)

if preview:
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = (hi - lo) * 1.6
    cam.location = (cx, -60, (lo + hi) / 2 + 0); cam.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = cam; sc.render.engine = 'BLENDER_WORKBENCH'
    sc.render.resolution_x = 700; sc.render.resolution_y = 900; sc.render.filepath = preview
    sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'MATERIAL'
    bpy.ops.render.render(write_still=True)

bpy.ops.wm.usd_export(filepath=dst, export_animation=True, export_materials=True, export_armatures=True,
                      generate_preview_surface=True, export_textures_mode='NEW', overwrite_textures=True, usdz_downscale_size='1024')
print("OK", dst)
