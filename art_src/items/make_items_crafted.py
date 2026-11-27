# Crafting materials + starter weapons (Megabonk-style low poly, 32px textures). Original designs.
#   stone_chunk / flint_shards : gatherables, origin at the base
#   flint_knife / driftwood_club : held like the Dawnsteel Blade (blade along +Z, origin at the grip)
#   twig_bow : like the Hunter's Bow (vertical, grip at origin, shoots +Y, string at -Y)
# Run: blender -b --factory-startup -P make_items_crafted.py -- <tex_dir> <glb_dir>
import bpy, math, os, sys, random
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib, item_kit as K
importlib.reload(K)
from item_kit import Builder

ARGS = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT = ARGS[0], ARGS[1]
K.init(TEX)
K.std_mats()
M = K.tex_mat
M("flint", [(58,60,70),(44,46,54),(84,88,100),(150,156,170)], seed=701, metal=True, rough=0.25,
  stripes=lambda x, y, r: r.random() < .06)
M("driftwood", [(186,168,140),(166,148,122),(206,190,164),(130,114,92)], seed=702,
  stripes=lambda x, y, r: y % 4 == 0 and r.random() < .7)
M("twig", [(120,86,52),(102,72,42),(142,104,66),(80,56,32)], seed=703, stripes=lambda x, y, r: y % 5 == 0)
M("fiber", [(206,196,150),(188,178,130),(224,214,170),(160,150,104)], seed=704)
D = math.radians
T = lambda v: Matrix.Translation(v)


def tube(b, mat, pts, radii, n=6):
    for i in range(len(pts) - 1):
        a, c = Vector(pts[i]), Vector(pts[i + 1])
        d = c - a
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        b.lathe(mat, [(0, radii[i]), (d.length, radii[i + 1])], n, xform=T(a) @ rot)


def stone_chunk():
    b = Builder()
    for i, (x, y, s) in enumerate(((0, 0, 1.0), (0.09, 0.05, 0.6), (-0.07, 0.07, 0.5))):
        b.blob("stone", (x, y, 0.05 * s), 0.07 * s, (1.1, 1.0, 0.75), 1, 0.2, 10 + i)
    return [b.build("Body", {"stone": 0.06})]


def flint_shards():
    b = Builder()
    for i, (x, y, rz, s) in enumerate(((0, 0, 0, 1.0), (0.07, 0.03, 50, 0.7), (-0.05, 0.06, -40, 0.6))):
        rot = Matrix.Rotation(D(rz), 3, 'Z') @ Matrix.Rotation(D(70), 3, 'X')
        b.lathe("flint", [(0, 0.035 * s), (0.08 * s, 0.03 * s), (0.13 * s, 0.0)], 4,
                xform=T((x, y, 0.02)) @ rot.to_4x4())
    return [b.build("Body", {"flint": 0.05})]


def flint_knife():
    b = Builder()
    tube(b, "twig", [(0, 0, -0.16), (0, 0, 0.1)], [0.022, 0.025], 6)                 # handle
    b.lathe("fiber", [(0.04, 0.03), (0.12, 0.03)], 6)                                   # lashing
    b.lathe("flint", [(0.1, 0.045), (0.3, 0.04), (0.48, 0.0)], 4, rot=0.0, sy=0.3)      # knapped blade
    b.box("flint", (0, 0, 0.11), (0.1, 0.03, 0.03))
    return [b.build("Body", {"twig": 0.06, "flint": 0.06})]


def driftwood_club():
    b = Builder()
    tube(b, "driftwood", [(0, 0, -0.2), (0.01, 0, 0.3), (0.03, 0, 0.62), (0.0, 0, 0.82)], [0.03, 0.04, 0.07, 0.06], 7)
    b.lathe("fiber", [(-0.12, 0.036), (0.06, 0.036)], 6)                                # grip wrap
    r = random.Random(5)
    for i in range(4):                                                                   # knots
        z = 0.45 + i * 0.09
        a = r.uniform(0, math.tau)
        b.blob("driftwood", (math.cos(a) * 0.06, math.sin(a) * 0.06, z), 0.035, (1, 1, 1), 0, 0.2, 20 + i)
    b.blob("stone", (0.0, 0.0, 0.7), 0.075, (1.1, 1.0, 1.2), 1, 0.15, 30)               # stone lashed in the head
    b.lathe("fiber", [(0.64, 0.072), (0.68, 0.072)], 6)
    return [b.build("Body", {"driftwood": 0.08})]


def twig_bow():
    b = Builder()
    pts = []
    for k in range(9):
        z = -0.55 + k * 0.1375
        y = 0.12 * (1.0 - (z / 0.55) ** 2)
        pts.append((0.0, y, z))
    tube(b, "twig", pts, [0.016, 0.02, 0.024, 0.027, 0.03, 0.027, 0.024, 0.02, 0.016], 5)
    b.lathe("fiber", [(-0.07, 0.034), (0.07, 0.034)], 6, y=0.12)                       # grip wrap
    tube(b, "fiber", [(0, 0.0, -0.55), (0, 0.0, 0.55)], [0.004, 0.004], 3)              # string
    return [b.build("Body", {"twig": 0.08, "fiber": 0.05})]


ITEMS = {"stone_chunk": stone_chunk, "flint_shards": flint_shards, "flint_knife": flint_knife,
         "driftwood_club": driftwood_club, "twig_bow": twig_bow}
groups = []
for name, fn in ITEMS.items():
    obs = fn()
    K.export(obs, os.path.join(OUT, name + ".glb"))
    groups.append(obs)
print("DONE crafted")
K.preview(groups, os.path.join(TEX, "preview_crafted.png"), cols=5)
