import bpy, bmesh, random, math, os, sys
from mathutils import Vector, Matrix

OUT = sys.argv[-1]               # output folder
SEED = 7
random.seed(SEED)
bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------- pixel textures (32x32, nearest filtering) ----------
def make_img(name, size, painter):
    img = bpy.data.images.new(name, size, size, alpha=False)
    px = []
    for y in range(size):
        for x in range(size):
            r, g, b = painter(x, y)
            px += [r, g, b, 1.0]
    img.pixels = px
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = 'PNG'
    img.save()
    return img

def srgb(c):  # palette in 0-255 sRGB -> blender byte image takes sRGB floats
    return tuple(v / 255.0 for v in c)

LEAF = [srgb(c) for c in [(58, 128, 44), (76, 158, 52), (104, 190, 66), (40, 98, 38), (140, 214, 84)]]
BARK = [srgb(c) for c in [(110, 72, 42), (92, 58, 34), (132, 90, 54), (64, 40, 24)]]

rl = random.Random(1)
leaf_map = {}
for y in range(32):
    for x in range(32):
        v = rl.random()
        leaf_map[(x, y)] = 0 if v < 0.45 else 1 if v < 0.75 else 3 if v < 0.9 else 2
# little bright "leaf" clusters
for _ in range(14):
    cx, cy = rl.randrange(32), rl.randrange(32)
    for dx, dy in [(0, 0), (1, 0), (0, 1), (1, 1), (-1, 0)]:
        leaf_map[((cx + dx) % 32, (cy + dy) % 32)] = 2 if rl.random() < 0.7 else 4
leaf_img = make_img("tex_leaves_a", 32, lambda x, y: LEAF[leaf_map[(x, y)]])

rb = random.Random(2)
cols = [rb.choice([0, 0, 1, 2]) for _ in range(32)]
groove = {x for x in range(0, 32, 5)}
def bark(x, y):
    if x in groove and rb.random() < 0.85:
        return BARK[3]
    c = cols[x]
    if rb.random() < 0.12:
        c = 1
    return BARK[c]
bark_img = make_img("tex_bark_a", 32, bark)

def material(name, img):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = 'Closest'          # -> glTF sampler NEAREST (pixel look)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m

mat_bark = material("bark", bark_img)
mat_leaf = material("leaves", leaf_img)

# ---------- geometry helpers ----------
def jitter(bm, amt, rng):
    for v in bm.verts:
        v.co += Vector((rng.uniform(-amt, amt), rng.uniform(-amt, amt), rng.uniform(-amt, amt)))

def cube_uv(bm, texel_size):
    """Box-project UVs so 1 texture tile = texel_size metres (consistent pixel density)."""
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            co = l.vert.co
            u, v = [(co.y, co.z), (co.x, co.z), (co.x, co.y)][ax]
            l[uv].uv = (u / texel_size, v / texel_size)

def obj_from_bm(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob

rng = random.Random(SEED)

# ---------- trunk: 6 sides, tapered, slight lean, 4 segments ----------
bm = bmesh.new()
SIDES, H = 6, 3.2
rings = []
for i in range(5):
    t = i / 4
    z = t * H
    r = 0.42 * (1 - t) + 0.22 * t
    lean = Vector((0.18 * t * t, 0.06 * t, 0))
    ring = []
    for s in range(SIDES):
        a = s / SIDES * math.tau + (0.2 if i % 2 else 0)
        rr = r * rng.uniform(0.92, 1.08)
        ring.append(bm.verts.new((math.cos(a) * rr + lean.x, math.sin(a) * rr + lean.y, z)))
    rings.append(ring)
for i in range(4):
    for s in range(SIDES):
        a, b = rings[i][s], rings[i][(s + 1) % SIDES]
        c, d = rings[i + 1][(s + 1) % SIDES], rings[i + 1][s]
        bm.faces.new((a, b, c, d))
bm.faces.new(list(reversed(rings[0])))
bm.faces.new(rings[-1])
# root flares: pull every other bottom vert outward
for s in range(0, SIDES, 2):
    v = rings[0][s]
    d = Vector((v.co.x, v.co.y, 0)).normalized()
    v.co += d * 0.28
    v.co.z = -0.05
# branch stub
bm.normal_update()
side = [f for f in bm.faces if len(f.verts) == 4 and 1.6 < f.calc_center_median().z < 2.5]
f = max(side, key=lambda f: f.calc_center_median().x)
ret = bmesh.ops.extrude_face_region(bm, geom=[f])
newv = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
n = f.normal.copy()
c = sum((v.co for v in newv), Vector()) / len(newv)
for v in newv:
    v.co = c + (v.co - c) * 0.55 + n * 0.75 + Vector((0, 0, 0.55))
bm.normal_update()
cube_uv(bm, 1.0)
trunk = obj_from_bm("Trunk", bm, mat_bark)

# ---------- canopy: faceted blobs ----------
blobs = [  # center, radius
    (Vector((0.35, 0.05, 3.7)), 1.55),
    (Vector((-0.55, 0.45, 3.35)), 1.05),
    (Vector((0.95, -0.55, 3.25)), 1.0),
    (Vector((0.15, 0.1, 4.75)), 0.95),
    (Vector((1.25, 0.4, 2.75)), 0.6),   # over the branch
]
bm = bmesh.new()
for center, rad in blobs:
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=rad)
    jitter(tmp, rad * 0.12, rng)
    for v in tmp.verts:
        v.co.z *= 0.82  # slightly squashed, chunkier
        v.co += center
    tmp.normal_update()
    me = bpy.data.meshes.new("t")
    tmp.to_mesh(me); tmp.free()
    bm.from_mesh(me); bpy.data.meshes.remove(me)
bm.normal_update()
cube_uv(bm, 1.6)
canopy = obj_from_bm("Canopy", bm, mat_leaf)

# ---------- join, origin at base, export ----------
root = bpy.data.objects.new("TreeOakA", None)
bpy.context.scene.collection.objects.link(root)
trunk.parent = root
canopy.parent = root

tris = sum(len(p.vertices) - 2 for o in (trunk, canopy) for p in o.data.polygons)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "tree_oak_a.blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "tree_oak_a.glb"), export_format='GLB',
                          export_apply=True, export_yup=True, export_image_format='AUTO')
print("TRIS", tris)
