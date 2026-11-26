# Batch 2 item models: elemental reagents (flora / fungi), food, ores. Original designs.
# Origin = base centre (sits on the ground), +Z up. ~0.2-0.35 m so they read as pickups.
# Run: blender -b --factory-startup -P make_items_gather.py -- <tex_dir> <glb_dir> [name ...]
import bpy, math, os, sys, random
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib, item_kit as K
importlib.reload(K)
from item_kit import Builder, ring_z

ARGS = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT, ONLY = ARGS[0], ARGS[1], set(ARGS[2:])
K.init(TEX)
K.std_mats()
D = math.radians
RX = lambda a: Matrix.Rotation(D(a), 3, 'X')
RY = lambda a: Matrix.Rotation(D(a), 3, 'Y')
RZ = lambda a: Matrix.Rotation(D(a), 3, 'Z')
T = lambda v: Matrix.Translation(v)

M = K.tex_mat
M("stem", [(84,140,58),(70,120,46),(104,164,72),(50,90,34)], seed=301)
M("pepper", [(212,48,34),(186,36,26),(236,82,50),(150,24,18)], seed=302, rough=0.4)
M("capblue", [(120,176,222),(100,156,206),(150,200,240),(232,246,255)], seed=303,
  stripes=lambda x, y, r: r.random() < .07)
M("palestem", [(226,222,206),(206,202,186),(240,238,226),(180,176,160)], seed=304)
M("thistle", [(146,86,196),(124,68,172),(170,112,214),(250,220,90)], seed=305,
  stripes=lambda x, y, r: (x + y) % 7 == 0)
M("petalblue", [(80,170,230),(60,148,212),(120,200,246),(40,110,180)], seed=306, rough=0.3)
M("puff", [(150,140,128),(128,118,108),(172,164,152),(90,82,76)], seed=307,
  stripes=lambda x, y, r: r.random() < .08)
M("petalwhite", [(246,244,232),(226,224,210),(255,255,246),(206,200,180)], seed=308)
M("moss", [(164,84,170),(140,66,148),(190,110,196),(100,46,110)], seed=309,
  stripes=lambda x, y, r: (x * x + y) % 9 == 0)
M("apple", [(214,62,40),(190,46,30),(236,108,58),(250,170,70)], seed=310, rough=0.45,
  stripes=lambda x, y, r: x % 6 == 0 and r.random() < .5)
M("root", [(196,116,52),(170,96,40),(220,142,72),(130,72,30)], seed=311,
  stripes=lambda x, y, r: y % 4 == 0 and r.random() < .5)
M("comb", [(232,170,48),(210,146,34),(250,198,84),(170,110,20)], seed=312, rough=0.35)
M("ore_rock", [(110,106,104),(92,88,86),(132,128,124),(70,66,64)], seed=313)
M("ironore", [(96,104,118),(78,86,100),(140,150,164),(54,58,68)], seed=314, metal=True)
G = K.glow_mat
G("g_fire", (255, 120, 40), 2.5); G("g_frostcap", (150, 230, 255), 2.0); G("g_shock", (255, 236, 90), 3.5)
G("g_water", (90, 200, 255), 2.5); G("g_smoke", (170, 150, 190), 1.2); G("g_flash", (255, 255, 230), 5.0)
G("g_chaos", (255, 90, 220), 2.5); G("g_light", (255, 214, 110), 3.5); G("g_honey", (255, 170, 40), 1.8)
G("g_star", (200, 240, 255), 3.0)


def tube(b, mat, pts, radii, n=6):
    """Bent tube through points (stems, peppers): a lathe segment per span."""
    for i in range(len(pts) - 1):
        a, c = Vector(pts[i]), Vector(pts[i + 1])
        d = c - a
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        b.lathe(mat, [(0, radii[i]), (d.length, radii[i + 1])], n, xform=T(a) @ rot)


