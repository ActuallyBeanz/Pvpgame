# Nature set for the island (Megabonk-style low poly + 32px pixel textures). Original designs.
#   trees    : origin at the trunk base, +Z up, real metres (4-9 m)
#   rocks    : origin at the base centre (sink them a little when placing)
#   ground   : grass / flowers / ferns / bushes / mushrooms - no collision, scattered with MultiMesh
#   stones   : flat flagstones / stepping stones for paths
# Run: blender -b --factory-startup -P make_nature.py -- <tex_dir> <glb_dir> [name ...]
import bpy, math, os, sys, random
from mathutils import Vector, Matrix
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "items"))
import importlib, item_kit as K
importlib.reload(K)
from item_kit import Builder, ring_z

ARGS = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT, ONLY = ARGS[0], ARGS[1], set(ARGS[2:])
K.init(TEX)
K.std_mats()
D = math.radians
RY = lambda a: Matrix.Rotation(D(a), 3, 'Y')
RZ = lambda a: Matrix.Rotation(D(a), 3, 'Z')
T = lambda v: Matrix.Translation(v)
M = K.tex_mat

M("bark", [(110,72,42),(92,58,34),(132,90,54),(64,40,24)], seed=401, stripes=lambda x, y, r: x % 5 == 0 and r.random() < .7)
M("bark_dark", [(74,52,38),(60,42,30),(92,66,46),(40,28,20)], seed=402, stripes=lambda x, y, r: x % 4 == 0)
M("birch", [(228,224,212),(210,206,194),(242,240,232),(46,42,40)], seed=403, stripes=lambda x, y, r: y % 7 == 0 and r.random() < .6)
M("char", [(46,40,40),(36,32,32),(62,54,52),(120,56,30)], seed=404, stripes=lambda x, y, r: r.random() < .04)
M("leaf_oak", [(70,148,52),(58,128,44),(96,176,66),(40,98,38)], seed=405, stripes=lambda x, y, r: r.random() < .05)
M("leaf_deep", [(46,112,48),(38,96,40),(64,136,60),(28,74,32)], seed=406)
M("leaf_birch", [(132,190,74),(114,170,60),(160,210,96),(90,140,46)], seed=407)
M("leaf_autumn", [(214,132,46),(192,108,36),(236,168,72),(160,74,30)], seed=408)
M("pine", [(44,96,64),(36,82,54),(58,116,78),(26,62,42)], seed=409, stripes=lambda x, y, r: (x + y) % 6 == 0)
M("snowcap", [(236,242,250),(222,230,242),(250,252,255),(196,208,226)], seed=410)
M("palmleaf", [(96,164,58),(80,144,46),(124,190,76),(58,110,36)], seed=411, stripes=lambda x, y, r: x % 4 == 0)
M("palmtrunk", [(150,116,76),(130,98,62),(176,140,96),(96,70,44)], seed=412, stripes=lambda x, y, r: y % 4 == 0)
M("cactus", [(84,140,74),(70,122,62),(104,164,92),(50,96,46)], seed=413, stripes=lambda x, y, r: x % 6 == 0)
M("moss", [(92,140,58),(78,122,48),(112,162,72),(60,96,38)], seed=414)
M("sandrock", [(206,160,104),(186,140,88),(226,184,128),(150,108,66)], seed=415, stripes=lambda x, y, r: y % 6 == 0 and r.random() < .5)
M("basalt", [(64,58,60),(52,46,48),(82,76,78),(36,32,34)], seed=416)
M("grass_a", [(92,170,64),(78,152,54),(118,196,82),(60,124,44)], seed=417)
M("grass_dry", [(178,170,92),(160,150,78),(200,192,116),(130,120,60)], seed=418)
M("grass_snow", [(170,190,170),(150,172,152),(196,212,196),(128,150,130)], seed=419)
M("flagstone", [(150,146,138),(130,126,120),(170,166,158),(104,100,96)], seed=420, stripes=lambda x, y, r: r.random() < .05)
M("petal_r", [(220,70,80),(200,56,66),(240,110,110),(160,40,50)], seed=421)
M("petal_y", [(246,208,70),(232,190,52),(255,226,110),(200,160,40)], seed=422)
M("petal_b", [(110,140,230),(90,120,210),(140,170,245),(70,96,180)], seed=423)
M("petal_w", [(244,242,236),(228,226,218),(255,255,250),(200,198,190)], seed=424)
M("shroom", [(196,72,56),(176,58,46),(222,104,80),(244,236,220)], seed=425, stripes=lambda x, y, r: r.random() < .1)
M("berry", [(150,40,80),(130,30,66),(180,60,100),(100,20,50)], seed=426)


