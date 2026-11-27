# Path-side cover pieces (replace the old plain boxes). Megabonk-style low poly, 32px textures.
#   cover_ruin_sand  : broken sandstone wall, carved band, toppled block, sand drift   (sand / mesa / beach)
#   cover_ruin_snow  : frost-bitten stone wall, snow cap + icicles, drift               (snow)
#   cover_basalt     : cluster of hex basalt columns with glowing ember cracks          (ash)
#   cover_ruin_stone : mossy field-stone wall stub                                      (grass / forest)
# ~2.8 m wide, up to 1.7 m tall, ~1.1 m deep; origin bottom centre; long side along X.
# Run: blender -b --factory-startup -P make_cover.py -- <tex_dir> <glb_dir>
import bpy, math, os, sys, random
from mathutils import Matrix
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "items"))
import importlib, item_kit as K
importlib.reload(K)
from item_kit import Builder

ARGS = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT = ARGS[0], ARGS[1]
K.init(TEX)
K.std_mats()
T = lambda key, pal, seed: K.tex_mat(key, pal, seed=seed, stripes=lambda x, y, r: y % 8 == 0 or (x + (y // 8) * 5) % 10 == 0)
T("wallstone", [(146,140,130),(126,120,112),(166,160,150),(98,92,86)], 601)
T("wallsand", [(214,170,112),(194,150,94),(232,192,136),(160,118,70)], 602)
T("wallsnow", [(150,156,168),(132,138,150),(170,176,188),(104,110,122)], 605)
K.tex_mat("basaltcol", [(62,56,58),(50,45,47),(78,70,70),(34,30,32)], seed=611)
K.tex_mat("moss", [(76,128,52),(60,108,42),(96,150,64),(46,84,34)], seed=607)
K.tex_mat("snowcap", [(236,242,250),(222,230,242),(248,250,255),(200,212,228)], seed=608)
K.tex_mat("sanddrift", [(226,196,140),(214,182,126),(236,208,156),(198,166,110)], seed=612)
K.tex_mat("carve", [(150,104,60),(136,92,52),(166,118,70),(118,80,44)], seed=613)
K.glow_mat("g_ember", (255, 110, 40), 2.4)
D = math.radians
W, DEP = 2.8, 0.9


def wall(b, r, mat, tops, depth=DEP):
    """Stacked block courses; tops = height of each column slice (broken silhouette)."""
    n = len(tops)
    cw = W / n
    for i, top in enumerate(tops):
        x0 = -W / 2 + i * cw
        z = 0.0
        row = 0
        while z < top - 0.05:
            h = min(r.uniform(0.32, 0.42), top - z)
            off = (cw * 0.5) if row % 2 else 0.0
            w = cw + r.uniform(-0.04, 0.04)
            x = x0 + cw / 2 + (off * 0.25 if i < n - 1 else 0)
            b.box(mat, (x + r.uniform(-0.02, 0.02), r.uniform(-0.03, 0.03), z + h / 2),
                  (w - 0.03, depth - r.uniform(0.0, 0.08), h - 0.03), Matrix.Rotation(D(r.uniform(-2, 2)), 3, 'Z'))
            z += h
            row += 1


def ruin_sand(seed):
    b, r = Builder(), random.Random(seed)
    b.box("wallsand", (0, 0, 0.1), (W + 0.25, DEP + 0.25, 0.2))                       # plinth
    wall(b, r, "wallsand", [1.55, 1.65, 1.3, 0.95, 0.6])
    b.box("carve", (-0.55, -DEP / 2 - 0.012, 1.05), (1.4, 0.03, 0.12))                # carved band
    for k in range(4):
        b.box("carve", (-1.1 + k * 0.36, -DEP / 2 - 0.02, 1.05), (0.1, 0.03, 0.1), Matrix.Rotation(D(45), 3, 'Y'))
    b.box("wallsand", (1.05, -0.85, 0.2), (0.6, 0.45, 0.38), Matrix.Rotation(D(23), 3, 'Z'))   # toppled block
    for i in range(5):                                                                   # sand drift at the foot
        b.blob("sanddrift", (r.uniform(-1.3, 1.3), r.choice((-1, 1)) * 0.55, 0.05), r.uniform(0.25, 0.4), (1.8, 1.0, 0.35), 1, 0.15, seed + i)
    return [b.build("Body", {"wallsand": 0.4, "sanddrift": 0.4, "carve": 0.3})]


def ruin_snow(seed):
    b, r = Builder(), random.Random(seed)
    b.box("wallsnow", (0, 0, 0.1), (W + 0.2, DEP + 0.2, 0.2))
    tops = [1.2, 1.6, 1.7, 1.45, 1.0]
    wall(b, r, "wallsnow", tops)
    cw = W / len(tops)
    for i, top in enumerate(tops):                                                       # snow caps follow the broken top
        b.box("snowcap", (-W / 2 + cw * (i + 0.5), 0, top + 0.05), (cw + 0.06, DEP + 0.12, 0.12))
        for k in range(2):                                                               # icicles
            b.lathe("ice", [(top - 0.35 - r.uniform(0, 0.2), 0.0), (top - 0.02, 0.045)], 4,
                    x=-W / 2 + cw * (i + r.uniform(0.2, 0.8)), y=-DEP / 2 - 0.07)
    for i in range(5):
        b.blob("snowcap", (r.uniform(-1.3, 1.3), r.choice((-1, 1)) * 0.6, 0.05), r.uniform(0.25, 0.45), (1.8, 1.0, 0.4), 1, 0.15, seed + i)
    return [b.build("Body", {"wallsnow": 0.4, "snowcap": 0.4})]


def basalt(seed):
    b, r = Builder(), random.Random(seed)
    cols = [(-0.95, 0.05, 1.35, 0.42), (-0.35, -0.15, 2.0, 0.46), (0.3, 0.1, 1.75, 0.44), (0.9, -0.1, 1.15, 0.4), (0.0, 0.45, 1.5, 0.38)]
    for i, (x, y, h, rad) in enumerate(cols):
        tilt = r.uniform(-0.06, 0.06)
        b.lathe("basaltcol", [(0.0, rad), (h * 0.96, rad * 0.96), (h, rad * 0.8), (h + 0.001, 0.0)], 6, x=x + tilt, y=y, rot=r.uniform(0, 1))
        b.box("g_ember", (x + rad * 0.55, y - rad * 0.55, h * 0.45), (0.035, 0.035, h * 0.55), Matrix.Rotation(D(r.uniform(-10, 10)), 3, 'Y'))
    for i in range(4):
        b.blob("basaltcol", (r.uniform(-1.3, 1.3), r.uniform(-0.6, 0.6), 0.08), r.uniform(0.14, 0.26), (1.2, 1.0, 0.7), 1, 0.25, seed + i)
    return [b.build("Body", {"basaltcol": 0.4})]


def ruin_stone(seed):
    b, r = Builder(), random.Random(seed)
    b.box("wallstone", (0, 0, 0.1), (W + 0.2, DEP + 0.2, 0.2))
    tops = [0.9, 1.4, 1.55, 1.25, 0.75]
    wall(b, r, "wallstone", tops)
    cw = W / len(tops)
    for i, top in enumerate(tops):                                                       # moss sitting on each broken top
        b.blob("moss", (-W / 2 + cw * (i + 0.5) + r.uniform(-0.15, 0.15), r.uniform(-0.2, 0.2), top - 0.02), r.uniform(0.16, 0.22), (1.6, 1.4, 0.4), 1, 0.2, seed + 40 + i)
    for i in range(3):
        b.blob("moss", (r.uniform(-1.2, 1.2), -DEP / 2 - 0.02, r.uniform(0.3, 0.9)), 0.13, (1.3, 0.5, 1.0), 0, 0.2, seed + 60 + i)
    return [b.build("Body", {"wallstone": 0.4, "moss": 0.3})]


groups = []
for name, fn, seed in (("cover_ruin_sand", ruin_sand, 71), ("cover_ruin_snow", ruin_snow, 72),
                       ("cover_basalt", basalt, 73), ("cover_ruin_stone", ruin_stone, 74)):
    obs = fn(seed)
    K.export(obs, os.path.join(OUT, name + ".glb"))
    groups.append(obs)
print("DONE cover")
K.preview(groups, os.path.join(TEX, "preview_cover.png"), cols=4)
