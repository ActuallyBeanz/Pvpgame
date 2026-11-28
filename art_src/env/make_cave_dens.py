# Hidden caves: a tunnel into a cliff / hillside that opens into a room UNDER the terrain.
# The terrain gets a hole at the mouth (hidden_cave.gd); a rock face patch + boulders around the
# opening cover the edges. Built from thick slabs, so it looks solid from inside and out.
#   cave_den_<style> : mouth at Blender y=0 (faces -Y = Godot +Z), floor top z=0, goes +Y (Godot -Z)
#                      tunnel 3.4 w x 3.3 h, 7 m long -> room ~10 x 11 x 4.6 m
# Run: blender -b --factory-startup -P make_cave_dens.py -- <tex_dir> <glb_dir>
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
M = K.tex_mat
M("cave_stone", [(112,106,98),(96,90,84),(130,124,116),(76,72,68)], seed=701)
M("cave_sand", [(200,140,86),(180,122,72),(218,160,104),(150,96,56)], seed=702, stripes=lambda x, y, r: y % 7 == 0)
M("cave_basalt", [(52,46,48),(42,37,39),(66,58,58),(30,26,28)], seed=703)
M("cave_snow", [(126,132,146),(110,116,130),(146,152,166),(90,96,110)], seed=704)
M("cave_floor", [(78,72,66),(66,61,56),(92,86,78),(54,50,46)], seed=721)
M("moss", [(76,128,52),(60,108,42),(96,150,64),(46,84,34)], seed=607)
M("snowcap", [(236,242,250),(222,230,242),(248,250,255),(200,212,228)], seed=608)
CRYSTAL = {"stone": (120, 220, 255), "sand": (255, 200, 90), "basalt": (255, 110, 50), "snow": (170, 230, 255)}
D = math.radians
TW, TH, TL = 1.7, 3.3, 7.0           # tunnel half width, height, length
RW, RH, R0, R1 = 5.0, 4.6, 7.0, 18.0  # room half width, height, front y, back y


