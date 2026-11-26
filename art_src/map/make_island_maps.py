# Paints the island's heightmap + biome map from the Map.png layout (one pixel = one metre).
#   heightmap.png : 8-bit grey, height = H_MIN + value * H_STEP   (repaint it to reshape the land)
#   biome.png     : what each spot is painted with (colours = PALETTE below; Godot reads the same ones)
#   preview.png   : shaded top-down preview to eyeball the result
# World: x = column - 255.5 (east +), z = row - 255.5 (south +, north = top of the image), sea level y = 0.
# Run: python3 make_island_maps.py <out_dir>
import sys, os, math
import numpy as np
from PIL import Image

OUT = sys.argv[1]
N = 512
H_MIN, H_STEP = -8.0, 0.25          # keep in sync with island_terrain.gd
rng = np.random.default_rng(7)
xs = np.arange(N) - 255.5
X, Z = np.meshgrid(xs, xs)          # X[row, col], Z[row, col]

PALETTE = {
    "grass": (96, 168, 70), "forest": (64, 128, 52), "snow": (232, 238, 248), "ash": (78, 66, 64),
    "sand": (226, 188, 118), "beach": (238, 214, 160), "path": (176, 140, 96), "plaza": (168, 162, 150),
    "bed": (104, 96, 82), "lava": (255, 96, 24), "ice": (176, 220, 245), "mesa": (204, 140, 84),
}


# ------------------------------------------------------------------ noise helpers
def value_noise(scale, octaves=3, seed=0):
    r = np.random.default_rng(abs(int(seed)))
    out = np.zeros((N, N)); amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(N / scale * (2 ** o)))
        g = r.random((s + 1, s + 1))
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        out += amp * (np.asarray(img, float) / 255.0 - 0.5); tot += amp; amp *= 0.5
    return out / tot * 2.0          # about -1..1


def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def blur(a, r, passes=2):
    """Separable box blur (radius r, edge-clamped), run twice ~ gaussian."""
    a = a.astype(float)
    k = 2 * r + 1
    for _ in range(passes):
        for ax in (0, 1):
            p = np.pad(a, [(r, r) if i == ax else (0, 0) for i in range(2)], mode="edge")
            c = np.cumsum(p, axis=ax)
            c = np.insert(c, 0, 0, axis=ax)
            a = (np.take(c, range(k, k + a.shape[ax]), axis=ax) - np.take(c, range(0, a.shape[ax]), axis=ax)) / k
    return a


def dist_to_polyline(pts):
    d = np.full((N, N), 1e9)
    for (ax, az), (bx, bz) in zip(pts[:-1], pts[1:]):
        vx, vz = bx - ax, bz - az
        L2 = vx * vx + vz * vz
        t = np.clip(((X - ax) * vx + (Z - az) * vz) / L2, 0, 1)
        d = np.minimum(d, np.hypot(X - (ax + t * vx), Z - (az + t * vz)))
    return d


def polygon_mask(pts):
    from PIL import ImageDraw
    img = Image.new("L", (N, N), 0)
    ImageDraw.Draw(img).polygon([(x + 255.5, z + 255.5) for x, z in pts], fill=255)
    return np.asarray(img, float) / 255.0


def uv(u, v):  # Map.png pixel -> world metres (image is ~1277 x 1232)
    return ((u / 1277.0 - 0.5) * 500.0, (v / 1232.0 - 0.5) * 500.0)


# ------------------------------------------------------------------ island outline (traced off Map.png)
OUTLINE = [uv(*p) for p in [
    (60, 240), (150, 95), (300, 55), (450, 70), (560, 115), (690, 85), (790, 60), (860, 30), (1000, 20),
    (1120, 85), (1195, 185), (1190, 285), (1215, 410), (1232, 520), (1190, 600), (1235, 690), (1250, 805),
    (1240, 905), (1200, 985), (1100, 1055), (1000, 1140), (860, 1172), (720, 1150), (650, 1075), (560, 1115),
    (420, 1125), (330, 1060), (200, 1005), (85, 955), (40, 820), (58, 655), (48, 520), (78, 400), (55, 300)]]
