# Secret caves: a hollow rock outcrop with ONE way in - the 3.6 x 3.2 m doorway opening at the
# front (the bombable CrackedWall sits in it). Chamber inside ~5 x 6 x 3.4 m with glowing crystals.
# Origin = floor centre of the chamber; the opening faces Blender -Y (Godot +Z) at y = -3.5.
#   cave_<style>   : the shell (collision = its own mesh, made in cave.gd)
#   grapple_post   : wooden anchor post for plateau rims (hookable), banner on top
# Run: blender -b --factory-startup -P make_caves.py -- <tex_dir> <glb_dir>
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
M = K.tex_mat
M("cave_stone", [(112,106,98),(96,90,84),(130,124,116),(76,72,68)], seed=701)
M("cave_sand", [(200,140,86),(180,122,72),(218,160,104),(150,96,56)], seed=702, stripes=lambda x, y, r: y % 7 == 0)
M("cave_basalt", [(52,46,48),(42,37,39),(66,58,58),(30,26,28)], seed=703)
M("cave_snow", [(126,132,146),(110,116,130),(146,152,166),(90,96,110)], seed=704)
M("moss", [(76,128,52),(60,108,42),(96,150,64),(46,84,34)], seed=607)
M("snowcap", [(236,242,250),(222,230,242),(248,250,255),(200,212,228)], seed=608)
M("plank_dark", [(104,70,44),(88,58,36),(124,86,54),(60,40,24)], seed=902, stripes=lambda x, y, r: y % 8 == 0)
M("log", [(112,80,52),(96,68,44),(130,94,62),(70,48,30)], seed=905, stripes=lambda x, y, r: x % 5 == 0)
CRYSTAL = {"stone": (120, 220, 255), "sand": (255, 200, 90), "basalt": (255, 110, 50), "snow": (170, 230, 255)}
D = math.radians
FRONT = -3.5            # opening plane (y)
OW, OH = 3.6, 3.2       # opening = the doorway frame