def den(style, seed):
    mat = "cave_" + style
    K.glow_mat("g_crystal_" + style, CRYSTAL[style], 2.6)
    b = Builder()
    r = random.Random(seed)
    jit = lambda a=3: Matrix.Rotation(D(r.uniform(-a, a)), 3, 'Z') @ Matrix.Rotation(D(r.uniform(-a, a)), 3, 'X')
    # --- tunnel
    for sx in (-1, 1):
        for seg in range(4):
            y0 = -0.1 + seg * (TL + 0.6) / 4
            b.box(mat, (sx * (TW + 0.6 + r.uniform(-0.15, 0.2)), y0 + (TL + 0.6) / 8, TH / 2), (1.2, (TL + 0.6) / 4 + 0.3, TH + 0.6), jit(6))
    for seg in range(3):
        y0 = -0.1 + seg * (TL + 0.6) / 3
        b.box(mat, (0, y0 + (TL + 0.6) / 6, TH + 0.5 + r.uniform(-0.1, 0.15)), (2 * TW + 2.4, (TL + 0.6) / 3 + 0.3, 1.0), jit(4))
    b.box("cave_floor", (0, TL / 2, -0.5), (2 * TW + 2.4, TL + 1.0, 1.0))
    # --- room
    for sx in (-1, 1):
        b.box(mat, (sx * (TW + (RW - TW) / 2 + 0.3), R0 + 0.3, RH / 2), (RW - TW + 0.6, 1.0, RH + 0.4), jit())   # front wall
        b.box(mat, (sx * (RW + 0.6), (R0 + R1) / 2, RH / 2), (1.2, R1 - R0 + 1.6, RH + 0.8), jit())          # side walls
    b.box(mat, (0, R0 + 0.3, TH + (RH - TH) / 2 + 0.2), (2 * TW + 0.8, 1.0, RH - TH + 0.6))                     # lintel
    b.box(mat, (0, R1 + 0.6, RH / 2), (2 * RW + 2.4, 1.2, RH + 0.8), jit())                                     # back
    b.box(mat, (0, (R0 + R1) / 2, RH + 0.5), (2 * RW + 2.4, R1 - R0 + 2.0, 1.0), jit(2))                        # roof
    b.box("cave_floor", (0, (R0 + R1) / 2, -0.5), (2 * RW + 2.4, R1 - R0 + 2.0, 1.0))
    # --- inside: boulders along the walls (round off the box), stalactites, stalagmites
    for i in range(16):
        side = r.choice((-1, 1))
        y = r.uniform(R0 + 1.0, R1 - 0.5)
        s = r.uniform(0.7, 1.2)
        b.blob(mat, (side * (RW - 0.2), y, r.uniform(0.3, RH - 0.6)), s, (0.8, 1.1, 1.0), 1, 0.25, seed + i)
    for i in range(8):
        b.blob(mat, (r.uniform(-RW + 1, RW - 1), R1 - 0.2, r.uniform(0.4, RH - 0.8)), r.uniform(0.8, 1.3), (1.1, 0.7, 1.0), 1, 0.25, seed + 30 + i)
    for sx in (-1, 1):
        for sy in (R0 + 0.6, R1 - 0.4):
            b.blob(mat, (sx * (RW - 0.5), sy, RH - 0.4), 1.2, (1.0, 1.0, 0.9), 1, 0.2, seed + 50 + int(sx * 3 + sy))
    for i in range(26):                                                              # tunnel walls: lumpy rock
        b.blob(mat, (r.choice((-1, 1)) * (TW + 0.05), r.uniform(0.2, TL + 0.2), r.uniform(0.2, TH - 0.2)), r.uniform(0.42, 0.68), (0.65, 1.2, 1.0), 1, 0.28, seed + 70 + i)
    for i in range(9):                                                               # ...and ceiling
        b.blob(mat, (r.uniform(-TW + 0.4, TW - 0.4), r.uniform(0.6, TL), TH + 0.1), r.uniform(0.45, 0.7), (1.1, 1.2, 0.55), 1, 0.28, seed + 200 + i)
    for i in range(10):                                                              # room ceiling lumps
        b.blob(mat, (r.uniform(-RW + 1, RW - 1), r.uniform(R0 + 1, R1 - 1), RH + 0.1), r.uniform(0.8, 1.3), (1.2, 1.2, 0.5), 1, 0.25, seed + 220 + i)
    for i in range(14):                                                              # stalactites
        h = r.uniform(0.5, 1.4)
        x, y = r.uniform(-RW + 0.8, RW - 0.8), r.uniform(R0 + 1.0, R1 - 0.8)
        if abs(x) < 1.6 and y < R0 + 6:
            continue
        b.lathe(mat, [(RH - h, 0.0), (RH - h * 0.5, 0.12), (RH + 0.05, 0.28)], 5, x=x, y=y)
    for i in range(7):                                                               # stalagmites
        h = r.uniform(0.4, 1.1)
        x, y = r.choice((-1, 1)) * r.uniform(2.6, RW - 0.8), r.uniform(R0 + 1.2, R1 - 1.0)
        b.lathe(mat, [(-0.05, 0.32), (h * 0.5, 0.15), (h, 0.0)], 5, x=x, y=y)
    for (cx, cy, cz, n) in ((-RW + 0.9, R1 - 1.2, 0.0, 6), (RW - 0.9, R0 + 1.6, 0.0, 5), (RW - 1.0, R1 - 1.5, 2.6, 4),
                            (-RW + 0.9, R0 + 3.0, 3.0, 3), (-TW + 0.3, TL - 0.8, 0.0, 3), (TW - 0.3, 2.0, 2.6, 2)):
        for k in range(n):
            h = r.uniform(0.4, 1.1)
            rot = Matrix.Rotation(D(r.uniform(-28, 28)), 4, 'X') @ Matrix.Rotation(D(r.uniform(-28, 28)), 4, 'Y')
            b.lathe("g_crystal_" + style, [(0.0, 0.1), (h * 0.7, 0.09), (h, 0.0)], 5,
                    xform=Matrix.Translation((cx + r.uniform(-0.3, 0.3), cy + r.uniform(-0.3, 0.3), cz)) @ rot)
    for i in range(8):                                                               # floor rubble
        b.blob(mat, (r.uniform(-RW + 1, RW - 1), r.uniform(R0 + 1, R1 - 1), 0.05), r.uniform(0.15, 0.32), (1, 1, 0.6), 1, 0.2, seed + 90 + i)
    # --- mouth: an arch of big boulders framing the opening (covers the cut terrain edges)
    for i in range(20):
        a = math.pi * (i + r.uniform(-0.3, 0.3)) / 19.0
        rad = r.uniform(3.0, 3.5)
        x, z = math.cos(a) * rad * 1.1, math.sin(a) * (rad + 0.6) + 0.5
        b.blob(mat, (x, r.uniform(-0.3, 0.5), z), r.uniform(0.85, 1.25), (1.0, 0.9, 1.0), 1, 0.25, seed + 120 + i)
    b.blob(mat, (0, 0.2, TH + 1.7), 1.4, (2.3, 1.1, 0.8), 1, 0.2, seed + 145)          # brow
    for sx in (-1, 1):
        b.blob(mat, (sx * (TW + 0.9), -0.1, 0.5), 0.9, (0.9, 0.8, 1.1), 1, 0.2, seed + 140 + sx)
    if style == "stone":
        for i in range(8):
            b.blob("moss", (r.uniform(-3, 3), -0.2, r.uniform(3.2, 5.2)), r.uniform(0.3, 0.55), (1.4, 0.5, 0.6), 1, 0.25, seed + 160 + i)
    elif style == "snow":
        for i in range(6):
            b.blob("snowcap", (r.uniform(-3, 3), -0.2, r.uniform(4.0, 5.4)), r.uniform(0.4, 0.7), (1.5, 0.6, 0.45), 1, 0.2, seed + 170 + i)
        for i in range(5):
            b.lathe("ice", [(TH + 0.3 - r.uniform(0.3, 0.7), 0.0), (TH + 0.35, 0.06)], 4, x=r.uniform(-1.4, 1.4), y=-0.2)
    return [b.build("Body", {mat: 0.5, "cave_floor": 0.5, "moss": 0.4, "snowcap": 0.5})]