TEST_ISLET = (-220.0, 222.0, 0.0, -9.0)   # radius 0 = off (test area moved back to the arena map)    # x, z, radius, top height: the item test area (keep in sync with island.gd)
ISLETS = [(uv(110, 120), 14), (uv(615, 45), 13), (uv(1135, 95), 16), (uv(1205, 290), 11), (uv(38, 360), 11),
          (uv(40, 510), 10), (uv(1232, 640), 12), (uv(62, 905), 12), (uv(308, 1150), 12),
          (uv(690, 1140), 11), (uv(1120, 1110), 16), (uv(1172, 1050), 9)]

land = blur(polygon_mask(OUTLINE), 6)
BAYS = [(uv(60, 580), 34), (uv(1240, 560), 38), (uv(560, 55), 22), (uv(215, 1120), 30), (uv(1235, 330), 26),
        (uv(820, 1170), 34)]
for (bx, bz), r in BAYS:
    land -= smooth(1.0 - np.hypot(X - bx, Z - bz) / r, 0.0, 0.3)
warp = value_noise(28, 3, 11)
land = smooth(land + warp * 0.38, 0.45, 0.55)
islet_h = np.zeros((N, N))
for (cx, cz), r in ISLETS:
    d = np.hypot(X - cx, Z - cz) / r + value_noise(12, 2, int(cx * 7 + cz)) * 0.25
    islet_h = np.maximum(islet_h, smooth(1.0 - d, 0.0, 0.25) * (r * 0.45))

# distance (m) from the coast inward, chamfer
inside = land > 0.5
dist = np.where(inside, 0.0, 0.0)
cur = inside.copy(); dcoast = np.zeros((N, N))
for i in range(40):
    sh = cur.copy()
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        sh &= np.roll(np.roll(cur, dx, 1), dz, 0)
    dcoast += cur
    cur = sh
# beach stretches (gentle slope) vs cliffs
BEACHES = [(uv(560, 1100), 70), (uv(980, 1110), 110), (uv(1180, 960), 60), (uv(640, 100), 40), (uv(1120, 760), 40),
           (uv(60, 700), 45), (uv(90, 420), 35), (uv(1215, 470), 40), (uv(380, 70), 35), (uv(260, 1060), 45), (uv(1180, 230), 30)]
beachy = np.zeros((N, N))
for (cx, cz), r in BEACHES:
    beachy = np.maximum(beachy, smooth(1.0 - np.hypot(X - cx, Z - cz) / r, 0.0, 0.4))

# ------------------------------------------------------------------ regions (nearest seed, warped)
REGIONS = {  # name: (seed x, z, base height, biome)
    "center": (0, -65, 10.0, "grass"), "snow": (-150, -165, 14.0, "snow"), "volcano": (135, -185, 12.0, "ash"),
    "forest_w": (-160, 20, 6.5, "forest"), "forest_sw": (-110, 160, 7.5, "forest"), "desert": (140, 120, 5.0, "sand"),
    "grass_e": (160, -45, 8.0, "grass"), "grass_s": (10, 120, 7.0, "grass"), "grass_n": (-10, -195, 9.0, "grass"),
}
names = list(REGIONS)
wx = X + value_noise(50, 2, 21) * 22
wz = Z + value_noise(50, 2, 22) * 22
dists = np.stack([np.hypot(wx - REGIONS[n][0], wz - REGIONS[n][1]) for n in names])
nearest = np.argmin(dists, 0)
base = np.zeros((N, N)); biome = np.empty((N, N), dtype=object)
for i, n in enumerate(names):
    base[nearest == i] = REGIONS[n][2]
    biome[nearest == i] = REGIONS[n][3]
