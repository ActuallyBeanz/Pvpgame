# Renders a quick preview of weapons_grapple_set.blend (Workbench, textured).
# Run: blender -b weapons_grapple_set.blend -P preview_grapples.py -- <out.png>
import bpy, sys, math
from mathutils import Vector
out = sys.argv[-1]
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x, sc.render.resolution_y = 900, 600
sc.world = bpy.data.worlds.new("w") if sc.world is None else sc.world
cam = bpy.data.cameras.new("c"); co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co)
sc.camera = co
co.location = Vector((1.9, -1.1, 1.0))
d = Vector((0.35, 0.3, 0.15)) - co.location
co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
cam.lens = 40
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
