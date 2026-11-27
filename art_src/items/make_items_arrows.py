# Special arrows (Megabonk-style low poly, 32px textures). Original designs.
# Same layout as arrow_basic.glb: tip at the origin, pointing Godot -Z (Blender +Y),
# shaft ~0.78 m long behind it. Built along +Z here, then turned onto +Y.
#   arrow_fire  : ember-wrapped head, red fletching
#   arrow_frost : ice-crystal head, white/blue fletching
#   arrow_shock : forked brass head with a spark core, yellow fletching
#   arrow_bomb  : a little Blastgourd lashed behind a brass cap, lit fuse, dark fletching
# Run: blender -b --factory-startup -P make_items_arrows.py -- <tex_dir> <glb_dir>
import bpy, math, os, sys
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
M("gourd", [(120,62,40),(100,50,32),(146,82,54),(214,170,96)], seed=203, stripes=lambda x, y, r: x % 8 == 0)
M("feather_red", [(196,58,44),(168,44,34),(226,94,70),(120,30,24)], seed=801, stripes=lambda x, y, r: y % 4 == 0)
M("feather_ice", [(232,244,252),(206,226,242),(250,252,255),(120,180,228)], seed=802, stripes=lambda x, y, r: y % 4 == 0)
M("feather_gold", [(236,196,70),(214,170,48),(250,224,120),(150,110,30)], seed=803, stripes=lambda x, y, r: y % 4 == 0)
M("feather_soot", [(62,58,60),(48,44,46),(84,80,80),(170,70,40)], seed=804, stripes=lambda x, y, r: y % 5 == 0)
K.glow_mat("g_ember", (255, 120, 40), 3.0)
K.glow_mat("g_frost", (140, 230, 255), 2.8)
K.glow_mat("g_spark", (255, 230, 120), 4.0)
D = math.radians
L = 0.78


def shaft(b, mat="wood"):
    b.lathe(mat, [(-L + 0.01, 0.011), (-0.08, 0.011)], 6)
    b.lathe("darkwood", [(-L - 0.005, 0.013), (-L + 0.015, 0.013)], 6)          # nock


def fletch(b, mat):
    for k in range(3):
        a = k / 3 * math.tau + 0.5
        s = Vector((math.cos(a), math.sin(a), 0))
        b.leaf(mat, Vector((0, 0, -0.6)) + s * 0.028, (0, 0, -1), 0.17, 0.05, 0.004, side=s)


def arrow_fire():
    b = Builder()
    shaft(b); fletch(b, "feather_red")
    b.lathe("darkiron", [(-0.1, 0.0), (-0.095, 0.03), (0.0, 0.0)], 4, sy=0.5)    # flat iron head
    b.lathe("cloth_red", [(-0.19, 0.02), (-0.1, 0.02)], 6)                         # oil-soaked wrap
    for k in range(4):
        a = k / 4 * math.tau
        b.octa("g_ember", (math.cos(a) * 0.022, math.sin(a) * 0.022, -0.145), 0.012, 0.03)
    return [b.build("Body", {"wood": 0.08})]


def arrow_frost():
    b = Builder()
    shaft(b); fletch(b, "feather_ice")
    b.lathe("ice", [(-0.16, 0.0), (-0.11, 0.035), (-0.05, 0.03), (0.0, 0.0)], 5)   # crystal head
    b.octa("g_frost", (0, 0, -0.08), 0.014, 0.04)
    for k in range(3):                                                             # little shards
        a = k / 3 * math.tau
        rot = Matrix.Rotation(a, 4, 'Z') @ Matrix.Rotation(D(55), 4, 'Y')
        b.lathe("ice", [(0.0, 0.012), (0.06, 0.0)], 4, xform=Matrix.Translation((0, 0, -0.13)) @ rot)
    return [b.build("Body", {"wood": 0.08})]


def arrow_shock():
    b = Builder()
    shaft(b); fletch(b, "feather_gold")
    b.lathe("brass", [(-0.12, 0.016), (-0.08, 0.02)], 6)                           # socket
    for k in range(3):                                                              # forked prongs
        a = k / 3 * math.tau
        b.lathe("brass", [(-0.08, 0.009), (0.0, 0.0)], 4,
                xform=Matrix.Translation((math.cos(a) * 0.012, math.sin(a) * 0.012, 0)))
    b.octa("g_spark", (0, 0, -0.045), 0.016, 0.03)
    b.lathe("g_spark", [(-0.22, 0.014), (-0.2, 0.014)], 6)                          # glowing band
    return [b.build("Body", {"wood": 0.08})]


def arrow_bomb():
    b = Builder()
    shaft(b); fletch(b, "feather_soot")
    b.lathe("brass", [(-0.05, 0.03), (-0.03, 0.03), (0.0, 0.0)], 6)                # cap / nose
    b.lathe("gourd", [(-0.21, 0.012), (-0.19, 0.04), (-0.13, 0.058), (-0.08, 0.05), (-0.05, 0.028)], 8)
    for k in range(4):                                                              # glowing seams
        a = k / 4 * math.tau
        b.box("g_ember", (math.cos(a) * 0.056, math.sin(a) * 0.056, -0.13), (0.008, 0.008, 0.05),
              Matrix.Rotation(a, 3, 'Z'))
    b.lathe("rope", [(-0.23, 0.016), (-0.19, 0.016)], 5)                            # lashing
    fuse = Matrix.Translation((0, 0.03, -0.17)) @ Matrix.Rotation(D(-60), 4, 'X')
    b.lathe("rope", [(0.0, 0.006), (0.06, 0.005)], 4, xform=fuse)                   # fuse
    b.octa("g_spark", (0, 0.03 + 0.052, -0.17 + 0.03), 0.012)
    return [b.build("Body", {"wood": 0.08, "gourd": 0.06})]


ITEMS = {"arrow_fire": arrow_fire, "arrow_frost": arrow_frost, "arrow_shock": arrow_shock, "arrow_bomb": arrow_bomb}
TURN = Matrix.Rotation(D(-90), 4, 'X')            # +Z (built) -> +Y (Blender) = Godot -Z
groups = []
for name, fn in ITEMS.items():
    obs = fn()
    for o in obs:
        o.data.transform(TURN)
    K.export(obs, os.path.join(OUT, name + ".glb"))
    groups.append(obs)
print("DONE arrows")
K.preview(groups, os.path.join(TEX, "preview_arrows.png"), cols=4)
