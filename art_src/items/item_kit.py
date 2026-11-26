# Shared helpers for the item model scripts (Megabonk-style: chunky low poly, 32px
# nearest-filtered noise textures, a few emissive accents). Imported by make_items_*.py.
# Axes: Blender Z up = Godot Y up, Blender -Y = Godot +Z (glTF export_yup).
import bpy, bmesh, random, math, os
from mathutils import Vector, Matrix

TEX_OUT = None          # set by init()
MATS = {}
_PALETTES = {}


def init(tex_out):
    global TEX_OUT
    TEX_OUT = tex_out
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def srgb(c): return tuple(v / 255.0 for v in c)


def _img(name, painter, size=32):
    img = bpy.data.images.new(name, size, size, alpha=False)
    px = []
    for y in range(size):
        for x in range(size):
            px += [*painter(x, y), 1.0]
    img.pixels = px
    img.filepath_raw = os.path.join(TEX_OUT, name + ".png"); img.file_format = 'PNG'; img.save()
    return img


def tex_mat(key, palette, weights=(.5, .28, .17, .05), seed=1, metal=False, rough=None, stripes=None):
    """Material with a 32px noise texture from a 4-colour palette (last colour = stripe colour)."""
    if key in MATS:
        return key
    r = random.Random(seed)
    def p(x, y):
        if stripes and stripes(x, y, r):
            return srgb(palette[-1])
        v, acc = r.random(), 0.0
        for c, w in zip(palette, weights):
            acc += w
            if v < acc: return srgb(c)
        return srgb(palette[0])
    img = _img("tex_i_" + key, p)
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough if rough is not None else (0.4 if metal else 0.85)
    b.inputs["Metallic"].default_value = 0.65 if metal else 0.0
    t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = img; t.interpolation = 'Closest'
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    MATS[key] = m
    return key


def glow_mat(key, color, strength=2.5):
    if key in MATS:
        return key
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(color), 1.0)
    b.inputs["Emission Color"].default_value = (*srgb(color), 1.0)
    b.inputs["Emission Strength"].default_value = strength
    b.inputs["Roughness"].default_value = 0.25
    MATS[key] = m
    return key


# ---- common palette (shared textures keep the item set consistent)
def std_mats():
    tex_mat("steel", [(188,198,210),(160,170,184),(222,230,240),(120,128,140)], (.45,.3,.2,.05), 101, True,
            stripes=lambda x, y, r: x % 16 == 0 and r.random() < .5)
    tex_mat("darkiron", [(70,72,82),(54,56,64),(94,96,108),(34,34,40)], seed=102, metal=True)
    tex_mat("brass", [(214,164,66),(190,140,48),(240,204,112),(140,98,30)], (.5,.25,.2,.05), 103, True)
    tex_mat("copper", [(196,112,64),(170,92,50),(226,146,92),(120,62,34)], seed=104, metal=True)
    tex_mat("leather", [(92,52,38),(76,42,30),(118,70,50),(52,28,20)], (.5,.3,.15,.05), 105,
            stripes=lambda x, y, r: (x + y) % 6 == 0)
    tex_mat("wood", [(124,82,48),(104,66,38),(146,100,60),(72,46,26)], (.5,.3,.15,.05), 106,
            stripes=lambda x, y, r: y % 5 == 0 and r.random() < .6)
    tex_mat("darkwood", [(84,54,34),(68,42,26),(104,70,44),(46,28,18)], seed=107)
    tex_mat("rope", [(196,170,116),(170,144,94),(218,196,140),(128,104,64)], seed=108,
            stripes=lambda x, y, r: (x + y * 2) % 5 == 0)
    tex_mat("stone", [(132,128,122),(112,108,104),(156,152,146),(84,80,78)], seed=109)
    tex_mat("cloth_red", [(176,48,40),(150,38,32),(204,72,58),(110,26,22)], seed=110)
    tex_mat("leafgreen", [(86,156,62),(70,134,50),(112,182,80),(48,100,36)], seed=111,
            stripes=lambda x, y, r: x == 16)
    tex_mat("sand", [(222,190,128),(200,166,104),(240,214,158),(170,136,80)], seed=112)
    tex_mat("ice", [(170,222,248),(140,200,236),(206,240,255),(110,170,214)], seed=113, rough=0.15)


def cube_uv(bm, texel):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal; ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            c = l.vert.co
            u, v = [(c.y, c.z), (c.x, c.z), (c.x, c.y)][ax]
            l[uv].uv = (u / texel, v / texel)


def ring_z(z, r, n=8, x=0.0, y=0.0, rot=0.5, sx=1.0, sy=1.0):
    """Polygon ring around the Z axis."""
    return [Vector((x + math.cos((i + rot) / n * math.tau) * r * sx,
                    y + math.sin((i + rot) / n * math.tau) * r * sy, z)) for i in range(n)]