def tube(b, mat, pts, radii, n=6):
    for i in range(len(pts) - 1):
        a, c = Vector(pts[i]), Vector(pts[i + 1])
        d = c - a
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        b.lathe(mat, [(0, radii[i]), (d.length, radii[i + 1])], n, xform=T(a) @ rot)


def canopy(b, mat, centers, seed):
    r = random.Random(seed)
    for i, (c, rad) in enumerate(centers):
        b.blob(mat, c, rad, (1, 1, 0.82), 1, 0.16, seed * 10 + i,
               rot=RZ(r.uniform(0, 360)))


# ------------------------------------------------------------------ trees
def oak_b():
    b = Builder()
    tube(b, "bark", [(0, 0, 0), (0.1, 0, 1.6), (0.05, 0.1, 3.0)], [0.36, 0.28, 0.2], 7)
    tube(b, "bark", [(0.08, 0.05, 2.0), (0.9, 0.3, 3.0)], [0.14, 0.07], 5)
    tube(b, "bark", [(0.05, 0.0, 2.3), (-0.8, -0.4, 3.2)], [0.13, 0.06], 5)
    b.lathe("bark", [(0, 0.5), (0.25, 0.36)], 7)                                       # root flare
    canopy(b, "leaf_oak", [((0, 0, 4.0), 1.9), ((1.2, 0.5, 3.6), 1.3), ((-1.2, -0.4, 3.7), 1.4),
                           ((0.3, -1.1, 3.5), 1.2), ((-0.2, 0.8, 4.8), 1.2)], 1)
    return [b.build("Body", {"bark": 0.25, "leaf_oak": 0.5})]


def oak_c():   # wide umbrella oak, forked trunk
    b = Builder()
    tube(b, "bark_dark", [(0, 0, 0), (0, 0, 1.8)], [0.42, 0.34], 7)
    for a in (20, 150, 260):
        d = Vector((math.cos(D(a)), math.sin(D(a)), 0))
        tube(b, "bark_dark", [(0, 0, 1.7), tuple(Vector((0, 0, 3.1)) + d * 1.3)], [0.24, 0.12], 6)
    canopy(b, "leaf_deep", [((0, 0, 3.6), 2.2), ((1.8, 0.6, 3.3), 1.6), ((-1.6, 1.0, 3.4), 1.5),
                            ((-0.6, -1.8, 3.3), 1.6), ((1.0, -1.4, 3.7), 1.3)], 2)
    b.lathe("bark_dark", [(0, 0.55), (0.25, 0.42)], 7)
    return [b.build("Body", {"bark_dark": 0.25, "leaf_deep": 0.55})]


def autumn():
    b = Builder()
    tube(b, "bark", [(0, 0, 0), (-0.1, 0, 1.4), (0.05, 0, 2.6)], [0.3, 0.24, 0.18], 6)
    canopy(b, "leaf_autumn", [((0, 0, 3.4), 1.6), ((0.9, 0.4, 3.0), 1.1), ((-0.9, -0.2, 3.1), 1.1), ((0, 0.2, 4.3), 1.0)], 3)
    return [b.build("Body", {"bark": 0.25, "leaf_autumn": 0.5})]


def birch():
    b = Builder()
    tube(b, "birch", [(0, 0, 0), (0.15, 0, 2.5), (0.05, 0.1, 5.2)], [0.18, 0.14, 0.09], 6)
    tube(b, "birch", [(0.1, 0, 3.4), (0.7, 0.2, 4.4)], [0.06, 0.03], 4)
    canopy(b, "leaf_birch", [((0.1, 0, 5.0), 1.1), ((0.6, 0.2, 4.3), 0.9), ((-0.4, -0.1, 4.2), 0.85), ((0.0, 0.1, 6.0), 0.8),
                             ((0.2, -0.3, 3.5), 0.7)], 4)
    return [b.build("Body", {"birch": 0.2, "leaf_birch": 0.4})]