def ground_leaves(b, mat, n, length, width, z=0.0, seed=0, tilt=0.35):
    r = random.Random(seed)
    for k in range(n):
        a = k / n * math.tau + r.uniform(-.3, .3)
        d = Vector((math.cos(a), math.sin(a), tilt))
        b.leaf(mat, (0, 0, z), d, length * r.uniform(.85, 1.1), width, 0.012,
               side=(-math.sin(a), math.cos(a), 0))


# ------------------------------------------------------------------ elemental flora / fungi
def cinderpepper():
    b = Builder()
    for k, (x, y, rz) in enumerate(((0.0, 0.0, 0), (0.07, 0.03, 140))):
        R = RZ(rz)
        pts = [R @ Vector(p) + Vector((x, y, 0)) for p in
               ((0, 0, 0.2), (0.03, 0, 0.17), (0.06, 0, 0.11), (0.07, 0, 0.05), (0.05, 0, 0.015))]
        tube(b, "pepper", pts, [0.03, 0.038, 0.034, 0.024, 0.0], 7)
        tube(b, "stem", [pts[0] + Vector((0, 0, -0.01)), pts[0] + Vector((-0.01, 0, 0.04))], [0.012, 0.008], 5)
        b.lathe("stem", [(-0.012, 0.035), (0.004, 0.025)], 6, xform=T(pts[0]))
        b.octa("g_fire", pts[-1] + Vector((0, 0, 0.012)), 0.014)
    return [b.build("Body", {"pepper": 0.06})]


def frostcap():
    b = Builder()
    for k, (x, y, s) in enumerate(((0, 0, 1.0), (0.08, -0.05, 0.62), (-0.07, -0.04, 0.5))):
        b.lathe("palestem", [(0, 0.03 * s), (0.12 * s, 0.022 * s), (0.15 * s, 0.026 * s)], 6, x=x, y=y)
        b.lathe("g_frostcap", [(0.14 * s, 0.07 * s), (0.15 * s, 0.11 * s)], 8, x=x, y=y)
        b.lathe("capblue", [(0.15 * s, 0.115 * s), (0.18 * s, 0.11 * s), (0.22 * s, 0.07 * s), (0.24 * s, 0.0)], 8, x=x, y=y)
        b.octa("palestem", (x + 0.04 * s, y - 0.05 * s, 0.205 * s), 0.014 * s)
        b.octa("palestem", (x - 0.05 * s, y + 0.02 * s, 0.2 * s), 0.012 * s)
    return [b.build("Body", {"capblue": 0.08, "palestem": 0.05})]


def sparkthistle():
    b = Builder()
    tube(b, "stem", [(0, 0, 0), (0.01, 0, 0.12), (0, 0, 0.2)], [0.012, 0.01, 0.01], 5)
    ground_leaves(b, "stem", 4, 0.12, 0.05, 0.03, seed=5, tilt=0.6)
    hz = 0.24
    b.lathe("stem", [(0.18, 0.012), (0.205, 0.05), (0.225, 0.045)], 7)
    b.blob("thistle", (0, 0, hz), 0.045, (1, 1, 1.15), 1, 0.05, 9)
    r = random.Random(4)
    for k in range(14):
        a, e = r.uniform(0, math.tau), r.uniform(D(-10), D(80))
        d = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
        base = Vector((0, 0, hz)) + d * 0.04
        b.cone_tip("thistle", [base + Matrix.Rotation(i * math.tau / 3, 3, d) @ (d.orthogonal().normalized() * 0.008) for i in range(3)],
                   tuple(base + d * 0.055))
    b.octa("g_shock", (0, 0, hz + 0.05), 0.022, 0.035)
    return [b.build("Body", {"thistle": 0.06, "stem": 0.05})]