base = blur(base, 3)                         # ~6 m wide slopes between region levels (cliff bands)
hills = value_noise(70, 2, 33) * smooth(np.asarray(base), 4.0, 6.0) * (1.0 - smooth(np.asarray(base), 11.0, 13.0))
h = base + value_noise(25, 3, 31) * 1.8 + np.maximum(hills, -0.3) * 7.0

# ------------------------------------------------------------------ landmarks
def bump(cx, cz, r, height, sharp=1.0, seed=0, ridges=0.0):
    d = np.hypot(X - cx, Z - cz) / r
    ang = np.arctan2(Z - cz, X - cx)
    rr = d * (1.0 + ridges * np.sin(ang * 7 + seed) * 0.12) + value_noise(18, 2, seed) * 0.08
    return np.clip(1.0 - rr, 0, 1) ** sharp * height

def plateau(cx, cz, r, top, edge=3.0, noise=0.0, seed=0, rx=None):
    rx = rx or r
    d = np.hypot((X - cx) / rx * r, Z - cz) + value_noise(15, 2, seed) * noise
    return smooth(r - d, 0, edge), top

def set_plateau(h, cx, cz, r, top, edge=3.0, noise=4.0, seed=0, rx=None, mode="max"):
    m, t = plateau(cx, cz, r, top, edge, noise, seed, rx)
    return np.maximum(h, h * (1 - m) + t * m) if mode == "max" else h * (1 - m) + t * m

# snow mountain + volcano
h += bump(-190, -205, 70, 32, 1.4, 41, 1.0)
volc = bump(150, -208, 80, 44, 1.2, 51, 0.8)
h += volc
crater = smooth(16 - np.hypot(X - 160, Z + 200), 0, 6)
h = h * (1 - crater) + (h.clip(max=46) - 7) * crater
# central plateau: ring terraces up to the fountain plaza
C = (0, -60)
h = set_plateau(h, *C, 66, 10.0, 2.5, 0, mode="set")
h = set_plateau(h, *C, 42, 12.0, 2.5, 0, mode="set")
h = set_plateau(h, *C, 20, 13.5, 1.5, 0, mode="set")
# Frosthollow keep hill, Emberfall fortress shelf, Sunscorch temple plateau, desert mesas
h = set_plateau(h, -160, -140, 26, 17.0, 3, 3, 61)
h = set_plateau(h, 120, -135, 30, 16.0, 3, 3, 62, rx=38)
h = set_plateau(h, 150, 95, 34, 8.0, 3, 3, 63, mode="set")
MESAS = [(85, 175, 14, 15.0), (205, 55, 12, 17.0), (205, 190, 16, 13.0), (55, 70, 10, 14.0), (235, 120, 9, 18.0)]
for i, (mx, mz, r, top) in enumerate(MESAS):
    h = set_plateau(h, mx, mz, r, top, 1.5, 3, 70 + i)
# Thornwood ruin circles (flat clearings)
h = set_plateau(h, -165, 15, 18, 6.5, 3, 2, 80, mode="set")
h = set_plateau(h, -150, 150, 22, 7.5, 3, 2, 81, mode="set")

# ------------------------------------------------------------------ water: moat + rivers (sea level 0)
RIVERS = {
    "n": [(0, -128), (6, -170), (-4, -215), (6, -260)],
    "w": [(-60, -95), (-120, -95), (-185, -88), (-262, -92)],
    "e": [(60, -95), (110, -88), (190, -92), (262, -80)],
    "s": [(0, 8), (-14, 70), (8, 150), (-6, 200), (4, 262)],
}
water_d = np.full((N, N), 1e9)
for pts in RIVERS.values():
    water_d = np.minimum(water_d, dist_to_polyline(pts) + value_noise(20, 2, 91) * 1.5)
