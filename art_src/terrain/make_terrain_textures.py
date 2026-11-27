# Pixel-art terrain tiles for Terrain3D (Megabonk look: chunky 64x64, 4-6 colour palettes).
#   <name>_albedo.png : RGB colour, A = height (for blending between layers)
#   <name>_normal.png : RGB normal (from the height), A = roughness
# Layer order = Terrain3D texture id = biome (systems/world/island_terrain3d.gd keeps the same list).
# Run: python3 art_src/terrain/make_terrain_textures.py assets/terrain/textures
import sys, os, math, random
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/terrain/textures"
os.makedirs(OUT, exist_ok=True)
N = 64


def vnoise(seed, cell):
    """Tileable value noise, 0..1, cell = pixels per lattice step."""
    r = random.Random(seed)
    g = N // cell
    lat = [[r.random() for _ in range(g)] for _ in range(g)]
    def f(x, y):
        fx, fy = x / cell, y / cell
        x0, y0 = int(fx) % g, int(fy) % g
        x1, y1 = (x0 + 1) % g, (y0 + 1) % g
        tx, ty = fx - int(fx), fy - int(fy)
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = lat[y0][x0] * (1 - tx) + lat[y0][x1] * tx
        b = lat[y1][x0] * (1 - tx) + lat[y1][x1] * tx
        return a * (1 - ty) + b * ty
    return f


def make(name, pal, seed, rough=0.9, extra=None, cells=(16, 8, 4), weights=(0.5, 0.3, 0.2), jitter=0.12):
    if name in ("rock", "basalt", "redrock"):
        cells, weights, jitter = (8, 4, 2), (0.45, 0.35, 0.2), 0.08
    r = random.Random(seed)
    ns = [vnoise(seed + i, c) for i, c in enumerate(cells)]
    hmap = [[0.0] * N for _ in range(N)]
    img = Image.new("RGBA", (N, N))
    for y in range(N):
        for x in range(N):
            v = sum(w * n(x, y) for w, n in zip(weights, ns)) + r.uniform(-jitter, jitter)
            v = min(0.999, max(0.0, v))
            h = v
            col = pal[min(len(pal) - 1, int(v * len(pal)))]
            if extra:
                res = extra(x, y, v, r)
                if res:
                    col, h = res
            hmap[y][x] = h
            img.putpixel((x, y), (*col, int(h * 255)))
    img.save(os.path.join(OUT, name + "_albedo.png"))
    nrm = Image.new("RGBA", (N, N))
    k = 2.5
    for y in range(N):
        for x in range(N):
            dx = (hmap[y][(x + 1) % N] - hmap[y][(x - 1) % N]) * k
            dy = (hmap[(y + 1) % N][x] - hmap[(y - 1) % N][x]) * k
            l = math.sqrt(dx * dx + dy * dy + 1.0)
            nx, ny, nz = -dx / l, dy / l, 1.0 / l
            nrm.putpixel((x, y), (int((nx * 0.5 + 0.5) * 255), int((ny * 0.5 + 0.5) * 255), int((nz * 0.5 + 0.5) * 255), int(rough * 255)))
    nrm.save(os.path.join(OUT, name + "_normal.png"))
    print("tex", name)


def sprinkle(chance, colors, hbonus=0.25):
    def f(x, y, v, r):
        if r.random() < chance:
            return r.choice(colors), min(1.0, max(0.0, v + hbonus))
    return f


def pavers(size, mortar, mortar_h=0.1):
    def f(x, y, v, r):
        ox = (size // 2) if (y // size) % 2 else 0
        if y % size == 0 or (x + ox) % size == 0:
            return mortar, mortar_h
    return f


def strata(band, colors):
    def f(x, y, v, r):
        i = ((y + int(v * 6)) // band) % len(colors)
        return colors[i], 0.3 + 0.4 * v
    return f


def columns(width, crack):
    def f(x, y, v, r):
        if x % width == 0 or (x % width == width // 2 and (y // 12) % 2 == 0 and y % 12 == 0):
            return crack, 0.05
    return f


def blocks(size, crack):
    def f(x, y, v, r):
        ox = (size // 2) if (y // (size // 2)) % 2 else 0
        if y % (size // 2) == 0 or (x + ox) % size == 0:
            return crack, 0.05
    return f


LAYERS = [
    # 0..11 = biomes (same order as BIOMES in island_terrain3d.gd), 12..14 = cliff rock
    ("grass", [(66, 140, 52), (82, 160, 60), (100, 178, 70), (122, 196, 84)], 11, 0.95,
     sprinkle(0.012, [(240, 230, 120), (250, 250, 240), (220, 120, 160)])),
    ("forest", [(44, 92, 40), (56, 110, 46), (70, 126, 52), (96, 84, 52)], 12, 0.95,
     sprinkle(0.03, [(120, 92, 56), (88, 70, 44)], 0.1)),
    ("snow", [(206, 216, 232), (222, 230, 242), (236, 242, 250), (248, 250, 255)], 13, 0.6,
     sprinkle(0.01, [(255, 255, 255)], 0.3)),
    ("ash", [(52, 44, 44), (64, 54, 52), (78, 66, 62), (92, 78, 72)], 14, 0.95,
     sprinkle(0.008, [(255, 120, 40), (230, 80, 30)], 0.0)),
    ("sand", [(214, 172, 102), (226, 186, 116), (236, 200, 132), (244, 214, 150)], 15, 0.95, None),
    ("beach", [(226, 204, 152), (236, 216, 166), (244, 228, 182), (250, 238, 200)], 16, 0.9,
     sprinkle(0.01, [(250, 250, 245), (210, 160, 150)], 0.2)),
    ("path", [(140, 106, 70), (156, 120, 80), (172, 136, 94), (188, 154, 110)], 17, 0.95,
     sprinkle(0.04, [(150, 146, 140), (120, 116, 112)], 0.3)),
    ("plaza", [(150, 146, 136), (164, 158, 148), (176, 170, 160)], 18, 0.85, pavers(16, (104, 98, 90))),
    ("bed", [(92, 86, 74), (108, 100, 86), (124, 116, 100), (140, 132, 116)], 19, 0.8,
     sprinkle(0.08, [(160, 156, 150), (90, 84, 78)], 0.3)),
    ("lava", [(36, 24, 22), (52, 32, 28), (70, 40, 32)], 20, 0.95,
     sprinkle(0.05, [(255, 110, 30), (255, 170, 60)], 0.0)),
    ("ice", [(150, 204, 236), (168, 218, 244), (190, 232, 250)], 21, 0.25,
     sprinkle(0.015, [(230, 248, 255)], 0.2)),
    ("mesa", [(196, 120, 72), (210, 138, 84), (222, 156, 98)], 22, 0.95,
     strata(6, [(192, 116, 70), (210, 140, 86), (180, 104, 62), (224, 160, 104)])),
    ("rock", [(92, 86, 80), (108, 102, 96), (124, 118, 110), (142, 136, 128), (160, 154, 146)], 23, 0.9,
     sprinkle(0.03, [(70, 66, 62)], -0.3)),
    ("basalt", [(40, 36, 38), (52, 46, 48), (64, 56, 58)], 24, 0.9, columns(10, (24, 20, 22))),
    ("redrock", [(160, 92, 56), (176, 104, 64), (190, 118, 74)], 25, 0.9,
     strata(5, [(158, 90, 54), (178, 106, 66), (146, 80, 48), (196, 126, 80)])),
]
for name, pal, seed, rough, extra in LAYERS:
    make(name, pal, seed, rough, extra)
print("DONE", len(LAYERS))