def dewbloom():
    b = Builder()
    b.lathe("leafgreen", [(0.0, 0.14), (0.012, 0.14)], 10, sy=0.9)                     # lily pad
    b.lathe("stem", [(0.012, 0.02), (0.05, 0.016)], 6)
    for ring, (n, L, W, tilt, z) in enumerate(((6, 0.11, 0.06, 1.1, 0.05), (5, 0.09, 0.05, 2.2, 0.06))):
        for k in range(n):
            a = (k + ring * 0.5) / n * math.tau
            b.leaf("petalblue", (0, 0, z), (math.cos(a), math.sin(a), tilt), L, W, 0.012,
                   side=(-math.sin(a), math.cos(a), 0))
    b.octa("g_water", (0, 0, 0.11), 0.03, 0.045)                                        # glowing droplet
    b.cone_tip("g_water", ring_z(0.11, 0.022, 6), (0, 0, 0.17))
    return [b.build("Body", {"leafgreen": 0.12, "petalblue": 0.06})]


def smolderpuff():
    b = Builder()
    for k, (x, y, s) in enumerate(((0, 0, 1.0), (0.09, 0.03, 0.6), (-0.05, 0.07, 0.45))):
        b.blob("puff", (x, y, 0.085 * s), 0.09 * s, (1, 1, 0.85), 1, 0.08, 40 + k)
        b.lathe("g_smoke", [(0.155 * s, 0.022 * s), (0.17 * s, 0.014 * s)], 6, x=x, y=y)   # vent
        b.lathe("palestem", [(0, 0.05 * s), (0.02 * s, 0.06 * s)], 6, x=x, y=y)
    for k, (x, y, z, r) in enumerate(((0.0, 0.0, 0.22, 0.025), (0.02, 0.01, 0.27, 0.018), (-0.01, 0.0, 0.31, 0.012))):
        b.blob("g_smoke", (x, y, z), r, (1, 1, 1), 0, 0.1, 60 + k)                      # smoke wisps
    return [b.build("Body", {"puff": 0.07})]


def glarepetal():
    b = Builder()
    tube(b, "stem", [(0, 0, 0), (0.015, 0, 0.1), (0, 0, 0.19)], [0.01, 0.009, 0.008], 5)
    ground_leaves(b, "stem", 3, 0.1, 0.045, 0.02, seed=8, tilt=0.4)
    for k in range(10):
        a = k / 10 * math.tau
        b.leaf("petalwhite", (0, 0, 0.2), (math.cos(a), math.sin(a), 0.25), 0.085, 0.035, 0.01,
               side=(-math.sin(a), math.cos(a), 0))
    b.lathe("g_flash", [(0.19, 0.03), (0.215, 0.035), (0.225, 0.0)], 8)
    return [b.build("Body", {"petalwhite": 0.05, "stem": 0.05})]


def muddlemoss():
    b = Builder()
    b.blob("moss", (0, 0, 0.04), 0.11, (1.2, 1.0, 0.45), 1, 0.18, 70)
    b.blob("moss", (0.06, 0.04, 0.07), 0.06, (1, 1, 0.8), 1, 0.2, 71)
    r = random.Random(3)
    for k in range(4):                                                                  # curly tendrils
        a = k / 4 * math.tau + 0.4
        base = Vector((math.cos(a) * 0.05, math.sin(a) * 0.04, 0.07))
        pts = [base]
        for s in range(5):
            t = s * 1.3 + a
            pts.append(pts[-1] + Vector((math.cos(t) * 0.025, math.sin(t) * 0.025, 0.03)))
        tube(b, "moss", pts, [0.012, 0.011, 0.01, 0.008, 0.006, 0.0], 5)
        b.octa("g_chaos", pts[-2], 0.012)
    for k in range(5):
        a = r.uniform(0, math.tau)
        b.octa("g_chaos", (math.cos(a) * 0.09, math.sin(a) * 0.07, 0.065), 0.01)
    return [b.build("Body", {"moss": 0.06})]


