# Bombable "cracked" walls + the rubble left behind (Megabonk-style low poly, 32px textures).
# Wall: 3.6 m wide, 3.2 m tall, 0.8 m thick, origin at the bottom centre, face toward Blender -Y
# (Godot +Z). The cracks are the tell: dark, jagged seams + a few chunks already missing.
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
K.tex_mat("wallstone", [(146,140,130),(126,120,112),(166,160,150),(98,92,86)], seed=601,
          stripes=lambda x, y, r: y % 8 == 0 or (x + (y // 8) * 5) % 10 == 0)
K.tex_mat("wallsand", [(214,170,112),(194,150,94),(232,192,136),(160,118,70)], seed=602,
          stripes=lambda x, y, r: y % 8 == 0 or (x + (y // 8) * 5) % 10 == 0)
K.tex_mat("crack", [(30,26,24),(22,18,16),(44,38,34),(12,10,10)], seed=603)
D = math.radians


def wall(mat, seed):
    b = Builder()
    r = random.Random(seed)
    W, H, T = 3.6, 3.2, 0.8
    # block courses (slightly uneven bricks)
    rows = 5
    for row in range(rows):
        z0 = row * H / rows
        x = -W / 2
        k = 0
        while x < W / 2 - 0.05:
            w = min(r.uniform(0.7, 1.2) if (row + k) % 2 else r.uniform(0.5, 0.9), W / 2 - x)
            if not (row in (1, 2) and abs(x + w / 2) < 0.35 and r.random() < 0.6):     # a missing chunk or two
                b.box(mat, (x + w / 2, r.uniform(-0.03, 0.03), z0 + H / rows / 2), (w - 0.03, T, H / rows - 0.03))
            x += w
            k += 1
    # recessed backing so missing chunks show darkness, not daylight
    b.box("crack", (0, 0.25, H / 2), (W - 0.2, 0.2, H - 0.1))
    # jagged crack seams across the face (the tell)
    pts = [(-0.2, 2.9), (0.15, 2.3), (-0.25, 1.8), (0.3, 1.2), (-0.1, 0.6), (0.2, 0.05)]
    for (x0, z0), (x1, z1) in zip(pts[:-1], pts[1:]):
        c = Vector(((x0 + x1) / 2, -T / 2 - 0.012, (z0 + z1) / 2))
        L = math.hypot(x1 - x0, z1 - z0)
        ang = math.atan2(x1 - x0, z1 - z0)
        b.box("crack", c, (0.07, 0.03, L + 0.05), Matrix.Rotation(-ang, 3, 'Y'))
    for (x0, z0, x1, z1) in ((0.15, 2.3, 0.9, 2.6), (0.3, 1.2, 1.1, 0.9), (-0.25, 1.8, -1.0, 2.1), (-0.1, 0.6, -0.8, 0.4)):
        c = Vector(((x0 + x1) / 2, -T / 2 - 0.012, (z0 + z1) / 2))
        L = math.hypot(x1 - x0, z1 - z0)
        ang = math.atan2(x1 - x0, z1 - z0)
        b.box("crack", c, (0.05, 0.03, L), Matrix.Rotation(-ang, 3, 'Y'))
    # a few loose stones at the foot
    for i in range(3):
        b.blob(mat, (r.uniform(-1.4, 1.4), -T / 2 - 0.25, 0.1), r.uniform(0.12, 0.2), (1, 1, 0.7), 1, 0.2, seed + i)
    return [b.build("Body", {mat: 0.4, "crack": 0.2})]


def rubble(mat, seed):
    b = Builder()
    r = random.Random(seed)
    for i in range(14):
        a = r.uniform(0, math.tau)
        d = r.uniform(0, 1.6)
        s = r.uniform(0.18, 0.45)
        b.blob(mat, (math.cos(a) * d, math.sin(a) * d * 0.8, s * 0.5), s, (1.2, 1.0, 0.7), 1, 0.25, seed + i)
    return [b.build("Body", {mat: 0.4})]


for name, fn in (("wall_cracked_stone", lambda: wall("wallstone", 1)), ("wall_cracked_sand", lambda: wall("wallsand", 2)),
                 ("rubble_stone", lambda: rubble("wallstone", 3)), ("rubble_sand", lambda: rubble("wallsand", 4))):
    obs = fn()
    K.export(obs, os.path.join(OUT, name + ".glb"))
    for o in obs:
        bpy.data.objects.remove(o)
print("DONE walls")
