# Modular wooden bridge kit (fantasy, Megabonk low poly). Assembled by systems/world/bridge.gd.
# All pieces: origin at the top centre of the deck line, length along Blender +Y (= Godot -Z).
#   bridge_deck   : 1 m deck section, 4 m wide: planks across (slightly uneven), 2 stringers below
#   bridge_post   : rail post (1.1 m) with a cap
#   bridge_rail   : 1 m rail beam (sits between posts, at the top)
#   bridge_pier   : trestle pier legs, 1 m tall unit (stretched down to the river bed)
#   bridge_lantern: tall end post with a hanging glowing lantern (marks bridges from afar)
# Run: blender -b --factory-startup -P make_props_bridge.py -- <tex_dir> <glb_dir>
import bpy, math, os, sys, random
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "items"))
import importlib, item_kit as K
importlib.reload(K)
from item_kit import Builder

ARGS = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT = ARGS[0], ARGS[1]
K.init(TEX)
K.std_mats()
M = K.tex_mat
M("plank", [(150,102,60),(128,86,48),(170,120,74),(92,60,34)], seed=901, stripes=lambda x, y, r: y % 8 == 0)
M("plank_dark", [(104,70,44),(88,58,36),(124,86,54),(60,40,24)], seed=902, stripes=lambda x, y, r: y % 8 == 0)
M("log", [(112,80,52),(96,68,44),(130,94,62),(70,48,30)], seed=905, stripes=lambda x, y, r: x % 5 == 0)
K.glow_mat("g_lantern", (255, 196, 110), 3.5)
D = math.radians
W = 4.0


def deck():
    b = Builder()
    r = random.Random(3)
    for k in range(3):                                              # 3 planks per metre
        y = -0.5 + (k + 0.5) / 3
        tilt = Matrix.Rotation(D(r.uniform(-1.5, 1.5)), 3, 'Y')
        b.box("plank", (r.uniform(-0.05, 0.05), y, -0.06), (W + r.uniform(-0.1, 0.15), 0.3, 0.12), tilt)
    for sx in (-1, 1):                                              # stringers
        b.box("plank_dark", (sx * (W / 2 - 0.35), 0, -0.24), (0.22, 1.02, 0.24))
    return [b.build("Body", {"plank": 0.5, "plank_dark": 0.5})]


def post():
    b = Builder()
    b.box("log", (0, 0, 0.55), (0.18, 0.18, 1.1))
    b.box("plank_dark", (0, 0, 1.12), (0.26, 0.26, 0.08))
    b.octa("plank_dark", (0, 0, 1.2), 0.1, 0.08)
    return [b.build("Body", {"log": 0.4})]


def rail():
    b = Builder()
    b.box("plank_dark", (0, 0, 0.98), (0.12, 1.0, 0.12))
    b.box("plank_dark", (0, 0, 0.55), (0.08, 1.0, 0.08))
    return [b.build("Body", {"plank_dark": 0.5})]


def pier():
    b = Builder()
    for sx in (-1, 1):                                              # legs only: the pier is stretched to the bed
        b.box("log", (sx * (W / 2 - 0.5), 0, -0.5), (0.3, 0.3, 1.0))
    return [b.build("Body", {"log": 0.4})]


def lantern():
    b = Builder()
    b.box("log", (0, 0, 1.3), (0.26, 0.26, 2.6))
    b.box("plank_dark", (0, -0.35, 2.45), (0.12, 0.8, 0.12))          # arm reaching out over the deck
    b.lathe("darkiron", [(1.92, 0.0), (1.95, 0.12), (2.05, 0.14), (2.32, 0.12), (2.36, 0.0)], 6, y=-0.65)
    b.lathe("g_lantern", [(1.98, 0.09), (2.28, 0.09)], 6, y=-0.65)
    b.box("rope", (0, -0.65, 2.4), (0.03, 0.03, 0.12))
    b.octa("plank_dark", (0, 0, 2.66), 0.18, 0.12)
    return [b.build("Body", {"log": 0.4})]


ITEMS = {"bridge_deck": deck, "bridge_post": post, "bridge_rail": rail, "bridge_pier": pier, "bridge_lantern": lantern}
groups = []
for name, fn in ITEMS.items():
    obs = fn()
    K.export(obs, os.path.join(OUT, name + ".glb"))
    groups.append(obs)
print("DONE bridge")
K.preview(groups, os.path.join(TEX, "preview_bridge.png"), cols=5)