def lumenbell():
    b = Builder()
    ground_leaves(b, "leafgreen", 3, 0.1, 0.045, 0.01, seed=11, tilt=0.5)
    pts = [(0, 0, 0), (0.0, 0, 0.14), (0.03, 0, 0.24), (0.09, 0, 0.27), (0.13, 0, 0.24)]
    tube(b, "stem", pts, [0.012, 0.011, 0.01, 0.009, 0.008], 5)
    for k, (p, s) in enumerate(((Vector((0.13, 0, 0.24)), 1.0), (Vector((0.05, 0.0, 0.255)), 0.75))):
        b.lathe("stem", [(0.0, 0.006), (0.015, 0.012)], 5, x=p.x, y=p.y, xform=T((0, 0, p.z - 0.015)))
        b.lathe("g_light", [(-0.06 * s, 0.045 * s), (-0.045 * s, 0.04 * s), (-0.015 * s, 0.03 * s), (0.0, 0.0)], 8,
                x=p.x, y=p.y, xform=T((0, 0, p.z - 0.012)))
    b.lathe("g_light", [(0.0, 0.0), (0.004, 0.02)], 6, x=0.05, xform=T((0, 0, 0.18)))  # seed
    return [b.build("Body", {"stem": 0.05, "leafgreen": 0.08})]


# ------------------------------------------------------------------ food
def hearthapple():
    b = Builder()
    b.lathe("apple", [(0.0, 0.0), (0.01, 0.05), (0.05, 0.085), (0.1, 0.08), (0.13, 0.05), (0.135, 0.02)], 10)
    tube(b, "darkwood", [(0, 0, 0.12), (0.01, 0, 0.17)], [0.008, 0.006], 4)
    b.leaf("leafgreen", (0.01, 0, 0.16), (1, 0.3, 0.3), 0.07, 0.035, 0.01)
    return [b.build("Body", {"apple": 0.06})]


def stoutroot():
    b = Builder()
    pts = [(0, 0, 0.05), (0.05, 0, 0.06), (0.11, 0, 0.055), (0.17, 0, 0.04), (0.21, 0, 0.03)]
    tube(b, "root", pts, [0.05, 0.055, 0.045, 0.03, 0.0], 8)
    b.lathe("root", [(0.0, 0.0), (0.05, 0.05)], 8, xform=T((0.0, 0, 0.05)) @ RY(-90).to_4x4())
    for k in range(5):
        a = k / 5 * math.tau
        b.leaf("leafgreen", (-0.045, 0, 0.05), (-0.6, math.cos(a), 1.0 + math.sin(a) * 0.4), 0.11, 0.035, 0.01)
    for x in (0.08, 0.14):
        b.box("darkwood", (x, 0, 0.05), (0.004, 0.1, 0.004))                           # root rings
    return [b.build("Body", {"root": 0.05})]


def amberdrip_comb():
    b = Builder()
    for k, (x, y, h) in enumerate(((0, 0, 0.13), (0.065, 0.0375, 0.11), (0.065, -0.0375, 0.1),
                                   (-0.065, 0.0375, 0.12), (-0.065, -0.0375, 0.09), (0, 0.075, 0.1),
                                   (0, -0.075, 0.08))):
        b.lathe("comb", [(0.0, 0.04), (h, 0.04)], 6, x=x, y=y, rot=0.0)
        b.lathe("g_honey", [(h, 0.026), (h + 0.004, 0.026)], 6, x=x, y=y, rot=0.0)
    b.lathe("g_honey", [(0.13, 0.014), (0.06, 0.01), (0.03, 0.0)], 6, x=0.03, y=-0.03)   # drip
    b.blob("g_honey", (0.09, -0.06, 0.008), 0.03, (1.2, 1, 0.25), 0, 0.05, 81)          # puddle
    return [b.build("Body", {"comb": 0.04})]


