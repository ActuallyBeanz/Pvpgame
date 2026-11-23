# Generates bow, arrow, quiver (Megabonk-style: low poly + 32px nearest textures).
# Blender +Y = forward (exports to Godot -Z). Run: python3 make_weapons.py -- <out_dir>
import bpy, bmesh, random, math, os, sys
from mathutils import Vector

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
 "wood":    noise_tex("tex_bowwood", [(176,112,58),(150,92,46),(198,136,72),(110,66,32)], [.5,.25,.2,.05], 3,
                      lambda x, y, r: y % 6 == 0 and r.random() < .7),
 "leather": noise_tex("tex_leather", [(122,62,40),(104,52,34),(140,76,50),(70,36,24)], [.5,.3,.15,.05], 4,
                      lambda x, y, r: (x % 8 == 0 and y % 2 == 0)),
 "metal":   noise_tex("tex_metal", [(168,176,186),(140,148,160),(206,214,222),(96,102,112)], [.45,.3,.2,.05], 5),
 "feather": noise_tex("tex_feather", [(214,58,48),(236,96,72),(178,40,36),(250,240,226)], [.5,.25,.15,.1], 6,
                      lambda x, y, r: x % 11 == 0),
 "string":  noise_tex("tex_string", [(236,226,196),(214,202,170)], [.7,.3], 7),
 "brass":   noise_tex("tex_brass", [(222,178,72),(196,150,52),(246,214,120)], [.5,.3,.2], 8),
}
MATS = {}
for k, img in T.items():
    m = bpy.data.materials.new(k)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.45 if k in ("metal", "brass") else 0.85
    b.inputs["Metallic"].default_value = 0.6 if k in ("metal", "brass") else 0.0
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
    """Collects parts (one bmesh per material) into a single object."""
    def __init__(self): self.parts = {}
    def bm(self, mat):
        return self.parts.setdefault(mat, bmesh.new())
    def box(self, mat, center, size, rot=None):
        bm = self.bm(mat)
        r = bmesh.ops.create_cube(bm, size=1.0)
        vs = r["verts"]
        for v in vs:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
            if rot: v.co = rot @ v.co
            v.co += Vector(center)
        return vs
    def rings(self, mat, rings, cap_start=True, cap_end=True):
        """rings: list of lists of Vector (same count) -> lofted tube."""
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

def ring_rect(center, w, d):  # rectangle in XY plane (for vertical loft)
    x, y, z = center
    return [Vector((x - w, y - d, z)), Vector((x + w, y - d, z)), Vector((x + w, y + d, z)), Vector((x - w, y + d, z))]

# ---------------- BOW (vertical, grip at origin, shoots +Y, string at -Y) ----------------
b = Builder()
L, BEND = 0.62, 0.30               # limb length, how far tips curve back toward the archer
def limb(sign):
    rings = []
    for i in range(7):
        t = i / 6
        z = sign * (0.09 + t * L)
        y = -BEND * t * t + 0.03 * math.sin(t * math.pi)   # slight recurve
        w, d = 0.036 * (1 - 0.45 * t), 0.028 * (1 - 0.35 * t)
        rings.append(ring_rect((0, y, z), w, d))
    if sign < 0: rings.reverse()
    return rings
b.rings("wood", limb(1)); b.rings("wood", limb(-1))
b.rings("leather", [ring_rect((0, 0.005, z), 0.042, 0.036) for z in (-0.11, 0.0, 0.11)])   # grip wrap
b.box("wood", (0, 0.0, 0.0), (0.06, 0.05, 0.2))                                            # riser core
tipz, tipy = 0.09 + L, -BEND + 0.0
for s in (1, -1):
    b.box("brass", (0, tipy, s * tipz), (0.05, 0.04, 0.05))                                 # nocks
b.box("string", (0, tipy - 0.02, 0), (0.012, 0.012, 2 * tipz))                               # string
b.box("brass", (0, 0.045, 0.03), (0.02, 0.03, 0.03))                                         # arrow rest
bow = b.build("Bow", {"wood": 0.25, "leather": 0.15, "brass": 0.1, "string": 0.2})

