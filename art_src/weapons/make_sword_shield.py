# Generates the Dawnsteel Blade (sword) and Gildcrest Shield. Megabonk-style: chunky low
# poly + 32px nearest-filtered noise textures, a few emissive accents for "epic".
# Original designs (no Zelda emblems). Blender Z up = Godot Y up; Blender -Y = Godot +Z.
#   Sword: blade along +Z (Godot +Y), origin at the grip centre, guard along X, flat in Y.
#   Shield: face toward -Y (Godot +Z), origin at the handle on the back.
# Run: python3 make_sword_shield.py -- <out_dir>
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
 "steel":   noise_tex("tex_steel", [(196,206,218),(170,180,194),(228,236,244),(130,138,150)], [.45,.3,.2,.05], 21,
                      lambda x, y, r: x % 16 == 0 and r.random() < .5),
 "gold":    noise_tex("tex_gold", [(232,184,64),(206,156,44),(252,222,120),(160,112,30)], [.5,.25,.2,.05], 22),
 "leather": noise_tex("tex_grip", [(92,52,38),(76,42,30),(118,70,50),(52,28,20)], [.5,.3,.15,.05], 23,
                      lambda x, y, r: (x + y) % 6 == 0),
 "paint":   noise_tex("tex_shieldpaint", [(32,110,128),(26,94,112),(44,132,150),(18,70,86)], [.5,.28,.17,.05], 24),
 "wood":    noise_tex("tex_shieldwood", [(120,80,48),(100,64,38),(140,96,58),(70,44,26)], [.5,.3,.15,.05], 25,
                      lambda x, y, r: y % 5 == 0 and r.random() < .6),
}
MATS = {}
for k, img in T.items():
    m = bpy.data.materials.new(k)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    metal = k in ("steel", "gold")
    b.inputs["Roughness"].default_value = 0.35 if metal else 0.85
    b.inputs["Metallic"].default_value = 0.7 if metal else 0.0
    t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = img; t.interpolation = 'Closest'
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    MATS[k] = m


def glow_mat(name, color, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(color), 1.0)
    b.inputs["Emission Color"].default_value = (*srgb(color), 1.0)
    b.inputs["Emission Strength"].default_value = strength
    b.inputs["Roughness"].default_value = 0.2
    MATS[name] = m


glow_mat("rune", (90, 230, 255), 2.5)      # blade rune strip
glow_mat("gem", (60, 160, 255), 3.0)       # guard / pommel gems
glow_mat("sun", (255, 226, 130), 1.2)      # shield emblem core


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
        for v in r["verts"]:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
            if rot: v.co = rot @ v.co
            v.co += Vector(center)
        return r["verts"]
    def rings(self, mat, rings, cap_start=True, cap_end=True):
        bm = self.bm(mat)
        vv = [[bm.verts.new(p) for p in ring] for ring in rings]
        n = len(rings[0])
        for i in range(len(vv) - 1):
            for s in range(n):
                bm.faces.new((vv[i][s], vv[i][(s+1) % n], vv[i+1][(s+1) % n], vv[i+1][s]))
        if cap_start: bm.faces.new(list(reversed(vv[0])))
        if cap_end: bm.faces.new(vv[-1])
        return vv
    def cone_tip(self, mat, ring, tip):
        bm = self.bm(mat)
        vs = [bm.verts.new(p) for p in ring]
        t = bm.verts.new(tip)
        for i in range(len(vs)):
            bm.faces.new((vs[i], vs[(i+1) % len(vs)], t))
    def octa(self, mat, c, r):
        bm = self.bm(mat)
        c = Vector(c)
        pts = [bm.verts.new(c + Vector(d)) for d in ((r,0,0),(0,r*0.6,0),(-r,0,0),(0,-r*0.6,0))]
        top = bm.verts.new(c + Vector((0, 0, r))); bot = bm.verts.new(c + Vector((0, 0, -r)))
        for i in range(4):
            bm.faces.new((pts[i], pts[(i+1) % 4], top))
            bm.faces.new((pts[(i+1) % 4], pts[i], bot))
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


def diamond(z, w, t, x=0.0):   # blade cross-section: wide in X, thin in Y, sharp edges
    return [Vector((x - w, 0, z)), Vector((x, -t, z)), Vector((x + w, 0, z)), Vector((x, t, z))]


def octagon(z, r):
    return [Vector((math.cos(i / 8 * math.tau) * r, math.sin(i / 8 * math.tau) * r, z)) for i in range(8)]


# ======================= DAWNSTEEL BLADE (~1.55 units; character scale 0.8 -> ~1.25 m) =====
s = Builder()
# blade: flared base, slim waist, leaf swell, point
prof = [(0.07, 0.085), (0.14, 0.072), (0.40, 0.062), (0.78, 0.068), (1.02, 0.058), (1.14, 0.04)]
s.rings("steel", [diamond(z, w, 0.026) for z, w in prof], True, False)
s.cone_tip("steel", diamond(1.14, 0.04, 0.026), (0, 0, 1.30))
# glowing rune strip down both faces
for side in (-1, 1):
    s.box("rune", (0, side * 0.024, 0.58), (0.022, 0.008, 0.78))
    for z in (0.25, 0.48, 0.71, 0.94):                                  # rune "glyph" ticks
        s.box("rune", (0, side * 0.025, z), (0.05, 0.006, 0.012))
