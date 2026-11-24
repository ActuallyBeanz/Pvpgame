# Generates the two grapple launchers + their flying claw tips (Megabonk-style: chunky low
# poly + 32px nearest-filtered noise textures, a few emissive accents). Original designs.
#   Grappleclaw: short, stocky brass launcher, teal paint, 3-prong claw.
#   Skytether:   long telescoping steel launcher, violet paint, glowing spool, 4-prong claw.
# Axes: Blender +Y = barrel forward (Godot -Z), +Z = up (Godot +Y). Origin = grip centre.
# Each launcher exports two meshes: "Body" and "ClawHead" (the head is hidden in game while
# it is flying). The tip glbs are the claw alone, origin at its base, pointing +Y.
# Run (Blender):  blender -b -P make_grapples.py -- <tex_out_dir> <glb_out_dir>
import bpy, bmesh, random, math, os, sys
from mathutils import Vector, Matrix

TEX_OUT, GLB_OUT = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb(c): return tuple(v / 255.0 for v in c)


def make_img(name, painter, size=32):
    img = bpy.data.images.new(name, size, size, alpha=False)
    px = []
    for y in range(size):
        for x in range(size):
            px += [*painter(x, y), 1.0]
    img.pixels = px
    img.filepath_raw = os.path.join(TEX_OUT, name + ".png"); img.file_format = 'PNG'; img.save()
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
 "brass":  noise_tex("tex_g_brass", [(214,164,66),(190,140,48),(240,204,112),(140,98,30)], [.5,.25,.2,.05], 41),
 "steel":  noise_tex("tex_g_steel", [(188,198,210),(160,170,184),(222,230,240),(120,128,140)], [.45,.3,.2,.05], 42,
                     lambda x, y, r: x % 16 == 0 and r.random() < .5),
 "dark":   noise_tex("tex_g_dark", [(62,64,72),(48,50,58),(84,86,96),(30,30,36)], [.5,.3,.15,.05], 43),
 "grip":   noise_tex("tex_g_grip", [(92,52,38),(76,42,30),(118,70,50),(52,28,20)], [.5,.3,.15,.05], 44,
                     lambda x, y, r: (x + y) % 6 == 0),
 "wood":   noise_tex("tex_g_wood", [(124,82,48),(104,66,38),(146,100,60),(72,46,26)], [.5,.3,.15,.05], 45,
                     lambda x, y, r: y % 5 == 0 and r.random() < .6),
 "teal":   noise_tex("tex_g_teal", [(34,120,132),(28,100,114),(48,142,154),(18,74,86)], [.5,.28,.17,.05], 46),
 "violet": noise_tex("tex_g_violet", [(96,58,150),(80,46,128),(120,78,176),(56,30,92)], [.5,.28,.17,.05], 47),
}
MATS = {}
for k, img in T.items():
    m = bpy.data.materials.new(k)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    metal = k in ("brass", "steel", "dark")
    b.inputs["Roughness"].default_value = 0.4 if metal else 0.85
    b.inputs["Metallic"].default_value = 0.65 if metal else 0.0
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