def shell(style, seed):
    mat = "cave_" + style
    K.glow_mat("g_crystal_" + style, CRYSTAL[style], 2.4)
    b = Builder()
    r = random.Random(seed)
    jit = lambda: Matrix.Rotation(D(r.uniform(-4, 4)), 3, 'Z') @ Matrix.Rotation(D(r.uniform(-3, 3)), 3, 'X')
    # walls (thick, slightly crooked slabs) - the opening is the only gap
    for sx in (-1, 1):
        b.box(mat, (sx * 3.0, FRONT, 2.1), (2.4, 1.2, 4.2), jit())                  # front, either side of the door
        b.box(mat, (sx * 3.5, -0.3, 2.2), (1.4, 7.6, 4.4), jit())                   # side walls
    b.box(mat, (0, FRONT, OH + 0.6), (OW + 0.4, 1.2, 1.2))                         # over the door
    b.box(mat, (0, 3.2, 2.2), (8.4, 1.4, 4.4), jit())                              # back
    b.box(mat, (0, -0.3, 4.1), (8.6, 8.6, 1.2), Matrix.Rotation(D(2), 3, 'X'))     # roof
    # big boulders all over the outside so it reads as a rock outcrop, not a box
    for i in range(22):
        side = r.choice(("l", "r", "b", "t", "t", "f"))
        if side == "l":
            c = (-4.4 - r.uniform(0, 0.6), r.uniform(-3.8, 3.4), r.uniform(0.4, 3.6))
        elif side == "r":
            c = (4.4 + r.uniform(0, 0.6), r.uniform(-3.8, 3.4), r.uniform(0.4, 3.6))
        elif side == "b":
            c = (r.uniform(-4, 4), 4.1 + r.uniform(0, 0.6), r.uniform(0.4, 3.8))
        elif side == "t":
            c = (r.uniform(-3.8, 3.8), r.uniform(-3.4, 3.2), 4.6 + r.uniform(0, 0.5))
        else:                                                                       # front, away from the door
            c = (r.choice((-1, 1)) * r.uniform(2.6, 4.2), FRONT - 0.7, r.uniform(0.6, 3.6))
        s = r.uniform(0.9, 1.7)
        b.blob(mat, c, s, (1.2, 1.0, 0.85), 1, 0.22, seed + i)
    b.blob(mat, (0, FRONT - 0.5, OH + 1.5), 1.1, (1.6, 1.0, 0.7), 1, 0.2, seed + 50)  # brow over the doorway
    # boulders rounding off every top edge and corner (kills the box silhouette)
    k = 0
    for (x0, y0, x1, y1) in ((-4.3, FRONT - 0.4, 4.3, FRONT - 0.4), (-4.3, 3.9, 4.3, 3.9),
                             (-4.4, FRONT, -4.4, 3.9), (4.4, FRONT, 4.4, 3.9)):
        for t in (0.0, 0.25, 0.5, 0.75, 1.0):
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            if abs(x) < 2.2 and y < FRONT + 0.5 and t not in (0.0, 1.0):
                continue                                                            # keep the doorway clear
            b.blob(mat, (x + r.uniform(-0.3, 0.3), y + r.uniform(-0.3, 0.3), 4.1 + r.uniform(-0.4, 0.4)),
                   r.uniform(1.2, 1.9), (1.1, 1.1, 0.9), 1, 0.25, seed + 200 + k)
            k += 1
    for sx in (-1, 1):                                                              # corner buttresses down to the ground
        for sy in (FRONT - 0.3, 3.7):
            for z in (0.8, 2.4):
                b.blob(mat, (sx * 4.4, sy, z), r.uniform(1.3, 1.8), (1.0, 1.0, 1.1), 1, 0.22, seed + 300 + k)
                k += 1
    for sx in (-1, 1):                                                              # rock flanking the door
        b.blob(mat, (sx * 2.9, FRONT - 0.9, 1.2), 1.3, (0.9, 0.8, 1.4), 1, 0.2, seed + 400 + sx)
    # style dressing
    if style == "stone":
        for i in range(10):
            b.blob("moss", (r.uniform(-4, 4), r.uniform(-3.8, 3.6), 4.85), r.uniform(0.4, 0.8), (1.5, 1.2, 0.35), 1, 0.25, seed + 80 + i)
    elif style == "snow":
        b.box("snowcap", (0, -0.3, 4.75), (9.0, 9.0, 0.25))
        for i in range(8):
            b.blob("snowcap", (r.uniform(-4, 4), r.uniform(-3.8, 3.6), 5.0), r.uniform(0.5, 0.9), (1.6, 1.3, 0.4), 1, 0.2, seed + 90 + i)
    # glowing crystal clusters inside (and one by the door, the tell that something's in there)
    for (cx, cy, cz, n) in ((-2.4, 2.2, 0.2, 4), (2.3, 2.3, 0.2, 5), (-2.6, -1.0, 0.1, 3), (2.6, 0.4, 2.9, 3), (-2.3, FRONT - 0.9, 0.1, 2)):
        for k in range(n):
            h = r.uniform(0.35, 0.9)
            rot = Matrix.Rotation(D(r.uniform(-25, 25)), 4, 'X') @ Matrix.Rotation(D(r.uniform(-25, 25)), 4, 'Y')
            b.lathe("g_crystal_" + style, [(0.0, 0.09), (h * 0.7, 0.08), (h, 0.0)], 5,
                    xform=Matrix.Translation((cx + r.uniform(-0.25, 0.25), cy + r.uniform(-0.25, 0.25), cz)) @ rot)
    for i in range(6):                                                              # floor rubble
        b.blob(mat, (r.uniform(-2.2, 2.2), r.uniform(-2, 2.4), 0.05), r.uniform(0.15, 0.3), (1, 1, 0.6), 1, 0.2, seed + 120 + i)
    return [b.build("Body", {mat: 0.5, "moss": 0.4, "snowcap": 0.5})]


def grapple_post():
    b = Builder()
    b.box("log", (0, 0, 1.2), (0.34, 0.34, 2.4))
    b.box("plank_dark", (0, 0, 2.45), (0.48, 0.48, 0.12))
    b.lathe("darkiron", [(1.9, 0.2), (1.98, 0.2), (2.06, 0.2)], 8, y=-0.2)                 # iron ring = the hook point
    b.lathe("darkiron", [(2.4, 0.03), (3.4, 0.03)], 4)                                     # flagpole
    b.box("cloth_red", (0.3, 0, 3.15), (0.55, 0.03, 0.36))                                  # banner: seen from afar
    return [b.build("Body", {"log": 0.4})]


groups = []
for i, style in enumerate(("stone", "sand", "basalt", "snow")):
    obs = shell(style, 10 + i)
    K.export(obs, os.path.join(OUT, "cave_" + style + ".glb"))
    groups.append(obs)
obs = grapple_post()
K.export(obs, os.path.join(OUT, "grapple_post.glb"))
groups.append(obs)
print("DONE caves")
K.preview(groups, os.path.join(TEX, "preview_caves.png"), cols=5)