ring = np.abs(np.hypot(X - C[0], Z - C[1]) - 74.0)
water_d = np.minimum(water_d, ring)
RIVER_HALF = 6.0
chan = smooth(RIVER_HALF + 4.0 - water_d, 0, 4.0)          # banks over 4 m
h = h * (1 - chan) + (-2.8) * chan
# escape ramps: sloped cuts from the water up to the bank top, every ~40 m, alternating banks
def ramp(px, pz, nx, nz, start, length=34.0, half_w=3.5, slope=0.42):
    global h
    u = (X - px) * -nz + (Z - pz) * nx          # along the river
    v = (X - px) * nx + (Z - pz) * nz           # away from the water
    inside = (np.abs(u) < half_w + 1.5) & (v > start - 2) & (v < start + length)
    edge = smooth(half_w + 1.5 - np.abs(u), 0, 1.5)
    target = -0.6 + np.clip(v - start, 0, None) * slope
    h = np.where(inside, h * (1 - edge) + np.minimum(h, target) * edge, h)

RAMP_EVERY = 40.0
for pts in RIVERS.values():
    k = 0
    for (ax, az), (bx, bz) in zip(pts[:-1], pts[1:]):
        L = math.hypot(bx - ax, bz - az); dx, dz = (bx - ax) / L, (bz - az) / L
        t = 18.0
        while t < L - 6:
            side = 1 if k % 2 == 0 else -1
            ramp(ax + dx * t, az + dz * t, -dz * side, dx * side, RIVER_HALF - 1.0)
            k += 1; t += RAMP_EVERY
for i in range(10):                              # moat: alternate outer bank / inner plateau
    a = (i + 0.25) / 10 * math.tau
    out = 1 if i % 2 == 0 else -1
    px, pz = C[0] + math.cos(a) * 74.0, C[1] + math.sin(a) * 74.0
    ramp(px, pz, math.cos(a) * out, math.sin(a) * out, RIVER_HALF - 1.0, length=36.0)

# ------------------------------------------------------------------ high lakes (own water level)
LAKES = [  # (x, z, radius, water level, kind)
    (-75, -150, 26, 13.0, "frozen"),
    (105, 140, 12, 6.0, "water"),            # Sunscorch oasis
    (-200, 90, 11, 5.0, "water"),            # Thornwood pond
]
for i, (lx, lz, r, lvl, kind) in enumerate(LAKES):
    d = np.hypot(X - lx, Z - lz) + value_noise(10, 2, 100 + i) * 3
    rim = smooth(r + 8 - d, 0, 8)
    h = h * (1 - rim) + np.maximum(h, lvl + 1.0) * rim       # level shore
    bowl = smooth(r - d, 0, 5)
    h = h * (1 - bowl) + (lvl - 2.5) * bowl

# ------------------------------------------------------------------ coast
coast_w = 7.0 + beachy * 26.0
f = smooth(dcoast, 0, coast_w)
shore_top = np.where(beachy > 0.3, 1.2, h)
h = np.where(dcoast > 0, h * f + np.minimum(shore_top, 1.2) * (1 - f) * (beachy) + h * (1 - f) * (1 - beachy) * smooth(dcoast, 0, 1.5), -7.0)
h = np.maximum(h, np.where(islet_h > 0, islet_h - 1.5 + value_noise(8, 2, 120) * 0.6, -7.0))
h = np.where((land < 0.5) & (islet_h <= 0.2), -7.0 + value_noise(30, 2, 130) * 1.5, h)
tx_, tz_, tr_, tt_ = TEST_ISLET
td = np.hypot(X - tx_, Z - tz_)
test_m = smooth(tr_ + 10 - td, 0, 12)            # flat top with a beach all round
h = np.maximum(h, h * (1 - test_m) + (tt_ * smooth(tr_ + 2 - td, 0, 6) + (-1.0) * (1 - smooth(tr_ + 2 - td, 0, 6))) * test_m)