glow_mat("glow_teal", (80, 240, 220), 2.5)
glow_mat("glow_cyan", (110, 210, 255), 3.0)


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
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
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
    def cone_tip(self, mat, ring, tip):
        bm = self.bm(mat)
        vs = [bm.verts.new(p) for p in ring]
        t = bm.verts.new(tip)
        for i in range(len(vs)):
            bm.faces.new((vs[i], vs[(i+1) % len(vs)], t))
    def octa(self, mat, c, r):
        bm = self.bm(mat)
        c = Vector(c)
        pts = [bm.verts.new(c + Vector(d)) for d in ((r,0,0),(0,r,0),(-r,0,0),(0,-r,0))]
        top = bm.verts.new(c + Vector((0, 0, r))); bot = bm.verts.new(c + Vector((0, 0, -r)))
        for i in range(4):
            bm.faces.new((pts[i], pts[(i+1) % 4], top))
            bm.faces.new((pts[(i+1) % 4], pts[i], bot))
    def build(self, name, texels):
        me = bpy.data.meshes.new(name)
        merged = bmesh.new()
        for i, (mat, bm) in enumerate(self.parts.items()):
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.normal_update(); cube_uv(bm, texels.get(mat, 0.15))
            tmp = bpy.data.meshes.new("tmp"); bm.to_mesh(tmp); bm.free()
            for p in tmp.polygons: p.material_index = i
            merged.from_mesh(tmp); bpy.data.meshes.remove(tmp)
        merged.to_mesh(me); merged.free()
        for mat in self.parts: me.materials.append(MATS[mat])
        for p in me.polygons: p.use_smooth = False
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def ring_y(y, r, n=8, x=0.0, z=0.0, rot=0.5):
    """Polygon ring around the Y (barrel) axis."""
    return [Vector((x + math.cos((i + rot) / n * math.tau) * r, y, z + math.sin((i + rot) / n * math.tau) * r))
            for i in range(n)]


def ring_x(x, r, cy, cz, n=8):
    """Polygon ring around the X axis (spools)."""
    return [Vector((x, cy + math.cos((i + .5) / n * math.tau) * r, cz + math.sin((i + .5) / n * math.tau) * r))
            for i in range(n)]


def claw(b, base_y, prongs, metal, accent, size=1.0, z=0.0):
    """Claw head pointing +Y: collar, central spike, hooked prongs."""
    s = size
    b.rings(accent, [ring_y(base_y, 0.05 * s, z=z), ring_y(base_y + 0.05 * s, 0.058 * s, z=z),
                     ring_y(base_y + 0.08 * s, 0.045 * s, z=z)])
    b.cone_tip(metal, ring_y(base_y + 0.08 * s, 0.034 * s, 6, z=z), (0, base_y + 0.2 * s, z))
    for k in range(prongs):
        a = k / prongs * math.tau + math.pi / 2
        out = Vector((math.cos(a), 0, math.sin(a)))
        side = Vector((-math.sin(a), 0, math.cos(a)))
        rot_out = Matrix.Rotation(-math.radians(28), 3, side)       # splay outwards
        mid = Vector((0, base_y + 0.095 * s, z)) + out * 0.055 * s
        b.box(metal, mid, (0.026 * s, 0.1 * s, 0.026 * s), rot_out)
        tip_base = Vector((0, base_y + 0.14 * s, z)) + out * 0.08 * s
        sq = [tip_base + side * 0.016 * s,
              tip_base + out * 0.016 * s, tip_base - side * 0.016 * s, tip_base - out * 0.016 * s]
        b.cone_tip(metal, sq, tuple(Vector((0, base_y + 0.2 * s, z)) + out * 0.035 * s))   # hooks back inward


