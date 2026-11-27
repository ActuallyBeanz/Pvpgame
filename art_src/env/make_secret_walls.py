# Bombable wall doorways (Megabonk-style low poly, 32px textures). Two parts per style:
#   wall_frame_<style> : the stone doorway that STAYS: plinths, pillars, a lintel with a keystone,
#                        cornice + style trim (moss / snow caps / carved band / ember veins)
#   wall_fill_<style>  : the cracked rubble plug in the 2.6 x 2.5 m opening (bombs / hammer break it)
#   rubble_<style>     : what's left on the ground after it blows
# Overall 3.6 m wide, 3.2 m tall, 0.8 m thick; origin bottom centre; face toward Blender -Y (Godot +Z).
# Run: blender -b --factory-startup -P make_secret_walls.py -- <tex_dir> <glb_dir>
import bpy, math, os, sys, random
from mathutils import Vector, Matrix
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
T("wallbasalt", [(62,56,58),(50,45,47),(78,70,70),(34,30,32)], 604)
T("wallsnow", [(150,156,168),(132,138,150),(170,176,188),(104,110,122)], 605)
K.tex_mat("rubblefill", [(120,114,106),(100,95,88),(140,134,126),(80,76,70)], seed=606)
K.tex_mat("crack", [(30,26,24),(22,18,16),(44,38,34),(12,10,10)], seed=603)
K.tex_mat("moss", [(76,128,52),(60,108,42),(96,150,64),(46,84,34)], seed=607)
K.tex_mat("snowcap", [(236,242,250),(222,230,242),(248,250,255),(200,212,228)], seed=608)
K.glow_mat("g_ember", (255, 110, 40), 2.6)
K.glow_mat("g_rune", (120, 220, 255), 1.6)
D = math.radians
W, H, TH = 3.6, 3.2, 0.8
OW, OH = 2.6, 2.5                            # opening


def frame(mat, style, seed):
    b = Builder()
    r = random.Random(seed)
    pw = (W - OW) / 2                        # pillar width 0.5
    for sx in (-1, 1):
        cx = sx * (OW / 2 + pw / 2)
        b.box(mat, (cx, 0, 0.12), (pw + 0.16, TH + 0.16, 0.24))                       # plinth
        z = 0.24
        while z < OH - 0.05:                                                           # stacked pillar stones
            h = min(r.uniform(0.42, 0.62), OH - z)
            b.box(mat, (cx + r.uniform(-0.02, 0.02), r.uniform(-0.02, 0.02), z + h / 2), (pw - 0.02, TH - 0.02, h - 0.025))
            z += h
        b.box(mat, (cx, 0, OH + 0.08), (pw + 0.12, TH + 0.12, 0.16))                    # capital
    # lintel blocks + a big keystone
    x = -W / 2
    while x < W / 2 - 0.05:
        w = min(r.uniform(0.55, 0.8), W / 2 - x)
        b.box(mat, (x + w / 2, 0, OH + 0.16 + 0.24), (w - 0.025, TH, 0.46))
        x += w
    b.box(mat, (0, -0.06, OH + 0.34), (0.5, TH + 0.14, 0.66))                           # keystone (sticks out)
    b.box(mat, (0, 0, H - 0.05), (W + 0.18, TH + 0.18, 0.12))                          # cornice
    if style == "stone":
        for i in range(6):                                                              # moss tufts on top
            b.blob("moss", (r.uniform(-1.6, 1.6), r.uniform(-0.3, 0.3), H + 0.02), r.uniform(0.12, 0.22), (1.4, 1.0, 0.45), 1, 0.25, seed + 40 + i)
        for i in range(4):                                                              # moss dripping down a pillar
            b.blob("moss", (-1.55 + r.uniform(-0.1, 0.1), -TH / 2 - 0.02, H - 0.3 - i * 0.35), 0.12, (1.2, 0.5, 1.0), 0, 0.2, seed + 60 + i)
    elif style == "snow":
        b.box("snowcap", (0, 0, H + 0.06), (W + 0.26, TH + 0.26, 0.12))
        for sx in (-1, 1):
            b.box("snowcap", (sx * (OW / 2 + pw / 2), 0, OH + 0.2), (pw + 0.18, TH + 0.18, 0.08))
        for i in range(5):                                                              # icicles off the cornice
            b.lathe("ice", [(H - 0.42 - r.uniform(0, 0.2), 0.0), (H - 0.12, 0.05)], 4, x=r.uniform(-1.5, 1.5), y=-TH / 2 - 0.08)
    elif style == "sand":
        b.box("g_rune", (0, -TH / 2 - 0.011, OH + 0.34), (0.16, 0.02, 0.3))             # carved glyph glowing faintly
        for sx in (-1, 1):
            for k in range(3):
                b.box("brass", (sx * (OW / 2 + pw / 2), -TH / 2 - 0.01, 0.7 + k * 0.6), (0.2, 0.02, 0.05))
    elif style == "basalt":
        for sx in (-1, 1):
            b.box("g_ember", (sx * (OW / 2 + pw / 2) + 0.12 * sx, -TH / 2 - 0.011, 1.2), (0.04, 0.02, 1.6), Matrix.Rotation(D(8 * sx), 3, 'Y'))
        b.box("g_ember", (0, -TH / 2 - 0.08, OH + 0.34), (0.06, 0.02, 0.4))
    return [b.build("Body", {mat: 0.4, "moss": 0.3, "snowcap": 0.4})]


