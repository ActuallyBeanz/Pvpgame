# Burnable wooden props (Megabonk-style low poly, 32px textures). Original designs.
# Origin at the floor centre. Blender -Y = Godot +Z (the shack's door faces Godot +Z).
#   crate   : 1 x 1 x 1 m plank crate, dark posts, a cross brace, iron corner caps
#   barrel  : ~0.8 m wide, 1.05 m tall, staves + iron hoops + lid
#   shack   : 4 x 4 m plank hut, door gap (front), window (left), pitched shingle roof
# Run: blender -b --factory-startup -P make_props_wood.py -- <tex_dir> <glb_dir>
import bpy, math, os, sys
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
M("shingle", [(150,70,52),(128,58,42),(172,90,66),(90,40,30)], seed=903, stripes=lambda x, y, r: y % 6 == 0)
M("stave", [(140,94,56),(120,80,46),(160,112,70),(84,54,30)], seed=904, stripes=lambda x, y, r: x % 6 == 0)
D = math.radians
RZ = lambda d: Matrix.Rotation(D(d), 3, 'Z')
RY = lambda d: Matrix.Rotation(D(d), 3, 'Y')
RX = lambda d: Matrix.Rotation(D(d), 3, 'X')


def crate():
    b = Builder()
    s = 1.0
    h = s / 2
    for x in (-1, 1):                                                  # corner posts
        for y in (-1, 1):
            b.box("plank_dark", (x * (h - 0.06), y * (h - 0.06), h), (0.12, 0.12, s))
    for z in (0.06, s - 0.06):                                         # top / bottom rails
        for y in (-1, 1):
            b.box("plank_dark", (0, y * (h - 0.06), z), (s, 0.12, 0.12))
        for x in (-1, 1):
            b.box("plank_dark", (x * (h - 0.06), 0, z), (0.12, s, 0.12))
    for i in range(3):                                                 # plank faces (slightly inset)
        z = 0.2 + i * 0.3
        for y in (-1, 1):
            b.box("plank", (0, y * (h - 0.04), z), (s - 0.2, 0.06, 0.26))
        for x in (-1, 1):
            b.box("plank", (x * (h - 0.04), 0, z), (0.06, s - 0.2, 0.26))
    for k in range(3):
        b.box("plank", (0, -0.3 + k * 0.3, s - 0.04), (s - 0.2, 0.26, 0.06))   # lid planks
    for y in (-1, 1):                                                  # cross braces front/back
        b.box("plank_dark", (0, y * (h - 0.01), h), (1.2, 0.05, 0.1), RY(45))
    for x in (-1, 1):
        for y in (-1, 1):
            for z in (0.02, s - 0.02):
                b.box("darkiron", (x * (h - 0.02), y * (h - 0.02), z), (0.16, 0.16, 0.05))
    return [b.build("Body", {"plank": 0.25, "plank_dark": 0.25})]


def barrel():
    b = Builder()
    prof = [(0.0, 0.34), (0.08, 0.37), (0.3, 0.42), (0.52, 0.44), (0.74, 0.42), (0.96, 0.37), (1.04, 0.34)]
    b.lathe("stave", prof, 12)
    for z, r in ((0.14, 0.395), (0.88, 0.395), (0.4, 0.435), (0.64, 0.435)):
        b.lathe("darkiron", [(z - 0.03, r + 0.015), (z + 0.03, r + 0.015)], 12)
    b.lathe("plank_dark", [(1.0, 0.3), (1.05, 0.3)], 12)                   # lid
    b.box("plank_dark", (0, 0, 1.06), (0.5, 0.06, 0.03))
    return [b.build("Body", {"stave": 0.2, "plank_dark": 0.2})]