# ------------------------------------------------------------------ ores
def ore(seed, crystal_mat, n, cluster_scale, glow=None):
    b = Builder()
    b.blob("ore_rock", (0, 0, 0.07), 0.11, (1.25, 1.0, 0.7), 1, 0.15, seed)
    b.blob("ore_rock", (0.08, 0.05, 0.05), 0.06, (1, 1, 0.8), 1, 0.2, seed + 1)
    r = random.Random(seed)
    for k in range(n):
        a = r.uniform(0, math.tau)
        tilt = r.uniform(15, 45)
        base = Vector((math.cos(a) * 0.06, math.sin(a) * 0.045, 0.1))
        rot = Matrix.Rotation(a, 3, 'Z') @ RY(tilt)
        s = cluster_scale * r.uniform(.7, 1.15)
        b.lathe(crystal_mat, [(0, 0.022 * s), (0.06 * s, 0.026 * s), (0.09 * s, 0.0)], 5,
                xform=T(base) @ rot.to_4x4())
    if glow:
        b.octa(glow, (0, 0, 0.17), 0.02)
    return b


def coppergleam_ore():
    return [ore(90, "copper", 5, 1.0).build("Body", {"ore_rock": 0.07, "copper": 0.04})]


def ironvein_ore():
    b = ore(95, "ironore", 4, 1.1)
    for k in range(3):                                                                  # silver veins
        b.box("ironore", (0.0, -0.075, 0.04 + k * 0.035), (0.2, 0.01, 0.012), RX(10) @ RZ(k * 25 - 25))
    return [b.build("Body", {"ore_rock": 0.07, "ironore": 0.04})]


def starsilver_ore():
    return [ore(99, "g_star", 6, 1.2, "g_star").build("Body", {"ore_rock": 0.07})]


# ------------------------------------------------------------------ basic materials
def wood_bundle():
    b = Builder()
    M("logend", [(214,170,110),(196,150,92),(230,190,130),(150,104,60)], seed=330,
      stripes=lambda x, y, r: (abs(x - 16) + abs(y - 16)) % 5 == 0)
    for k, (y, z) in enumerate(((-0.07, 0.06), (0.07, 0.06), (0.0, 0.17))):
        rot = RY(90).to_4x4()
        b.lathe("wood", [(-0.17, 0.06), (0.17, 0.06)], 7, xform=T((0, y, z)) @ rot)
        for sx in (-1, 1):
            b.lathe("logend", [(sx * 0.171 - 0.001, 0.052), (sx * 0.171 + 0.001, 0.052)], 7, xform=T((0, y, z)) @ rot)
    for x in (-0.09, 0.09):
        b.box("rope", (x, 0, 0.11), (0.03, 0.27, 0.27))
    return [b.build("Body", {"wood": 0.08, "rope": 0.05})]


ITEMS = {
    "wood_bundle": wood_bundle,
    "cinderpepper": cinderpepper, "frostcap": frostcap, "sparkthistle": sparkthistle, "dewbloom": dewbloom,
    "smolderpuff": smolderpuff, "glarepetal": glarepetal, "muddlemoss": muddlemoss, "lumenbell": lumenbell,
    "hearthapple": hearthapple, "stoutroot": stoutroot, "amberdrip_comb": amberdrip_comb,
    "coppergleam_ore": coppergleam_ore, "ironvein_ore": ironvein_ore, "starsilver_ore": starsilver_ore,
}

done, groups, errors = [], [], {}
for name, fn in ITEMS.items():
    if ONLY and name not in ONLY:
        continue
    try:
        obs = fn()
        K.export(obs, os.path.join(OUT, name + ".glb"))
        done.append(name); groups.append(obs)
    except Exception:
        import traceback; errors[name] = traceback.format_exc()[-700:]
print("DONE", done)
for k, v in errors.items():
    print("ERROR", k, v)
if groups:
    K.preview(groups, os.path.join(TEX, "preview_gather.png"))
