# Batch 1 item models: heavy melees, slingshot, world tools, throwables. Original designs.
#   Melee / staffs / rods / fan: shaft along +Z (Godot +Y), origin at the grip centre, flat in Y
#   (same convention as the Dawnsteel Blade, so the same hand rotation works).
#   Slingshot: fork up +Z, origin at the grip.  Bomb: origin at its centre.  Trap: origin at its base.
# Run: blender -b --factory-startup -P make_items_weapons.py -- <tex_dir> <glb_dir> [name ...]
import bpy, math, os, sys
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

K.tex_mat("ember_iron", [(58,48,46),(44,36,34),(80,66,60),(150,60,30)], seed=201, metal=True,
          stripes=lambda x, y, r: y % 9 == 0 and r.random() < .3)
K.tex_mat("maulstone", [(118,112,104),(96,92,86),(142,136,126),(70,66,62)], seed=202,
          stripes=lambda x, y, r: (x * 3 + y) % 11 == 0)
K.tex_mat("gourd", [(120,62,40),(100,50,32),(146,82,54),(214,170,96)], seed=203,
          stripes=lambda x, y, r: x % 8 == 0)
K.tex_mat("cloth_blue", [(58,86,150),(46,70,128),(78,108,176),(32,50,96)], seed=204)
K.glow_mat("g_ember", (255, 120, 40), 3.0)
K.glow_mat("g_amber", (255, 190, 70), 2.6)
K.glow_mat("g_frost", (140, 230, 255), 2.8)
K.glow_mat("g_gale", (170, 255, 190), 2.0)
K.glow_mat("g_spark", (255, 230, 120), 4.0)


def grip(b, z0, z1, r=0.026, mat="leather", rings="brass"):
    b.lathe(mat, [(z0, r), (z1, r)], 8)
    for z in (z0, z1):
        b.lathe(rings, [(z - 0.012, r * 1.3), (z + 0.012, r * 1.3)], 8)


# ------------------------------------------------------------------ Emberfang Greatsword
def greatsword():
    b = Builder()
    # blade: 4-sided diamond section, wide in X, thin in Y; serrated "fang" notches near the base
    prof = [(0.16, 0.13), (0.36, 0.17), (0.5, 0.15), (1.4, 0.14), (1.85, 0.12), (2.12, 0.07), (2.3, 0.0)]
    b.lathe("ember_iron", prof, 4, rot=0.0, sy=0.16)
    b.lathe("g_ember", [(0.42, 0.018), (1.95, 0.012)], 4, rot=0.0, sy=1.6)          # glowing fuller
    for i in range(3):                                                                  # fangs
        z = 0.42 + i * 0.12
        for sx in (-1, 1):
            b.cone_tip("ember_iron", [Vector((sx * 0.14, -0.014, z)), Vector((sx * 0.14, 0.014, z)),
                                       Vector((sx * 0.14, 0.014, z + 0.07)), Vector((sx * 0.14, -0.014, z + 0.07))],
                       (sx * 0.21, 0, z + 0.06))
    # crossguard with down-swept quillons + ember gem
    b.box("darkiron", (0, 0, 0.13), (0.5, 0.08, 0.08))
    for sx in (-1, 1):
        b.box("darkiron", (sx * 0.24, 0, 0.09), (0.08, 0.06, 0.12), RY(sx * 25))
        b.octa("brass", (sx * 0.27, 0, 0.03), 0.03)
    b.octa("g_ember", (0, -0.04, 0.14), 0.035)
    b.octa("g_ember", (0, 0.04, 0.14), 0.035)
    # long two-hand grip + pommel
    grip(b, -0.3, 0.09, 0.03)
    b.lathe("leather", [(-0.11, 0.034), (-0.08, 0.034)], 8)
    b.lathe("darkiron", [(-0.42, 0.0), (-0.38, 0.05), (-0.33, 0.045), (-0.31, 0.03)], 6)
    b.octa("g_ember", (0, 0, -0.43), 0.025)
    return [b.build("Body", {"ember_iron": 0.14, "leather": 0.08})]