def shack():
    b = Builder()
    W, Dp, H, T = 4.0, 4.0, 2.6, 0.15       # width (x), depth (y), wall height, wall thickness
    hx, hy = W / 2, Dp / 2
    b.box("plank_dark", (0, 0, 0.05), (W + 0.2, Dp + 0.2, 0.1))             # floor
    # walls: back (+y), right (+x), left (-x) with a window, front (-y) with a door gap
    b.box("plank", (0, hy - T / 2, H / 2 + 0.1), (W, T, H))
    b.box("plank", (hx - T / 2, 0, H / 2 + 0.1), (T, Dp, H))
    win_z0, win_z1, win_y = 1.1, 1.9, 0.6                                   # left wall window
    b.box("plank", (-hx + T / 2, 0, win_z0 / 2 + 0.1), (T, Dp, win_z0))
    b.box("plank", (-hx + T / 2, 0, (win_z1 + H) / 2 + 0.1), (T, Dp, H - win_z1))
    b.box("plank", (-hx + T / 2, (win_y + hy) / 2 + 0.0, (win_z0 + win_z1) / 2 + 0.1), (T, hy - win_y, win_z1 - win_z0))
    b.box("plank", (-hx + T / 2, (-win_y - hy) / 2, (win_z0 + win_z1) / 2 + 0.1), (T, hy - win_y, win_z1 - win_z0))
    door_w, door_h = 1.3, 2.1
    side = (W - door_w) / 2
    for sx in (-1, 1):
        b.box("plank", (sx * (door_w / 2 + side / 2), -hy + T / 2, H / 2 + 0.1), (side, T, H))
    b.box("plank", (0, -hy + T / 2, (door_h + H) / 2 + 0.1), (door_w, T, H - door_h))
    for sx in (-1, 1):                                                       # door frame
        b.box("plank_dark", (sx * (door_w / 2 + 0.05), -hy + 0.02, door_h / 2 + 0.1), (0.12, 0.22, door_h))
    b.box("plank_dark", (0, -hy + 0.02, door_h + 0.16), (door_w + 0.3, 0.22, 0.12))
    for sx in (-1, 1):                                                       # corner posts
        for sy in (-1, 1):
            b.box("plank_dark", (sx * (hx - 0.05), sy * (hy - 0.05), H / 2 + 0.1), (0.24, 0.24, H + 0.1))
    for z in (0.45, 1.5, 2.55):                                              # horizontal beams (outside)
        b.box("plank_dark", (0, hy + 0.01, z), (W, 0.08, 0.1))
        b.box("plank_dark", (hx + 0.01, 0, z), (0.08, Dp, 0.1))
    # gables (triangles front / back) + roof (ridge along x)
    rise, over = 1.1, 0.35
    for sy in (-1, 1):
        y = sy * (hy - T / 2)
        bm = b.bm("plank")
        v = [bm.verts.new(p) for p in ((-hx, y, H + 0.1), (hx, y, H + 0.1), (0, y, H + 0.1 + rise))]
        bm.faces.new(v)
        bm.faces.new(list(reversed([bm.verts.new(Vector(p) + Vector((0, sy * -T, 0))) for p in ((-hx, y, H + 0.1), (hx, y, H + 0.1), (0, y, H + 0.1 + rise))])))
    ang = math.degrees(math.atan2(rise, hx))
    slope = math.hypot(hx + over, rise + over * rise / hx)
    for sx in (-1, 1):
        cx = sx * (hx + over) / 2
        cz = H + 0.1 + rise / 2 - over * rise / hx / 2 + 0.08
        b.box("shingle", (cx, 0, cz), (slope, Dp + 2 * over, 0.14), RY(sx * ang))
        for k in range(4):                                                   # shingle ridges
            t = (k + 0.5) / 4
            px = sx * t * (hx + over)
            pz = H + 0.1 + rise * (1 - t) + 0.17 - over * rise / hx * t
            b.box("shingle", (px, 0, pz), (0.08, Dp + 2 * over, 0.05), RY(sx * ang))
    b.box("plank_dark", (0, 0, H + 0.1 + rise + 0.1), (0.2, Dp + 2 * over + 0.1, 0.2))     # ridge beam
    return [b.build("Body", {"plank": 0.5, "plank_dark": 0.4, "shingle": 0.4})]


ITEMS = {"crate_wood": crate, "barrel_wood": barrel, "shack_wood": shack}
groups = []
for name, fn in ITEMS.items():
    obs = fn()
    K.export(obs, os.path.join(OUT, name + ".glb"))
    groups.append(obs)
print("DONE props")
K.preview(groups, os.path.join(TEX, "preview_props_wood.png"), cols=3)