# crossguard: centre block + swept wings rising to points
s.box("gold", (0, 0, 0.03), (0.16, 0.075, 0.08))
for sx in (-1, 1):
    rot = Matrix.Rotation(math.radians(-sx * 22), 3, 'Y')
    s.box("gold", (sx * 0.17, 0, 0.065), (0.22, 0.06, 0.055), rot)
    s.cone_tip("gold", [Vector((sx * 0.27, y, z)) for y, z in ((-0.03, 0.08), (0.03, 0.08), (0.03, 0.13), (-0.03, 0.13))],
               (sx * 0.36, 0, 0.19))
s.octa("gem", (0, -0.045, 0.035), 0.035)                                 # guard gems, both faces
s.octa("gem", (0, 0.045, 0.035), 0.035)
# grip (leather wrap with gold rings) + pommel
s.rings("leather", [octagon(z, r) for z, r in ((-0.27, 0.042), (-0.14, 0.047), (-0.01, 0.042))])
for z in (-0.2, -0.08):
    s.rings("gold", [octagon(z - 0.012, 0.05), octagon(z + 0.012, 0.05)])
s.rings("gold", [octagon(-0.27, 0.05), octagon(-0.3, 0.07), octagon(-0.36, 0.06), octagon(-0.38, 0.03)])
s.octa("gem", (0, 0, -0.41), 0.04)
sword = s.build("Sword", {"steel": 0.3, "gold": 0.12, "leather": 0.1})

# ======================= GILDCREST SHIELD (heater, ~0.9 x 1.1 units) =========================
h = Builder()
OUT_PTS = [(-0.45, 0.48), (0.45, 0.48), (0.47, 0.18), (0.40, -0.12), (0.26, -0.38), (0.0, -0.6),
           (-0.26, -0.38), (-0.40, -0.12), (-0.47, 0.18)]
FRONT, BACK, BULGE = -0.06, 0.0, 0.07
bm = h.bm("paint")
fv = [bm.verts.new((x, FRONT, z)) for x, z in OUT_PTS]
bv = [bm.verts.new((x, BACK, z)) for x, z in OUT_PTS]
n = len(OUT_PTS)
centre = bm.verts.new((0, FRONT - BULGE, -0.02))          # poke: faceted bulge
for i in range(n):
    bm.faces.new((fv[i], fv[(i+1) % n], centre))
    bm.faces.new((fv[(i+1) % n], fv[i], bv[i], bv[(i+1) % n]))
back_c = bm.verts.new((0, BACK + 0.01, -0.02))
for i in range(n):
    bm.faces.new((bv[(i+1) % n], bv[i], back_c))
# gold rim: chunky beam along every edge
for i in range(n):
    a = Vector((OUT_PTS[i][0], 0, OUT_PTS[i][1])); b = Vector((OUT_PTS[(i+1) % n][0], 0, OUT_PTS[(i+1) % n][1]))
    mid = (a + b) / 2; d = b - a
    ang = math.atan2(d.z, d.x)
    h.box("gold", (mid.x, FRONT - 0.012, mid.z), (d.length + 0.06, 0.1, 0.07), Matrix.Rotation(-ang, 3, 'Y'))
# sunburst emblem: core gem + 8 tapered rays (gold), slightly proud of the bulge
EC = Vector((0, FRONT - BULGE - 0.03, 0.0))
h.octa("sun", (EC.x, EC.y - 0.02, EC.z), 0.08)
for k in range(8):
    a = k / 8 * math.tau
    L = 0.26 if k % 2 == 0 else 0.17
    dirv = Vector((math.cos(a), 0, math.sin(a)))
    base = EC + dirv * 0.07
    side = Vector((-dirv.z, 0, dirv.x)) * 0.035
    h.cone_tip("gold", [base + side + Vector((0, 0.012, 0)), base + side - Vector((0, 0.012, 0)),
                        base - side - Vector((0, 0.012, 0)), base - side + Vector((0, 0.012, 0))],
               tuple(EC + dirv * L + Vector((0, 0.01, 0))))
# back: wooden brace, leather arm strap + handle (origin = handle)
h.box("wood", (0, 0.02, -0.02), (0.08, 0.03, 0.8))
h.box("wood", (0, 0.02, 0.05), (0.75, 0.03, 0.08))
h.box("leather", (0, 0.06, 0.0), (0.26, 0.03, 0.05))
h.box("leather", (0, 0.06, 0.2), (0.3, 0.03, 0.06))
shield = h.build("Shield", {"paint": 0.25, "gold": 0.1, "wood": 0.2, "leather": 0.1})
for v in shield.data.vertices:          # origin at the handle (back centre)
    v.co.y -= 0.06


def export(ob, name):
    for o in bpy.context.scene.objects: o.select_set(False)
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dims = [round(d, 3) for d in ob.dimensions]
    print("EXPORT", name, "tris", tris, "dims", dims)


export(sword, "sword_dawnsteel")
export(shield, "shield_gildcrest")
sword.location = (-0.5, 0, 0.4); shield.location = (0.5, 0, 0.6)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "weapons_sword_set.blend"))
