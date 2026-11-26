# Treasure chests, one look per loot tier (the look tells you how good it is):
#   common = plain wood · uncommon = iron-banded · rare = blue + gold, glowing gem · legendary = ornate purple + gold, big glow
# Two objects per glb: "Base" and "Lid" (Lid origin on the back hinge: rotate it about X to open).
# Front faces Blender -Y (Godot +Z). Origin = base centre on the ground.
# Run: blender -b --factory-startup -P make_items_chests.py -- <tex_dir> <glb_dir>
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
M("chest_wood", [(150,98,56),(128,82,46),(172,118,70),(96,60,34)], seed=501, stripes=lambda x, y, r: y % 6 == 0)
M("chest_blue", [(52,82,150),(42,68,128),(70,104,176),(30,48,96)], seed=502, stripes=lambda x, y, r: y % 6 == 0)
M("chest_purple", [(104,52,140),(86,40,118),(130,72,168),(62,26,88)], seed=503, stripes=lambda x, y, r: y % 6 == 0)
M("gold", [(240,196,72),(220,170,52),(255,224,120),(180,130,30)], seed=504, metal=True)
K.glow_mat("g_blue", (90, 180, 255), 3.0)
K.glow_mat("g_purple", (220, 110, 255), 3.5)
K.glow_mat("g_gold", (255, 210, 90), 2.5)

TIERS = {   # body, band, trim, glow, size (w, d, base h, lid h), extra
    "common":    ("chest_wood", "darkwood", "darkiron", None, (0.9, 0.6, 0.4, 0.22), 0),
    "uncommon":  ("chest_wood", "steel", "steel", None, (1.0, 0.65, 0.44, 0.24), 1),
    "rare":      ("chest_blue", "gold", "gold", "g_blue", (1.08, 0.7, 0.48, 0.27), 2),
    "legendary": ("chest_purple", "gold", "gold", "g_purple", (1.2, 0.78, 0.52, 0.3), 3),
}


def chest(body, band, trim, glow, size, extra):
    w, d, bh, lh = size
    base, lid = Builder(), Builder()
    base.box(body, (0, 0, bh / 2), (w, d, bh))
    base.box(trim, (0, 0, 0.03), (w + 0.04, d + 0.04, 0.06))                       # plinth
    for x in (-w * 0.3, w * 0.3):
        base.box(band, (x, 0, bh / 2), (0.08, d + 0.03, bh + 0.01))                  # bands
    if extra >= 1:
        for sx in (-1, 1):
            for sy in (-1, 1):
                base.box(trim, (sx * w / 2, sy * d / 2, bh / 2), (0.07, 0.07, bh + 0.02))   # corners
                for z in (0.12, bh - 0.08):
                    base.octa(trim, (sx * (w / 2 + 0.02), sy * 0.12, z), 0.02)
    base.box(trim, (0, -d / 2 - 0.02, bh - 0.08), (0.12, 0.04, 0.14))                # lock plate
    if glow:
        base.box(glow, (0, -d / 2 - 0.045, bh - 0.08), (0.05, 0.01, 0.06))
        base.box(glow, (0, 0, bh - 0.01), (w - 0.04, d - 0.04, 0.02))               # light spilling from the seam
    # lid built around the hinge (back top edge = origin), curved top as stepped slabs
    hy = d / 2
    steps = 4
    for i in range(steps):
        z = lh * math.sin(math.pi * (i + 0.5) / steps) * 0.55 + lh * 0.25
        lid.box(body, (0, -d * (i + 0.5) / steps, z * 0.5 + 0.02), (w, d / steps + 0.002, z + 0.04))
    lid.box(trim, (0, -d / 2, 0.02), (w + 0.03, d + 0.03, 0.04))                     # rim
    for x in (-w * 0.3, w * 0.3):
        lid.box(band, (x, -d / 2, lh * 0.45), (0.085, d + 0.035, lh * 0.95))
    lid.box(trim, (0, -d - 0.02, 0.06), (0.12, 0.04, 0.12))                         # latch
    if glow:
        lid.octa(glow, (0, -d - 0.04, lh * 0.55), 0.05 + 0.02 * (extra - 2))
    if extra >= 3:
        for sx in (-1, 0, 1):                                                      # crown ornaments
            lid.cone_tip("gold", K.ring_z(lh + 0.02, 0.035, 4, x=sx * w * 0.32, y=-d / 2), (sx * w * 0.32, -d / 2, lh + 0.16))
            lid.octa("g_gold", (sx * w * 0.32, -d / 2, lh + 0.18), 0.025)
    b_ob = base.build("Base", {body: 0.12})
    l_ob = lid.build("Lid", {body: 0.12})
    l_ob.location = (0, hy, bh)
    return [b_ob, l_ob]


groups = []
for name, spec in TIERS.items():
    obs = chest(*spec)
    K.export(obs, os.path.join(OUT, "chest_%s.glb" % name))
    groups.append(obs)
print("DONE chests")
K.preview(groups, os.path.join(TEX, "preview_chests.png"), cols=4)