def ring_y(y, r, n=8, x=0.0, z=0.0, rot=0.5):
    return [Vector((x + math.cos((i + rot) / n * math.tau) * r, y,
                    z + math.sin((i + rot) / n * math.tau) * r)) for i in range(n)]


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

    def lathe(self, mat, profile, n=8, x=0.0, y=0.0, rot=0.5, sx=1.0, sy=1.0, xform=None):
        """Solid of revolution around Z: profile = [(z, radius), ...] bottom to top.
        A radius of 0 at either end makes a point instead of a cap."""
        bm = self.bm(mat)
        def P(v): return (xform @ v) if xform else v
        rings, pts = [], []
        for z, r in profile:
            if r <= 1e-5:
                pts.append(bm.verts.new(P(Vector((x, y, z)))))
                rings.append(None)
            else:
                rings.append([bm.verts.new(P(p)) for p in ring_z(z, r, n, x, y, rot, sx, sy)])
                pts.append(None)
        for i in range(len(profile) - 1):
            a, b = rings[i], rings[i + 1]
            if a and b:
                for s in range(n):
                    bm.faces.new((a[s], a[(s+1) % n], b[(s+1) % n], b[s]))
            elif a and not b:
                for s in range(n):
                    bm.faces.new((a[s], a[(s+1) % n], pts[i + 1]))
            elif b and not a:
                for s in range(n):
                    bm.faces.new((pts[i], b[(s+1) % n], b[s]))
        if rings[0]: bm.faces.new(list(reversed(rings[0])))
        if rings[-1]: bm.faces.new(rings[-1])

    def cone_tip(self, mat, ring, tip):
        bm = self.bm(mat)
        vs = [bm.verts.new(p) for p in ring]
        t = bm.verts.new(tip)
        for i in range(len(vs)):
            bm.faces.new((vs[i], vs[(i+1) % len(vs)], t))

    def octa(self, mat, c, r, sz=None):
        bm = self.bm(mat)
        c = Vector(c); rz = sz if sz is not None else r
        pts = [bm.verts.new(c + Vector(d)) for d in ((r,0,0),(0,r,0),(-r,0,0),(0,-r,0))]
        top = bm.verts.new(c + Vector((0, 0, rz))); bot = bm.verts.new(c + Vector((0, 0, -rz)))
        for i in range(4):
            bm.faces.new((pts[i], pts[(i+1) % 4], top))
            bm.faces.new((pts[(i+1) % 4], pts[i], bot))

    def blob(self, mat, c, r, scale=(1, 1, 1), subdiv=1, jitter=0.12, seed=0, rot=None):
        """Faceted rock / fruit: icosphere, squashed and jittered."""
        bm = self.bm(mat)
        rnd = random.Random(seed)
        res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
        for v in res["verts"]:
            k = 1.0 + rnd.uniform(-jitter, jitter)
            v.co = Vector((v.co.x * scale[0] * k, v.co.y * scale[1] * k, v.co.z * scale[2] * k))
            if rot: v.co = rot @ v.co
            v.co += Vector(c)

    def leaf(self, mat, base, direction, length, width, thick=0.012, side=None):
        """Flat diamond leaf/petal from `base` along `direction`."""
        bm = self.bm(mat)
        d = Vector(direction).normalized()
        s = Vector(side).normalized() if side else d.cross(Vector((0, 0, 1)))
        if s.length < 0.01: s = Vector((1, 0, 0))
        s.normalize()
        nrm = d.cross(s).normalized()
        b = Vector(base)
        mid = b + d * length * 0.45
        P = [b, mid + s * width * 0.5, b + d * length, mid - s * width * 0.5]
        up = bm.verts.new(mid + nrm * thick); dn = bm.verts.new(mid - nrm * thick)
        q = [bm.verts.new(p) for p in P]
        for i in range(4):
            bm.faces.new((q[i], q[(i+1) % 4], up))
            bm.faces.new((q[(i+1) % 4], q[i], dn))

    def build(self, name, texels=None, default_texel=0.12):
        texels = texels or {}
        me = bpy.data.meshes.new(name)
        merged = bmesh.new()
        order = list(self.parts.keys())
        for i, mat in enumerate(order):
            bm = self.parts[mat]
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.normal_update(); cube_uv(bm, texels.get(mat, default_texel))
            tmp = bpy.data.meshes.new("tmp"); bm.to_mesh(tmp); bm.free()
            for p in tmp.polygons: p.material_index = i
            merged.from_mesh(tmp); bpy.data.meshes.remove(tmp)
        merged.to_mesh(me); merged.free()
        for mat in order: me.materials.append(MATS[mat])
        for p in me.polygons: p.use_smooth = False
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def export(obs, path):
    for o in bpy.context.scene.objects: o.select_set(False)
    for o in obs: o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in obs)
    dims = [round(max(o.dimensions[i] for o in obs), 3) for i in range(3)]
    print("EXPORT", os.path.basename(path), "tris", tris, "dims", dims)
    return tris


def preview(groups, path, cols=5):
    """Contact sheet: each item scaled to fit a 1m cell, 3/4 view, Workbench textured."""
    sc = bpy.context.scene
    for i, obs in enumerate(groups):
        size = max(max(o.dimensions) for o in obs) or 1.0
        k = 0.8 / size
        cx, cy = (i % cols) * 1.1, -(i // cols) * 1.1
        for o in obs:
            o.scale = (k, k, k)
            o.location = (cx + o.location.x * k, 0.0, cy + o.location.z * k)
        # centre the group on its cell
        bpy.context.view_layer.update()
        lo = [min((o.matrix_world @ Vector(c))[a] for o in obs for c in o.bound_box) for a in range(3)]
        hi = [max((o.matrix_world @ Vector(c))[a] for o in obs for c in o.bound_box) for a in range(3)]
        for o in obs:
            o.location.x += cx - (lo[0] + hi[0]) / 2
            o.location.y += -(lo[1] + hi[1]) / 2
            o.location.z += cy - (lo[2] + hi[2]) / 2
    rows = (len(groups) + cols - 1) // cols
    w = bpy.data.worlds.new("w"); sc.world = w; w.color = (0.55, 0.62, 0.72)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = max(cols, rows * 1.6) * 1.12
    mid = Vector(((cols - 1) * 0.55, 0, -(rows - 1) * 0.55))
    d = Vector((0.55, -1.0, 0.35)).normalized()
    cam.location = mid + d * 20
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    sc.render.resolution_x = 220 * cols; sc.render.resolution_y = int(220 * rows * 1.0)
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "TEXTURE"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", path)