# ------------------------------------------------------------------ Quakeheart Maul
def maul():
    b = Builder()
    b.lathe("darkwood", [(-0.32, 0.03), (0.95, 0.034)], 8)                            # haft
    grip(b, -0.25, 0.22, 0.036)
    for z in (0.45, 0.7):
        b.lathe("copper", [(z, 0.042), (z + 0.03, 0.042)], 8)
    b.lathe("copper", [(-0.4, 0.0), (-0.36, 0.05), (-0.32, 0.045)], 6)                # butt cap
    hz = 1.08
    b.box("maulstone", (0, 0, hz), (0.56, 0.3, 0.3))                                  # head block
    for sx in (-1, 1):
        b.box("maulstone", (sx * 0.31, 0, hz), (0.06, 0.24, 0.24))                    # striking faces
        b.box("copper", (sx * 0.2, 0, hz), (0.04, 0.32, 0.32))                        # bands
        b.box("g_amber", (sx * 0.342, 0, hz), (0.008, 0.16, 0.03))                    # glowing cracks
        b.box("g_amber", (sx * 0.342, 0, hz + 0.04), (0.008, 0.03, 0.12))
    b.box("copper", (0, 0, hz + 0.16), (0.18, 0.18, 0.04))                            # top cap
    b.octa("g_amber", (0, 0, hz + 0.2), 0.04)
    for sy in (-1, 1):
        b.octa("brass", (0, sy * 0.155, hz), 0.035)                                   # rivets
    return [b.build("Body", {"maulstone": 0.16, "darkwood": 0.1})]


# ------------------------------------------------------------------ Thornfork Slingshot
def slingshot():
    b = Builder()
    b.lathe("wood", [(-0.12, 0.02), (0.05, 0.022)], 6)
    b.lathe("leather", [(-0.09, 0.025), (0.02, 0.025)], 6)
    b.lathe("wood", [(0.04, 0.024), (0.08, 0.03)], 6)
    tips = []
    for sx in (-1, 1):
        a = Vector((sx * 0.012, 0, 0.07)); t = Vector((sx * 0.085, 0, 0.21))
        d = (t - a); L = d.length
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
        b.lathe("wood", [(0, 0.018), (L, 0.015)], 6, xform=Matrix.Translation(a) @ rot.to_4x4())
        b.lathe("brass", [(L - 0.02, 0.019), (L + 0.005, 0.019)], 6, xform=Matrix.Translation(a) @ rot.to_4x4())
        for k in range(2):                                                            # thorns
            p = a + d * (0.35 + 0.3 * k)
            b.cone_tip("wood", [p + Vector((0, -0.006, -0.006)), p + Vector((0, 0.006, -0.006)),
                                p + Vector((0, 0.006, 0.006)), p + Vector((0, -0.006, 0.006))],
                       tuple(p + Vector((sx * 0.03, 0, 0.01))))
        tips.append(t)
    # band + pouch, pulled slightly back (-Y)
    pouch = Vector((0, -0.05, 0.2))
    for t in tips:
        m = (t + pouch) / 2; d = pouch - t
        b.box("leather", m, (0.008, d.length, 0.012), RZ(math.degrees(math.atan2(-d.x, d.y))))
    b.box("leather", pouch, (0.05, 0.02, 0.03))
    b.blob("stone", pouch + Vector((0, -0.005, 0)), 0.015, subdiv=1, seed=3)
    return [b.build("Body", {"wood": 0.06, "leather": 0.05})]


def slingstones():
    b = Builder()
    b.blob("leather", (0, 0, 0.06), 0.07, (1.0, 1.0, 0.8), 1, 0.08, 7)               # pouch
    b.lathe("rope", [(0.1, 0.035), (0.12, 0.03)], 6)
    b.lathe("leather", [(0.12, 0.03), (0.15, 0.045)], 6)
    for i, (x, y) in enumerate(((0.07, -0.03), (-0.06, -0.05), (0.02, -0.08))):
        b.blob("stone", (x, y, 0.025), 0.028, (1, 1, 0.8), 1, 0.15, 20 + i)
    return [b.build("Body", {"leather": 0.08, "stone": 0.05})]


