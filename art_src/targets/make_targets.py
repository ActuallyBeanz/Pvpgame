# Generates training dummy, archery target, boomerang (Megabonk-style: low poly + 32px nearest textures).
# Blender +Y = forward (exports to Godot -Z), Z up, origin at the ground (props) / spin centre (boomerang).
# Run inside Blender with sys.argv[-1] = output dir (see make_weapons.py for the same pipeline).
import bpy, bmesh, random, math, os, sys
from mathutils import Vector, Matrix

OUT = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)

def srgb(c): return tuple(v / 255.0 for v in c)

def make_img(name, painter, size=32):
    img = bpy.data.images.new(name, size, size, alpha=False)
    px = []
    for y in range(size):
        for x in range(size):
            px += [*painter(x, y), 1.0]
    img.pixels = px
    img.filepath_raw = os.path.join(OUT, name + ".png"); img.file_format = 'PNG'; img.save()
    return img

def noise_tex(name, palette, weights, seed, stripes=None):
    r = random.Random(seed)
    def p(x, y):
        if stripes and stripes(x, y, r):
            return srgb(palette[-1])
        v, acc = r.random(), 0.0
        for c, w in zip(palette, weights):
            acc += w
            if v < acc: return srgb(c)
        return srgb(palette[0])
    return make_img(name, p)