def pine(snowy, tall):
    b = Builder()
    H = 7.5 if tall else 5.5
    tube(b, "bark_dark", [(0, 0, 0), (0, 0, H * 0.35)], [0.24, 0.2], 6)
    tiers = 4 if tall else 3
    z = H * 0.25
    for i in range(tiers):
        r = 1.9 * (1.0 - i / (tiers + 0.6))
        h = (H - H * 0.25) / tiers * 1.35
        b.lathe("pine", [(z, r * 0.35), (z + 0.15, r), (z + h, 0.0)], 8, rot=0.5 + i * 0.25)
        if snowy:
            b.lathe("snowcap", [(z + h * 0.4, r * 0.72), (z + h * 0.5, r * 0.6), (z + h + 0.08, 0.0)], 8, rot=0.5 + i * 0.25)
        z += h * 0.62
    return [b.build("Body", {"bark_dark": 0.2, "pine": 0.4})]


def palm():
    b = Builder()
    pts = [(0, 0, 0), (0.3, 0, 1.6), (0.8, 0, 3.0), (1.5, 0, 4.2), (2.2, 0, 5.0)]
    tube(b, "palmtrunk", pts, [0.26, 0.22, 0.19, 0.17, 0.15], 6)
    top = Vector(pts[-1])
    for i in range(7):
        a = i / 7 * math.tau
        d = Vector((math.cos(a), math.sin(a), 0.0))
        b.leaf("palmleaf", top, d + Vector((0, 0, 0.35)), 1.6, 0.55, 0.03)
        b.leaf("palmleaf", top + d * 1.4 + Vector((0, 0, 0.45)), d + Vector((0, 0, -0.9)), 1.2, 0.45, 0.03)
    for k in range(3):
        a = k / 3 * math.tau
        b.blob("bark_dark", top + Vector((math.cos(a) * 0.22, math.sin(a) * 0.22, -0.2)), 0.13, (1, 1, 1), 0, 0.05, 50 + k)
    return [b.build("Body", {"palmtrunk": 0.15, "palmleaf": 0.3})]


def dead_tree():
    b = Builder()
    tube(b, "char", [(0, 0, 0), (0.15, 0, 1.8), (-0.1, 0.1, 3.4), (0.1, 0, 4.6)], [0.3, 0.22, 0.14, 0.04], 6)
    r = random.Random(9)
    for i in range(6):
        z = 1.4 + i * 0.5
        a = r.uniform(0, math.tau)
        d = Vector((math.cos(a), math.sin(a), 0.6))
        base = Vector((0.0, 0.0, z))
        tube(b, "char", [tuple(base), tuple(base + d * 1.1), tuple(base + d * 1.6 + Vector((0, 0, 0.5)))], [0.09, 0.05, 0.01], 4)
    b.lathe("char", [(0, 0.45), (0.25, 0.3)], 6)
    return [b.build("Body", {"char": 0.2})]


def cactus():
    b = Builder()
    b.lathe("cactus", [(0, 0.24), (2.6, 0.24), (2.9, 0.16), (3.0, 0.0)], 8)
    for sx, z0, z1 in ((1, 0.9, 2.0), (-1, 1.4, 2.3)):
        tube(b, "cactus", [(0, 0, z0), (sx * 0.55, 0, z0 + 0.1), (sx * 0.6, 0, z1)], [0.15, 0.15, 0.14], 7)
        b.lathe("cactus", [(z1, 0.14), (z1 + 0.15, 0.0)], 7, x=sx * 0.6)
    return [b.build("Body", {"cactus": 0.2})]


# ------------------------------------------------------------------ rocks
def rock(mat, seed, parts, cap=None):
    b = Builder()
    for (c, r, sc) in parts:
        b.blob(mat, c, r, sc, 1, 0.22, seed + len(c) + int(r * 100))
    if cap:
        for (c, r, sc) in parts[:1]:
            b.blob(cap, (c[0], c[1], c[2] + r * sc[2] * 0.55), r * 0.85, (sc[0], sc[1], sc[2] * 0.35), 1, 0.12, seed + 7)
    return [b.build("Body", {mat: 0.25})]