# ---------------- ARROW (points +Y, origin at the tip) ----------------
a = Builder()
LEN = 0.78
a.rings("wood", [ring_rect((0, 0, 0), 0.011, 0.011)], False, False) if False else None
shaft = [[Vector((sx * 0.011, -0.07 - t * (LEN - 0.07), sz * 0.011)) for sx, sz in ((-1,-1),(1,-1),(1,1),(-1,1))] for t in (0, 1)]
a.rings("wood", shaft)
# head: 4-sided pyramid
bmh = a.bm("metal")
base = [bmh.verts.new((x, -0.075, z)) for x, z in ((-0.035, 0), (0, -0.018), (0.035, 0), (0, 0.018))]
tip = bmh.verts.new((0, 0.0, 0))
back = bmh.verts.new((0, -0.1, 0))
for i in range(4):
    bmh.faces.new((base[i], base[(i+1) % 4], tip))
    bmh.faces.new((base[(i+1) % 4], base[i], back))
# fletching: 3 vanes
for k in range(3):
    ang = k * math.tau / 3
    from mathutils import Matrix
    rot = Matrix.Rotation(ang, 3, 'Y')
    a.box("feather", (0, 0, 0), (0.004, 0.16, 0.05), rot)
    vs = a.bm("feather").verts[-8:]
    for v in vs: v.co += rot @ Vector((0, 0, 0.035)) + Vector((0, -LEN + 0.1, 0))
a.box("string", (0, -LEN + 0.005, 0), (0.026, 0.02, 0.026))      # nock
arrow = a.build("Arrow", {"wood": 0.4, "metal": 0.06, "feather": 0.12, "string": 0.1})

# ---------------- QUIVER (vertical, origin at centre, opening at +Z) ----------------
q = Builder()
SIDES, H, R = 6, 0.58, 0.085
def ring6(z, r): return [Vector((math.cos(i / SIDES * math.tau) * r, math.sin(i / SIDES * math.tau) * r, z)) for i in range(SIDES)]
q.rings("leather", [ring6(-H/2, R * 0.9), ring6(-H/2 + 0.05, R), ring6(H/2, R * 1.08)], True, False)
q.rings("brass", [ring6(H/2 - 0.04, R * 1.12), ring6(H/2 + 0.005, R * 1.12)], False, False)
q.rings("brass", [ring6(-H/2 + 0.02, R * 1.0), ring6(-H/2 + 0.07, R * 1.04)], False, False)
q.box("leather", (0, -R - 0.012, 0.0), (0.05, 0.02, H * 0.9))                   # strap along the back
rq = random.Random(11)
for i in range(5):                                                               # arrows poking out
    ang = i / 5 * math.tau + 0.3
    x, y = math.cos(ang) * R * 0.45, math.sin(ang) * R * 0.45
    tilt = rq.uniform(-0.04, 0.04)
    q.box("wood", (x + tilt, y, H/2 + 0.06), (0.018, 0.018, 0.14))
    q.box("feather", (x + tilt, y, H/2 + 0.15), (0.05, 0.008, 0.09), None)
    q.box("feather", (x + tilt, y, H/2 + 0.15), (0.008, 0.05, 0.09), None)
quiver = q.build("Quiver", {"leather": 0.2, "brass": 0.1, "wood": 0.3, "feather": 0.12})

def export(ob, name):
    for o in bpy.context.scene.objects: o.select_set(False)
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dims = [round(d, 3) for d in ob.dimensions]
    print("EXPORT", name, "tris", tris, "dims", dims)

bow.location = (0, 0, 0); arrow.location = (0, 0, 0); quiver.location = (0, 0, 0)
export(bow, "bow_basic"); export(arrow, "arrow_basic"); export(quiver, "quiver_basic")
bow.location = (-0.6, 0, 0.7); arrow.location = (0, 0.4, 0.7); arrow.rotation_euler = (0, 0, math.radians(-90)); quiver.location = (0.6, 0, 0.35)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "weapons_bow_set.blend"))