T = {
 "wood":   noise_tex("tex_dummywood", [(170,118,70),(146,98,56),(192,140,88),(104,68,38)], [.5,.25,.2,.05], 21,
                     lambda x, y, r: y % 5 == 0 and r.random() < .6),
 "darkwood": noise_tex("tex_darkwood", [(102,70,46),(86,58,38),(122,86,58),(62,42,28)], [.5,.25,.2,.05], 22,
                     lambda x, y, r: y % 6 == 0 and r.random() < .6),
 "straw":  noise_tex("tex_straw", [(226,190,92),(204,166,70),(244,214,124),(168,130,52)], [.45,.3,.17,.08], 23,
                     lambda x, y, r: (x + y // 3) % 7 == 0 and r.random() < .5),
 "burlap": noise_tex("tex_burlap", [(186,150,104),(166,132,90),(204,170,124),(132,102,68)], [.45,.3,.17,.08], 24,
                     lambda x, y, r: (x % 3 == 0 and y % 3 == 0)),
 "rope":   noise_tex("tex_rope", [(150,112,70),(128,94,58),(176,136,90)], [.5,.3,.2], 25,
                     lambda x, y, r: (x + y) % 4 == 0),
 "red":    noise_tex("tex_paint_red", [(206,52,44),(190,44,38),(222,70,58)], [.6,.25,.15], 26),
 "white":  noise_tex("tex_paint_white", [(240,234,218),(226,220,204),(250,246,236)], [.6,.25,.15], 27),
 "gold":   noise_tex("tex_paint_gold", [(244,196,60),(226,176,44),(252,216,104)], [.6,.25,.15], 28),
 "teal":   noise_tex("tex_paint_teal", [(40,170,170),(30,148,150),(70,196,190)], [.6,.25,.15], 29),
 "brass":  noise_tex("tex_brass2", [(222,178,72),(196,150,52),(246,214,120)], [.5,.3,.2], 30),
}
MATS = {}
for k, img in T.items():
    m = bpy.data.materials.new(k)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.45 if k == "brass" else 0.9
    b.inputs["Metallic"].default_value = 0.6 if k == "brass" else 0.0
    t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = img; t.interpolation = 'Closest'
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    MATS[k] = m

def cube_uv(bm, texel):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal; ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            c = l.vert.co
            u, v = [(c.y, c.z), (c.x, c.z), (c.x, c.y)][ax]
            l[uv].uv = (u / texel, v / texel)

class Builder:
    def __init__(self): self.parts = {}
    def bm(self, mat): return self.parts.setdefault(mat, bmesh.new())
    def box(self, mat, center, size, rot=None):
        bm = self.bm(mat)
        for v in bmesh.ops.create_cube(bm, size=1.0)["verts"]:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
            if rot: v.co = rot @ v.co
            v.co += Vector(center)
    def rings(self, mat, rings, cap_start=True, cap_end=True):
        bm = self.bm(mat)
        vv = [[bm.verts.new(p) for p in ring] for ring in rings]
        n = len(rings[0])
        for i in range(len(vv) - 1):
            for s in range(n):
                bm.faces.new((vv[i][s], vv[i][(s+1) % n], vv[i+1][(s+1) % n], vv[i+1][s]))
        if cap_start: bm.faces.new(list(reversed(vv[0])))
        if cap_end: bm.faces.new(vv[-1])
    def build(self, name, texels):
        me = bpy.data.meshes.new(name)
        merged = bmesh.new()
        for i, (mat, bm) in enumerate(self.parts.items()):
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.normal_update(); cube_uv(bm, texels.get(mat, 0.3))
            tmp = bpy.data.meshes.new("tmp"); bm.to_mesh(tmp); bm.free()
            for p in tmp.polygons: p.material_index = i
            merged.from_mesh(tmp); bpy.data.meshes.remove(tmp)
        merged.to_mesh(me); merged.free()
        for mat in self.parts: me.materials.append(MATS[mat])
        for p in me.polygons: p.use_smooth = False
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob

def ngon_z(z, r, sides=8, cx=0.0, cy=0.0, rot=0.0):     # ring around the Z axis
    return [Vector((cx + math.cos(rot + i / sides * math.tau) * r, cy + math.sin(rot + i / sides * math.tau) * r, z)) for i in range(sides)]

def ngon_y(y, r, sides=12, cz=0.0):                      # ring around the Y axis (faces +Y)
    return [Vector((math.cos(i / sides * math.tau) * r, y, cz + math.sin(i / sides * math.tau) * r)) for i in range(sides)]

# ---------------- TRAINING DUMMY (≈1.85m, faces +Y) ----------------
d = Builder()
d.box("darkwood", (0, 0, 0.04), (0.9, 0.14, 0.08))                       # cross feet
d.box("darkwood", (0, 0, 0.04), (0.14, 0.9, 0.08))
d.box("wood", (0, 0, 0.55), (0.13, 0.13, 1.0))                           # post
sack = [(0.74, 0.17), (0.80, 0.25), (0.98, 0.30), (1.18, 0.31), (1.36, 0.28), (1.46, 0.20), (1.50, 0.12)]
d.rings("straw", [ngon_z(z, r, 8, rot=math.pi / 8) for z, r in sack])    # straw body
for z, r in ((0.86, 0.285), (1.30, 0.305)):                              # rope bands
    d.rings("rope", [ngon_z(z - 0.03, r, 8, rot=math.pi / 8), ngon_z(z + 0.03, r, 8, rot=math.pi / 8)], False, False)
d.box("wood", (0, 0, 1.24), (1.15, 0.09, 0.09))                          # arm bar
rs = random.Random(5)
for s in (1, -1):                                                        # straw tufts on the arms
    for k in range(3):
        a = (k - 1) * 0.5
        rot = Matrix.Rotation(a, 3, 'Y') @ Matrix.Rotation(rs.uniform(-.3, .3), 3, 'Z')
        d.box("straw", (s * 0.62, 0, 1.24), (0.16, 0.05, 0.03), rot)
    d.box("rope", (s * 0.52, 0, 1.24), (0.05, 0.12, 0.12))
head = [(1.52, 0.08), (1.58, 0.16), (1.68, 0.19), (1.78, 0.17), (1.85, 0.09), (1.87, 0.03)]
d.rings("burlap", [ngon_z(z, r, 8, rot=math.pi / 8) for z, r in head])   # burlap head
d.rings("rope", [ngon_z(1.535, 0.11, 8, rot=math.pi / 8), ngon_z(1.575, 0.13, 8, rot=math.pi / 8)], False, False)
d.box("rope", (0, 0, 1.91), (0.04, 0.04, 0.08))                          # tie knot on top
# painted target patch on the chest (front = +Y)
for i, (mat, r) in enumerate((("white", 0.17), ("red", 0.12), ("white", 0.075), ("red", 0.035))):
    y = 0.30 + 0.012 * (i + 1)
    d.rings(mat, [ngon_y(y - 0.012, r, 10, cz=1.12), ngon_y(y, r, 10, cz=1.12)], False, True)
# button eyes
for s in (1, -1):
    d.box("darkwood", (s * 0.07, 0.18, 1.72), (0.04, 0.03, 0.04))
dummy = d.build("TargetDummy", {"wood": 0.3, "darkwood": 0.3, "straw": 0.25, "burlap": 0.2, "rope": 0.1,
                               "red": 0.3, "white": 0.3})

# ---------------- ARCHERY TARGET (face +Y, centre 1.25m) ----------------
a = Builder()
CZ, R, DEP = 1.25, 0.62, 0.22
a.rings("straw", [ngon_y(-DEP / 2, R, 12, CZ), ngon_y(DEP / 2, R, 12, CZ)])   # straw butt
for z in (-0.35, 0.0, 0.35):                                                  # binding ropes around the bale
    pass
for i, (mat, r) in enumerate((("white", 0.58), ("red", 0.46), ("white", 0.34), ("red", 0.22), ("gold", 0.10))):
    y = DEP / 2 + 0.008 * (i + 1)
    a.rings(mat, [ngon_y(y - 0.008, r, 12, CZ), ngon_y(y, r, 12, CZ)], False, True)
legs = [((0.42, 0.10, 0.0), (0.18, 0.06, 1.9)), ((-0.42, 0.10, 0.0), (-0.18, 0.06, 1.9)), ((0, -0.75, 0.0), (0, -0.16, 1.7))]
for p0, p1 in legs:                                                           # easel legs
    p0, p1 = Vector(p0), Vector(p1)
    mid, dv = (p0 + p1) / 2, p1 - p0
    rot = Vector((0, 0, 1)).rotation_difference(dv.normalized()).to_matrix()
    a.box("wood", mid, (0.07, 0.07, dv.length), rot)
a.box("wood", (0, 0.0, 0.55), (0.9, 0.07, 0.07))                              # shelf bar the bale rests on
a.box("rope", (0, 0.0, CZ + R - 0.05), (0.14, DEP + 0.04, 0.05))              # top tie
archery = a.build("ArcheryTarget", {"wood": 0.3, "straw": 0.25, "rope": 0.1, "red": 0.4, "white": 0.4, "gold": 0.2})

# ---------------- BOOMERANG (flat in XY, spin centre at origin, ≈0.5m span) ----------------
bmr = Builder()
TH = 0.022
def arm(sign):
    # quad strip along a bent arm: from centre elbow out to the tip
    pts = []
    for i in range(6):
        t = i / 5
        ang = sign * math.radians(52) - sign * math.radians(14) * t      # slight curve
        dist = 0.03 + t * 0.26
        c = Vector((math.sin(ang) * dist, math.cos(ang) * dist - 0.06, 0))
        w = 0.055 * (1 - 0.35 * t)
        side = Vector((math.cos(ang), -math.sin(ang), 0)) * w
        pts.append((c, side))
    return pts
for sign in (1, -1):
    pts = arm(sign)
    rings = [[c - s + Vector((0, 0, -TH)), c + s + Vector((0, 0, -TH)), c + s + Vector((0, 0, TH)), c - s + Vector((0, 0, TH))] for c, s in pts]
    bmr.rings("wood", rings)
    c, s = pts[-1]
    bmr.box("brass", c + (c - pts[-2][0]).normalized() * 0.01, (0.06, 0.05, TH * 2.4),
            Matrix.Rotation(-math.atan2(c.x - pts[-2][0].x, c.y - pts[-2][0].y), 3, 'Z'))     # tip caps
    c2, s2 = pts[2]
    bmr.box("teal", c2, (0.03, 0.11, TH * 2.3), Matrix.Rotation(-math.atan2(c2.x, c2.y + 0.06), 3, 'Z'))  # painted band
bmr.box("wood", (0, -0.03, 0), (0.11, 0.09, TH * 2))                                         # elbow block
bmr.box("teal", (0, -0.03, 0), (0.05, 0.05, TH * 2.3))                                        # centre gem
boomerang = bmr.build("Boomerang", {"wood": 0.3, "brass": 0.1, "teal": 0.1})

def export(ob, name):
    for o in bpy.context.scene.objects: o.select_set(False)
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("EXPORT", name, "tris", tris, "dims", [round(v, 3) for v in ob.dimensions])
    return {"name": name, "tris": tris, "dims": [round(v, 3) for v in ob.dimensions]}

info = [export(dummy, "target_dummy"), export(archery, "archery_target"), export(boomerang, "boomerang_basic")]
dummy.location = (-1.4, 0, 0); archery.location = (0.2, 0, 0); boomerang.location = (1.5, 0, 0.9)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "targets_set.blend"))