# ------------------------------------------------------------------ paths (flatten a little, paint dirt)
PATHS = [
    [(0, -60), (25, 0), (30, 60), (40, 140), (60, 160), (140, 120)],               # plaza -> south -> temple
    [(0, -60), (-55, -110), (-110, -120), (-160, -140)],                            # -> keep
    [(0, -60), (55, -110), (100, -125), (120, -135)],                               # -> fortress
    [(0, -60), (-60, -30), (-120, -10), (-165, 15), (-170, 80), (-150, 150)],      # -> ruin circles
    [(0, -60), (60, -30), (120, -40), (180, -20), (200, 40)],                       # -> east grass -> desert
    [(0, -60), (-22, -140), (-28, -200)],                                           # -> north shore
    [(-150, 150), (-60, 190), (40, 140)],                                           # forest loop
    [(150, 95), (110, 200), (60, 230)],                                             # temple -> oasis -> beach
    [(-160, -140), (-90, -175), (-5, -200), (60, -175), (120, -135)],              # north ring
]
path_d = np.full((N, N), 1e9)
for pts in PATHS:
    path_d = np.minimum(path_d, dist_to_polyline(pts))
on_path = path_d < 2.5

# ------------------------------------------------------------------ biome paint
b = biome.copy()
slope = np.hypot(*np.gradient(h))
b[(h < 2.2) & (beachy > 0.2) & (h > -1)] = "beach"
b[(np.asarray(b == "sand")) & (h < 2.0)] = "beach"
for i, (mx, mz, r, top) in enumerate(MESAS):
    b[np.hypot(X - mx, Z - mz) < r + 2] = "mesa"
b[np.hypot(X - C[0], Z - C[1]) < 44] = "plaza"
b[(h > 30) & (np.asarray(biome == "snow") | (np.hypot(X + 190, Z + 205) < 70))] = "snow"
b[on_path & (h > 0.5)] = "path"
b[h < -0.5] = "bed"
b[crater > 0.6] = "lava"
for (lx, lz, r, lvl, kind) in LAKES:
    if kind == "frozen":
        b[(np.hypot(X - lx, Z - lz) < r) & (h < lvl)] = "ice"
for (cx, cz), r in ISLETS:
    sel = (np.hypot(X - cx, Z - cz) < r) & (h > 0.5) & (b != "bed")
    b[sel] = "grass"
b[(td < tr_ + 4) & (h > 2.0)] = "grass"
b[(td < tr_ + 12) & (h <= 2.0) & (h > -0.5)] = "beach"

# ------------------------------------------------------------------ write
hq = np.clip(np.round((h - H_MIN) / H_STEP), 0, 255).astype(np.uint8)
Image.fromarray(hq, "L").save(os.path.join(OUT, "heightmap.png"))
rgb = np.zeros((N, N, 3), np.uint8)
for k, c in PALETTE.items():
    rgb[b == k] = c
Image.fromarray(rgb, "RGB").save(os.path.join(OUT, "biome.png"))
# preview: hillshade x biome colour, water tinted
hh = H_MIN + hq * H_STEP
gx, gz = np.gradient(hh)
shade = np.clip(0.75 + (-gx * 0.6 - gz * 0.8) * 0.35, 0.35, 1.25)
prev = rgb.astype(float) * shade[..., None]
sea = hh < 0
prev[sea] = prev[sea] * 0.35 + np.array([40, 110, 170]) * 0.65
for (lx, lz, r, lvl, kind) in LAKES:
    m = (np.hypot(X - lx, Z - lz) < r + 6) & (hh < lvl)
    prev[m] = prev[m] * 0.3 + np.array([180, 225, 250] if kind == "frozen" else [50, 140, 200]) * 0.7
Image.fromarray(np.clip(prev, 0, 255).astype(np.uint8)).resize((1024, 1024), Image.NEAREST).save(os.path.join(OUT, "preview.png"))
print("height range %.1f .. %.1f m, land %.0f%%" % (hh.min(), hh.max(), (hh > 0).mean() * 100))