def slingstone():
    b = Builder()
    b.blob("stone", (0, 0, 0), 0.03, (1, 1, 0.85), 1, 0.15, 31)
    return [b.build("Body", {"stone": 0.05})]


# ------------------------------------------------------------------ Galeleaf Fan
def fan():
    b = Builder()
    b.lathe("wood", [(-0.18, 0.02), (0.2, 0.022)], 6)
    b.lathe("rope", [(-0.14, 0.025), (0.04, 0.025)], 6)
    b.lathe("brass", [(0.18, 0.03), (0.22, 0.03)], 6)
    b.octa("g_gale", (0, 0, -0.2), 0.025)
    # big main leaf + two side leaves fanned out (flat in the X-Z plane)
    b.leaf("leafgreen", (0, 0, 0.2), (0, 0, 1), 0.72, 0.5, 0.03, side=(1, 0, 0))
    for sx in (-1, 1):
        b.leaf("leafgreen", (sx * 0.02, 0.02, 0.2), (sx * 1.0, 0, 0.75), 0.55, 0.32, 0.025, side=(0.6, 0, -sx * 0.8))
    b.lathe("g_gale", [(0.22, 0.008), (0.84, 0.004)], 4)                               # glowing vein
    for k in range(3):
        z = 0.38 + k * 0.14
        for sx in (-1, 1):
            b.box("g_gale", (sx * 0.06, 0, z + 0.03), (0.12, 0.006, 0.006), RY(sx * -35))
    return [b.build("Body", {"leafgreen": 0.2, "wood": 0.06})]


# ------------------------------------------------------------------ Sandspire Staff
def sand_staff():
    b = Builder()
    b.lathe("darkwood", [(-0.7, 0.022), (0.75, 0.026)], 6)
    b.lathe("cloth_red", [(-0.12, 0.03), (0.12, 0.03)], 6)
    b.lathe("brass", [(-0.74, 0.0), (-0.7, 0.03), (-0.66, 0.028)], 6)
    # stepped sandstone spire
    z = 0.75
    for i, (w, h, rot) in enumerate(((0.19, 0.12, 0), (0.155, 0.15, 20), (0.13, 0.15, 40), (0.1, 0.13, 60))):
        b.box("sand", (0, 0, z + h / 2), (w, w, h), RZ(rot))
        z += h
    b.cone_tip("sand", ring_z(z, 0.07, 4, rot=0.0), (0, 0, z + 0.2))
    # brass cradle prongs holding a glowing amber orb in front of the spire
    for sx in (-1, 1):
        b.box("brass", (sx * 0.11, -0.06, 0.95), (0.025, 0.025, 0.3), RY(sx * -20))
    b.octa("g_amber", (0, -0.13, 1.0), 0.075)
    for sx in (-1, 1):
        b.box("sand", (sx * 0.14, 0, 0.82), (0.07, 0.07, 0.07), RZ(45))
    return [b.build("Body", {"sand": 0.08, "darkwood": 0.1})]


# ------------------------------------------------------------------ Rimecaller Rod
def rime_rod():
    b = Builder()
    b.lathe("steel", [(-0.4, 0.018), (0.5, 0.02)], 6)
    grip(b, -0.15, 0.12, 0.024, "cloth_blue", "steel")
    b.lathe("brass", [(-0.44, 0.0), (-0.4, 0.026), (-0.37, 0.024)], 6)
    b.lathe("brass", [(0.48, 0.022), (0.54, 0.08), (0.58, 0.08), (0.61, 0.05)], 6)    # head cup
    # ice crystal cluster
    b.octa("ice", (0, 0, 0.82), 0.085, 0.27)
    for i, (a, tilt, s) in enumerate(((0, 30, 0.8), (120, 35, 0.7), (240, 28, 0.75))):
        d = Matrix.Rotation(D(a), 3, 'Z') @ Matrix.Rotation(D(tilt), 3, 'X')
        c = Vector((0, 0, 0.68)) + d @ Vector((0, 0, 0.1))
        b.octa("ice", c, 0.05 * s, 0.19 * s)
    b.octa("g_frost", (0, 0, 0.82), 0.05, 0.15)
    for sx in (-1, 1):
        b.box("steel", (sx * 0.05, 0, 0.6), (0.012, 0.012, 0.1), RY(sx * -25))
    return [b.build("Body", {"ice": 0.06, "steel": 0.08})]