ROCKS = {
    "rock_boulder_a": lambda: rock("stone", 1, [((0, 0, 0.55), 0.9, (1.2, 1.0, 0.75))]),
    "rock_boulder_b": lambda: rock("stone", 2, [((0, 0, 0.8), 1.1, (1.0, 0.9, 0.85)), ((0.9, 0.3, 0.35), 0.5, (1, 1, 0.8))]),
    "rock_slab": lambda: rock("stone", 3, [((0, 0, 0.25), 1.2, (1.4, 1.0, 0.25))]),
    "rock_spire": lambda: rock("stone", 4, [((0, 0, 1.3), 0.7, (0.9, 0.8, 2.0)), ((0.6, 0.2, 0.4), 0.45, (1, 1, 0.9))]),
    "rock_cluster": lambda: rock("stone", 5, [((0, 0, 0.35), 0.5, (1, 1, 0.8)), ((0.7, 0.3, 0.25), 0.35, (1, 1, 0.8)),
                                              ((-0.5, 0.5, 0.2), 0.3, (1, 1, 0.8)), ((0.2, -0.6, 0.2), 0.28, (1, 1, 0.9))]),
    "rock_mossy": lambda: rock("stone", 6, [((0, 0, 0.6), 1.0, (1.1, 1.0, 0.7))], cap="moss"),
    "rock_sand": lambda: rock("sandrock", 7, [((0, 0, 0.9), 1.0, (1.1, 0.9, 1.0)), ((0.8, -0.3, 0.4), 0.55, (1, 1, 0.8))]),
    "rock_basalt": lambda: rock("basalt", 8, [((0, 0, 0.9), 0.75, (0.8, 0.8, 1.4)), ((0.6, 0.4, 0.5), 0.5, (0.8, 0.8, 1.3))]),
    "rock_snow": lambda: rock("stone", 9, [((0, 0, 0.6), 1.0, (1.2, 1.0, 0.7))], cap="snowcap"),
}


# ------------------------------------------------------------------ ground cover (no collision)
def grass(mat, n, h, w, seed, spread=0.18):
    b = Builder()
    r = random.Random(seed)
    for i in range(n):
        a = r.uniform(0, math.tau)
        base = Vector((math.cos(a) * r.uniform(0, spread), math.sin(a) * r.uniform(0, spread), 0))
        d = Vector((math.cos(a) * r.uniform(0.15, 0.45), math.sin(a) * r.uniform(0.15, 0.45), 1.0))
        b.leaf(mat, base, d, h * r.uniform(0.7, 1.15), w, 0.004, side=(-math.sin(a), math.cos(a), 0))
    return b


def flowers(petal, seed, n=4):
    b = grass("grass_a", 8, 0.28, 0.05, seed)
    r = random.Random(seed)
    for i in range(n):
        a = r.uniform(0, math.tau)
        c = Vector((math.cos(a) * 0.15, math.sin(a) * 0.15, 0))
        top = c + Vector((0, 0, r.uniform(0.3, 0.45)))
        tube(b, "grass_a", [tuple(c), tuple(top)], [0.008, 0.006], 3)
        for k in range(5):
            pa = k / 5 * math.tau
            b.leaf(petal, top, (math.cos(pa), math.sin(pa), 0.3), 0.07, 0.04, 0.004)
        b.octa("petal_y", top + Vector((0, 0, 0.01)), 0.015)
    return b


def fern(seed):
    b = Builder()
    r = random.Random(seed)
    for i in range(7):
        a = i / 7 * math.tau + r.uniform(-.2, .2)
        d = Vector((math.cos(a), math.sin(a), 0.7))
        b.leaf("leaf_deep", (0, 0, 0.02), d, r.uniform(0.5, 0.7), 0.16, 0.006, side=(-math.sin(a), math.cos(a), 0))
    return b


def bush(mat, seed, berries=False):
    b = Builder()
    for i, (c, rad) in enumerate((((0, 0, 0.35), 0.45), ((0.35, 0.15, 0.28), 0.32), ((-0.3, 0.1, 0.3), 0.33))):
        b.blob(mat, c, rad, (1, 1, 0.85), 1, 0.18, seed + i)
    if berries:
        r = random.Random(seed)
        for k in range(8):
            a, e = r.uniform(0, math.tau), r.uniform(0.2, 1.2)
            b.octa("berry", (math.cos(a) * 0.42 * math.cos(e), math.sin(a) * 0.42 * math.cos(e), 0.35 + math.sin(e) * 0.35), 0.035)
    return b


