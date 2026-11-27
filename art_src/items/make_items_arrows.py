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
K.glow_mat("g_water", (90, 170, 255), 2.2)
K.glow_mat("g_flash", (255, 255, 220), 5.0)
K.glow_mat("g_muddle", (190, 110, 255), 2.6)
K.glow_mat("g_light", (255, 230, 140), 4.0)
M("feather_blue", [(70,120,210),(54,100,186),(100,150,230),(30,60,130)], seed=805, stripes=lambda x, y, r: y % 4 == 0)
M("feather_grey", [(140,140,146),(118,118,124),(170,170,176),(80,80,86)], seed=806, stripes=lambda x, y, r: y % 4 == 0)
M("feather_white", [(240,240,232),(220,220,210),(255,255,248),(200,190,120)], seed=807, stripes=lambda x, y, r: y % 4 == 0)
M("feather_violet", [(130,80,180),(110,64,160),(160,110,206),(70,40,110)], seed=808, stripes=lambda x, y, r: y % 4 == 0)
M("feather_amber", [(230,180,90),(206,156,66),(250,210,130),(150,100,40)], seed=809, stripes=lambda x, y, r: y % 4 == 0)
M("moss", [(96,120,60),(78,100,48),(120,146,76),(150,90,180)], seed=810)
M("puff", [(150,146,140),(128,124,120),(176,172,166),(96,92,90)], seed=811)
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


def arrow_water():
    b = Builder()
    shaft(b); fletch(b, "feather_blue")
    b.lathe("ice", [(-0.13, 0.0), (-0.1, 0.04), (-0.05, 0.035), (0.0, 0.0)], 8)          # dew drop head
    b.octa("g_water", (0, 0, -0.07), 0.016, 0.03)
    b.lathe("leafgreen", [(-0.17, 0.014), (-0.13, 0.024)], 6)                          # leaf cup
    return [b.build("Body", {"wood": 0.08})]


def arrow_smoke():
    b = Builder()
    shaft(b); fletch(b, "feather_grey")
    b.lathe("darkiron", [(-0.06, 0.0), (-0.055, 0.025), (0.0, 0.0)], 4, sy=0.5)
    b.blob("puff", (0, 0, -0.12), 0.045, (1, 1, 1.3), 1, 0.2, 41)                       # puffball
    b.blob("puff", (0.025, 0.01, -0.09), 0.025, (1, 1, 1), 0, 0.2, 42)
    b.lathe("rope", [(-0.18, 0.015), (-0.16, 0.015)], 5)
    return [b.build("Body", {"wood": 0.08, "puff": 0.05})]


def arrow_flash():
    b = Builder()
    shaft(b); fletch(b, "feather_white")
    b.lathe("brass", [(-0.1, 0.0), (-0.09, 0.03), (0.0, 0.0)], 4, sy=0.6)
    for k in range(5):                                                                 # petal star
        a = k / 5 * math.tau
        d = Vector((math.cos(a), math.sin(a), -0.4)).normalized()
        b.leaf("g_flash", (0, 0, -0.12), d, 0.06, 0.035, 0.004)
    b.octa("g_flash", (0, 0, -0.12), 0.018)
    return [b.build("Body", {"wood": 0.08})]


def arrow_muddle():
    b = Builder()
    shaft(b); fletch(b, "feather_violet")
    b.lathe("darkiron", [(-0.07, 0.0), (-0.065, 0.025), (0.0, 0.0)], 4, sy=0.5)
    b.blob("moss", (0, 0, -0.13), 0.04, (1, 1, 1.4), 1, 0.25, 43)                      # moss clump
    for k in range(3):
        a = k / 3 * math.tau
        b.octa("g_muddle", (math.cos(a) * 0.04, math.sin(a) * 0.04, -0.13), 0.01)       # spores
    return [b.build("Body", {"wood": 0.08, "moss": 0.05})]


def arrow_light():
    b = Builder()
    shaft(b); fletch(b, "feather_amber")
    b.lathe("brass", [(-0.04, 0.012), (-0.02, 0.012), (0.0, 0.0)], 6)
    b.lathe("brass", [(-0.16, 0.0), (-0.15, 0.04), (-0.08, 0.035), (-0.04, 0.012)], 8)   # little bell
    b.octa("g_light", (0, 0, -0.12), 0.022, 0.035)                                      # glowing clapper
    return [b.build("Body", {"wood": 0.08})]


BREWS = {
    "emberfog": (255, 115, 60), "muddlehaze": (180, 128, 240), "rimemist": (150, 228, 255),
    "stormdrop": (190, 215, 255), "chainspark": (255, 240, 120), "steamburst": (235, 235, 242),
    "sunburst": (255, 242, 180), "mendingdew": (115, 255, 150),
}


def brew_arrow(name, col):
    """A little brew flask lashed behind a brass tip, fletching dyed to match."""
    def make():
        K.glow_mat("liq_" + name, col, 2.0)
        fm = "fl_" + name
        M(fm, [col, tuple(int(c * 0.8) for c in col), tuple(min(255, int(c * 1.1)) for c in col),
               tuple(int(c * 0.5) for c in col)], seed=sum(map(ord, name)), stripes=lambda x, y, r: y % 4 == 0)
        b = Builder()
        shaft(b); fletch(b, fm)
        b.lathe("brass", [(-0.05, 0.022), (-0.03, 0.022), (0.0, 0.0)], 6)
        b.lathe("liq_" + name, [(-0.17, 0.012), (-0.15, 0.04), (-0.1, 0.042), (-0.06, 0.022)], 8)
        b.lathe("ice", [(-0.06, 0.02), (-0.045, 0.02)], 6)
        b.lathe("rope", [(-0.19, 0.015), (-0.165, 0.015)], 5)
        return [b.build("Body", {"wood": 0.08})]
    return make


ITEMS = {"arrow_water": arrow_water, "arrow_smoke": arrow_smoke, "arrow_flash": arrow_flash,
         "arrow_muddle": arrow_muddle, "arrow_light": arrow_light,
         "arrow_fire": arrow_fire, "arrow_frost": arrow_frost, "arrow_shock": arrow_shock, "arrow_bomb": arrow_bomb}
for _n, _c in BREWS.items():
    ITEMS["arrow_" + _n] = brew_arrow(_n, _c)
TURN = Matrix.Rotation(D(-90), 4, 'X')            # +Z (built) -> +Y (Blender) = Godot -Z
groups = []
for name, fn in ITEMS.items():
    obs = fn()
    for o in obs:
        o.data.transform(TURN)
    K.export(obs, os.path.join(OUT, name + ".glb"))
    groups.append(obs)
print("DONE arrows")
K.preview(groups, os.path.join(TEX, "preview_arrows.png"), cols=6)