def launcher(spec):
    b = Builder()
    L, paint, metal, trim, glow = spec["len"], spec["paint"], spec["metal"], spec["trim"], spec["glow"]
    # grip (raked back) + pommel cap
    rake = Matrix.Rotation(math.radians(-14), 3, 'X')
    b.box("grip", (0, -0.025, -0.09), (0.065, 0.085, 0.2), rake)
    b.box(trim, (0, -0.05, -0.195), (0.08, 0.1, 0.035), rake)
    # trigger guard + trigger
    b.box("dark", (0, 0.06, -0.06), (0.02, 0.1, 0.018))
    b.box("dark", (0, 0.11, -0.035), (0.02, 0.018, 0.05))
    b.box(metal, (0, 0.045, -0.03), (0.018, 0.02, 0.05))
    # housing: stepped block (paint) with metal plates
    b.box(paint, (0, 0.04, 0.05), (0.12, 0.3, 0.11))
    b.box(metal, (0, 0.0, 0.115), (0.09, 0.22, 0.025))                  # top plate
    for sx in (-1, 1):
        b.box(trim, (sx * 0.062, 0.04, 0.05), (0.012, 0.26, 0.03))      # side rails
        for y in (-0.06, 0.04, 0.14):                                    # rivets
            b.octa(trim, (sx * 0.07, y, 0.085), 0.012)
    # chain spool on the left side
    sp_x, sp_y, sp_z = -0.085, -0.02, 0.05
    b.rings(trim, [ring_x(sp_x + 0.01, 0.07, sp_y, sp_z), ring_x(sp_x - 0.01, 0.07, sp_y, sp_z)])
    b.rings("dark", [ring_x(sp_x - 0.01, 0.05, sp_y, sp_z), ring_x(sp_x - 0.05, 0.05, sp_y, sp_z)])
    b.rings(trim, [ring_x(sp_x - 0.05, 0.072, sp_y, sp_z), ring_x(sp_x - 0.068, 0.072, sp_y, sp_z)])
    b.octa(glow, (sp_x - 0.075, sp_y, sp_z), 0.022)
    # barrel: telescoping segments with collars
    y = 0.19
    for i, (seg, r) in enumerate(spec["segments"]):
        b.rings(metal, [ring_y(y, r, z=0.05), ring_y(y + seg, r * 0.96, z=0.05)])
        b.rings(trim, [ring_y(y - 0.005, r * 1.22, z=0.05), ring_y(y + 0.03, r * 1.22, z=0.05)])
        y += seg
    b.rings(trim, [ring_y(y - 0.03, spec["segments"][-1][1] * 1.35, z=0.05),
                   ring_y(y, spec["segments"][-1][1] * 1.35, z=0.05)])   # muzzle
    # sight + glow strip on top
    b.box(trim, (0, 0.12, 0.14), (0.02, 0.05, 0.03))
    b.box(glow, (0, 0.02, 0.129), (0.03, 0.15, 0.006))
    if spec.get("fin"):
        for sx in (-1, 1):                                               # Skytether: swept fins
            b.box(paint, (sx * 0.07, 0.24, 0.05), (0.012, 0.16, 0.05),
                  Matrix.Rotation(math.radians(sx * 10), 3, 'Z'))
    body = b.build("Body", {"grip": 0.1, "dark": 0.1, paint: 0.12, metal: 0.12, trim: 0.08})
    h = Builder()
    claw(h, y, spec["prongs"], metal, trim, spec["claw"], z=0.05)
    head = h.build("ClawHead", {metal: 0.08, trim: 0.06})
    tip = Builder()
    claw(tip, 0.0, spec["prongs"], metal, trim, spec["claw"])
    tip.rings("dark", [ring_y(-0.06, 0.022, 6), ring_y(0.0, 0.022, 6)])  # chain socket
    tip_ob = tip.build("Tip", {metal: 0.08, trim: 0.06})
    return body, head, tip_ob, y


SPECS = {
 "grappleclaw": dict(len=0.7, paint="teal", metal="steel", trim="brass", glow="glow_teal",
                     segments=[(0.2, 0.042)], prongs=3, claw=1.0),
 "skytether":   dict(len=1.0, paint="violet", metal="steel", trim="brass", glow="glow_cyan",
                     segments=[(0.18, 0.05), (0.17, 0.042), (0.16, 0.035)], prongs=4, claw=1.15, fin=True),
}


def export(obs, name):
    for o in bpy.context.scene.objects: o.select_set(False)
    for o in obs: o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.export_scene.gltf(filepath=os.path.join(GLB_OUT, name + ".glb"), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in obs)
    print("EXPORT", name, "tris", tris)


report = {}
x = 0.0
for name, spec in SPECS.items():
    body, head, tip, muzzle = launcher(spec)
    body.name, head.name, tip.name = "Body", "ClawHead", "Tip"
    export([body, head], "%s" % name)
    export([tip], "%s_tip" % name)
    report[name] = {"muzzle_y": round(muzzle, 3), "dims": [round(d, 3) for d in body.dimensions]}
    for o in (body, head, tip):
        o.name = name + "_" + o.name
        o.location.x += x
    tip.location.z += 0.4
    x += 0.6
print("REPORT", report)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TEX_OUT, "weapons_grapple_set.blend"))