def chimney(style, seed):
    """Rock mass filling the recess carved above a cave mouth: 7.6 wide, ~2.6 deep, 10 tall.
    hidden_cave.gd stacks as many as it needs up to the cliff top. Origin bottom-front-centre."""
    mat = "cave_" + style
    b = Builder()
    r = random.Random(seed)
    b.box(mat, (0, 1.4, 5.0), (7.4, 2.6, 10.0))
    for i in range(16):                                       # lumpy front + sides
        x = r.uniform(-3.4, 3.4)
        b.blob(mat, (x, r.uniform(-0.1, 0.3), r.uniform(0.6, 9.4)), r.uniform(0.9, 1.5), (1.1, 0.6, 1.2), 1, 0.25, seed + i)
    for sx in (-1, 1):
        for k in range(3):
            b.blob(mat, (sx * 3.6, r.uniform(0.6, 2.0), 1.5 + k * 3.3), r.uniform(1.0, 1.4), (0.6, 1.0, 1.2), 1, 0.25, seed + 40 + k * 2 + sx)
    return [b.build("Body", {mat: 0.5})]


groups = []
for i, style in enumerate(("stone", "sand", "basalt", "snow")):
    obs = den(style, 900 + i * 17)
    K.export(obs, os.path.join(OUT, "cave_den_" + style + ".glb"))
    groups.append(obs)
    ch = chimney(style, 950 + i * 13)
    K.export(ch, os.path.join(OUT, "cave_chimney_" + style + ".glb"))
    for o in ch:
        bpy.data.objects.remove(o)
print("DONE dens")
K.preview(groups, os.path.join(TEX, "preview_dens.png"), cols=4)