def mushrooms(seed):
    b = Builder()
    for k, (x, y, s) in enumerate(((0, 0, 1.0), (0.12, 0.05, 0.6), (-0.08, 0.1, 0.5))):
        b.lathe("petal_w", [(0, 0.025 * s), (0.1 * s, 0.02 * s)], 6, x=x, y=y)
        b.lathe("shroom", [(0.09 * s, 0.07 * s), (0.12 * s, 0.065 * s), (0.15 * s, 0.0)], 7, x=x, y=y)
    return b


def dry_shrub(seed):
    b = Builder()
    r = random.Random(seed)
    for i in range(9):
        a = r.uniform(0, math.tau)
        d = Vector((math.cos(a), math.sin(a), r.uniform(0.6, 1.2)))
        tube(b, "bark", [(0, 0, 0), tuple(d * 0.25), tuple(d * 0.5 + Vector((0, 0, 0.1)))], [0.02, 0.012, 0.0], 3)
    b.blob("grass_dry", (0, 0, 0.12), 0.18, (1, 1, 0.6), 0, 0.2, seed)
    return b


GROUND = {
    "grass_tuft_a": lambda: grass("grass_a", 9, 0.35, 0.06, 1),
    "grass_tuft_b": lambda: grass("grass_a", 14, 0.5, 0.05, 2, 0.25),
    "grass_tall": lambda: grass("grass_a", 10, 0.9, 0.07, 3, 0.2),
    "grass_dry": lambda: grass("grass_dry", 10, 0.4, 0.05, 4),
    "grass_snow": lambda: grass("grass_snow", 7, 0.25, 0.05, 5),
    "flowers_red": lambda: flowers("petal_r", 6),
    "flowers_yellow": lambda: flowers("petal_y", 7),
    "flowers_blue": lambda: flowers("petal_b", 8),
    "flowers_white": lambda: flowers("petal_w", 9, 6),
    "fern": lambda: fern(10),
    "bush_round": lambda: bush("leaf_oak", 11),
    "bush_berry": lambda: bush("leaf_deep", 12, True),
    "mushrooms": lambda: mushrooms(13),
    "shrub_dry": lambda: dry_shrub(14),
}


# ------------------------------------------------------------------ path stones
def flagstone(seed, n=7, r0=0.45, thick=0.1):
    b = Builder()
    r = random.Random(seed)
    ring = []
    for i in range(n):
        a = i / n * math.tau
        rr = r0 * r.uniform(0.75, 1.1)
        ring.append((math.cos(a) * rr, math.sin(a) * rr))
    lo = [Vector((x, y, 0.0)) for x, y in ring]
    hi = [Vector((x * 0.92, y * 0.92, thick)) for x, y in ring]
    b.rings("flagstone", [lo, hi])
    return [b.build("Body", {"flagstone": 0.3})]


STONES = {
    "flagstone_a": lambda: flagstone(1, 7, 0.45),
    "flagstone_b": lambda: flagstone(2, 6, 0.6),
    "flagstone_c": lambda: flagstone(3, 8, 0.35),
    "stepstone_round": lambda: flagstone(4, 10, 0.5, 0.18),
}

ITEMS = {
    "tree_oak_b": oak_b, "tree_oak_c": oak_c, "tree_autumn": autumn, "tree_birch": birch,
    "tree_pine": lambda: pine(False, True), "tree_pine_small": lambda: pine(False, False),
    "tree_pine_snow": lambda: pine(True, True), "tree_pine_snow_small": lambda: pine(True, False),
    "tree_palm": palm, "tree_dead": dead_tree, "cactus": cactus,
}
ITEMS.update(ROCKS)
for k, fn in GROUND.items():
    ITEMS[k] = (lambda f: (lambda: [f().build("Body", default_texel=0.15)]))(fn)
ITEMS.update(STONES)

done, groups, errors = [], [], {}
for name, fn in ITEMS.items():
    if ONLY and name not in ONLY:
        continue
    try:
        obs = fn()
        K.export(obs, os.path.join(OUT, name + ".glb"))
        done.append(name); groups.append(obs)
    except Exception:
        import traceback; errors[name] = traceback.format_exc()[-700:]
print("DONE", len(done), done)
for k, v in errors.items():
    print("ERROR", k, v)
if groups:
    K.preview(groups, os.path.join(TEX, "preview_nature.png"), cols=8)
