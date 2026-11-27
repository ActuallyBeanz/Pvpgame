# Brew vials (two plants mixed): round glowing flask, glass neck, cork, a twine wrap. Origin at
# the base, ~0.24 m tall. One per brew, liquid colour = the brew's element colour.
# Run: blender -b --factory-startup -P make_items_vials.py -- <tex_dir> <glb_dir>
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib, item_kit as K
importlib.reload(K)
from item_kit import Builder

ARGS = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT = ARGS[0], ARGS[1]
K.init(TEX)
K.std_mats()
BREWS = {
    "emberfog": (255, 115, 60), "muddlehaze": (180, 128, 240), "rimemist": (150, 228, 255),
    "stormdrop": (190, 215, 255), "chainspark": (255, 240, 120), "steamburst": (235, 235, 242),
    "sunburst": (255, 242, 180), "mendingdew": (115, 255, 150),
}


def vial(name, col):
    K.glow_mat("liq_" + name, col, 1.8)
    b = Builder()
    b.lathe("liq_" + name, [(0.0, 0.03), (0.03, 0.075), (0.08, 0.085), (0.13, 0.07), (0.16, 0.035)], 10)  # flask
    b.lathe("ice", [(0.15, 0.03), (0.2, 0.026), (0.21, 0.034)], 8)                                        # glass neck + lip
    b.lathe("wood", [(0.205, 0.024), (0.245, 0.02)], 8)                                                   # cork
    b.lathe("rope", [(0.155, 0.04), (0.17, 0.04)], 8)                                                     # twine
    b.lathe("ice", [(0.0, 0.035), (0.012, 0.04)], 10)                                                     # glass foot
    return [b.build("Body", {"wood": 0.05})]


groups = []
for name, col in BREWS.items():
    obs = vial(name, col)
    K.export(obs, os.path.join(OUT, "vial_" + name + ".glb"))
    groups.append(obs)
print("DONE vials")
K.preview(groups, os.path.join(TEX, "preview_vials.png"), cols=4)