def fill(mat, seed):
    b = Builder()
    r = random.Random(seed)
    b.box("crack", (0, 0.22, OH / 2), (OW, 0.24, OH))                                   # dark backing
    rows = 5
    for row in range(rows):
        z0 = row * OH / rows
        x = -OW / 2
        k = 0
        while x < OW / 2 - 0.05:
            w = min(r.uniform(0.45, 0.8), OW / 2 - x)
            missing = row in (1, 2, 3) and abs(x + w / 2) < 0.45 and r.random() < 0.45
            if not missing:
                rot = Matrix.Rotation(D(r.uniform(-4, 4)), 3, 'Y')
                b.box(mat if r.random() < 0.5 else "rubblefill", (x + w / 2, r.uniform(-0.06, 0.04), z0 + OH / rows / 2),
                      (w - 0.05, TH - 0.2, OH / rows - 0.05), rot)
            x += w
            k += 1
    pts = [(-0.15, 2.4), (0.18, 1.9), (-0.2, 1.4), (0.25, 0.9), (-0.05, 0.4), (0.12, 0.0)]  # the big crack (the tell)
    for (x0, z0), (x1, z1) in zip(pts[:-1], pts[1:]):
        c = Vector(((x0 + x1) / 2, -TH / 2 + 0.07, (z0 + z1) / 2))
        L = math.hypot(x1 - x0, z1 - z0)
        ang = math.atan2(x1 - x0, z1 - z0)
        b.box("crack", c, (0.09, 0.04, L + 0.06), Matrix.Rotation(-ang, 3, 'Y'))
    for (x0, z0, x1, z1) in ((0.18, 1.9, 0.9, 2.2), (0.25, 0.9, 1.0, 0.6), (-0.2, 1.4, -1.0, 1.7), (-0.05, 0.4, -0.8, 0.2)):
        c = Vector(((x0 + x1) / 2, -TH / 2 + 0.07, (z0 + z1) / 2))
        L = math.hypot(x1 - x0, z1 - z0)
        ang = math.atan2(x1 - x0, z1 - z0)
        b.box("crack", c, (0.06, 0.04, L), Matrix.Rotation(-ang, 3, 'Y'))
    for i in range(4):                                                                  # crumbs at the foot
        b.blob("rubblefill", (r.uniform(-1.1, 1.1), -TH / 2 - 0.15, 0.08), r.uniform(0.1, 0.18), (1, 1, 0.7), 1, 0.2, seed + i)
    return [b.build("Body", {"rubblefill": 0.4, mat: 0.4, "crack": 0.2})]


def rubble(mat, seed):
    b = Builder()
    r = random.Random(seed)
    for i in range(16):
        a = r.uniform(0, math.tau)
        d = r.uniform(0, 1.5)
        s = r.uniform(0.16, 0.42)
        b.blob("rubblefill" if i % 3 else mat, (math.cos(a) * d, math.sin(a) * d * 0.7, s * 0.5), s, (1.2, 1.0, 0.7), 1, 0.25, seed + i)
    return [b.build("Body", {mat: 0.4, "rubblefill": 0.4})]


STYLES = {"stone": "wallstone", "sand": "wallsand", "basalt": "wallbasalt", "snow": "wallsnow"}
groups = []
for i, (style, mat) in enumerate(STYLES.items()):
    fr = frame(mat, style, 10 + i)
    K.export(fr, os.path.join(OUT, "wall_frame_" + style + ".glb"))
    fi = fill(mat, 20 + i)
    K.export(fi, os.path.join(OUT, "wall_fill_" + style + ".glb"))
    ru = rubble(mat, 30 + i)
    K.export(ru, os.path.join(OUT, "rubble_" + style + ".glb"))
    for o in ru:
        bpy.data.objects.remove(o)
    groups.append(fr + fi)
print("DONE walls")
K.preview(groups, os.path.join(TEX, "preview_walls.png"), cols=4)