# ------------------------------------------------------------------ Blastgourd Bomb
def bomb():
    b = Builder()
    b.lathe("gourd", [(-0.12, 0.0), (-0.1, 0.08), (-0.03, 0.125), (0.05, 0.11), (0.1, 0.06), (0.12, 0.035)], 10)
    for k in range(5):                                                                 # glowing seams
        a = k / 5 * math.tau
        b.box("g_ember", (math.cos(a) * 0.118, math.sin(a) * 0.118, -0.02), (0.012, 0.012, 0.1),
              RZ(math.degrees(a)))
    b.lathe("brass", [(0.115, 0.04), (0.145, 0.04)], 8)                                 # cap
    b.lathe("rope", [(0.145, 0.012), (0.2, 0.01)], 5, xform=Matrix.Translation((0.0, 0, 0)) @ RY(12).to_4x4())
    b.octa("g_spark", (0.04, 0, 0.21), 0.022)
    return [b.build("Body", {"gourd": 0.08})]


# ------------------------------------------------------------------ Snapjaw Trap
def trap():
    b = Builder()
    b.lathe("darkiron", [(0.0, 0.2), (0.025, 0.2)], 10)                                 # base ring plate
    b.lathe("brass", [(0.025, 0.07), (0.04, 0.07)], 8)                                  # pressure plate
    b.octa("g_amber", (0, 0, 0.045), 0.02, 0.008)
    for sx in (-1, 1):                                                                  # open jaws, teeth up
        cx = sx * 0.13
        b.box("darkiron", (cx, 0, 0.035), (0.04, 0.34, 0.02))
        for k in range(5):
            y = -0.13 + k * 0.065
            b.cone_tip("steel", [Vector((cx - 0.015, y - 0.015, 0.045)), Vector((cx + 0.015, y - 0.015, 0.045)),
                                 Vector((cx + 0.015, y + 0.015, 0.045)), Vector((cx - 0.015, y + 0.015, 0.045))],
                       (cx, y, 0.1))
    for sy in (-1, 1):                                                                  # springs
        b.lathe("steel", [(0, 0.03), (0.05, 0.03)], 6,
                xform=Matrix.Translation((-0.025, sy * 0.2, 0.03)) @ RY(90).to_4x4())
    b.lathe("steel", [(0.0, 0.008), (0.12, 0.008)], 4, xform=Matrix.Translation((0.19, 0, 0.02)) @ RY(90).to_4x4())
    b.cone_tip("darkiron", ring_z(0.02, 0.018, 4, x=0.33), (0.33, 0, -0.08))           # stake
    return [b.build("Body", {"darkiron": 0.08})]


ITEMS = {
    "greatsword_emberfang": greatsword, "maul_quakeheart": maul, "slingshot_thornfork": slingshot,
    "slingstones": slingstones, "slingstone": slingstone, "fan_galeleaf": fan,
    "staff_sandspire": sand_staff, "rod_rimecaller": rime_rod, "bomb_blastgourd": bomb,
    "trap_snapjaw": trap,
}

done, groups, errors = [], [], {}
for name, fn in ITEMS.items():
    if ONLY and name not in ONLY:
        continue
    try:
        obs = fn()
        K.export(obs, os.path.join(OUT, name + ".glb"))
        done.append(name); groups.append(obs)
    except Exception as e:
        import traceback; errors[name] = traceback.format_exc()[-600:]
print("DONE", done)
for k, v in errors.items():
    print("ERROR", k, v)
if groups:
    K.preview(groups, os.path.join(TEX, "preview_weapons.png"))
