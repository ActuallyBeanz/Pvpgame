extends Node3D
## Builds the island from two repaintable images (art_src/map/make_island_maps.py writes them):
##   heightmap.png  grey, height = h_min + value * h_step  (one pixel = one metre)
##   biome.png      paint colours (see PALETTE) -> terrain colour + what grows there
## Visual: flat-shaded low-poly chunks (mesh_step metres per quad), vertex coloured, steep faces
## turn to rock. Collision: one HeightMapShape3D at full 1 m resolution.
## World: x = column - (w-1)/2, z = row - (h-1)/2, so the map is centred on the origin.

@export_file("*.png") var heightmap_path := "res://assets/maps/island/heightmap.png"
@export_file("*.png") var biome_path := "res://assets/maps/island/biome.png"
@export var h_min := -8.0                  ## keep in sync with make_island_maps.py
@export var h_step := 0.25
@export var mesh_step := 2                 ## metres per visual quad (1 = finest, heavier)
@export var chunk_quads := 32              ## quads per chunk side (frustum culling granularity)
@export var cliff_angle_deg := 46.0        ## steeper faces are painted as rock
@export var color_jitter := 0.06

const PALETTE := {   # biome name -> paint colour in biome.png (must match the generator)
	"grass": Color8(96, 168, 70), "forest": Color8(64, 128, 52), "snow": Color8(232, 238, 248),
	"ash": Color8(78, 66, 64), "sand": Color8(226, 188, 118), "beach": Color8(238, 214, 160),
	"path": Color8(176, 140, 96), "plaza": Color8(168, 162, 150), "bed": Color8(104, 96, 82),
	"lava": Color8(255, 96, 24), "ice": Color8(176, 220, 245), "mesa": Color8(204, 140, 84),
}
const CLIFF := {     # rock colour for steep faces, by biome
	"snow": Color8(150, 156, 168), "ash": Color8(52, 44, 44), "sand": Color8(178, 112, 68),
	"mesa": Color8(166, 98, 58), "beach": Color8(150, 128, 100), "lava": Color8(60, 40, 36),
}
const ROCK := Color8(118, 110, 100)

var width := 0
var depth := 0
var heights := PackedFloat32Array()
var _biome: Image
var _ready_built := false


func _ready() -> void:
	build()


func build() -> void:
	if _ready_built:
		return
	var himg := _load_image(heightmap_path)
	_biome = _load_image(biome_path)
	if himg == null or _biome == null:
		push_error("IslandTerrain: missing map images")
		return
	himg.convert(Image.FORMAT_L8)
	_biome.convert(Image.FORMAT_RGB8)
	width = himg.get_width()
	depth = himg.get_height()
	heights.resize(width * depth)
	var raw := himg.get_data()
	for i in raw.size():
		heights[i] = h_min + float(raw[i]) * h_step
	_build_collision()
	_build_mesh()
	_ready_built = true
	print("[terrain] %dx%d built" % [width, depth])


static func _load_image(path: String) -> Image:
	var res: Resource = load(path) if ResourceLoader.exists(path) else null
	if res is Image:
		return (res as Image).duplicate()
	if res is Texture2D:
		return (res as Texture2D).get_image()
	return Image.load_from_file(path)


# ---------------------------------------------------------------- queries (any time after build)
func half_w() -> float:
	return (width - 1) * 0.5


func half_d() -> float:
	return (depth - 1) * 0.5


## Ground height at a world x/z (bilinear). Off the map = h_min.
func height_at(x: float, z: float) -> float:
	var fx := x + half_w()
	var fz := z + half_d()
	if fx < 0.0 or fz < 0.0 or fx > width - 1 or fz > depth - 1:
		return h_min
	var ix := mini(int(fx), width - 2)
	var iz := mini(int(fz), depth - 2)
	var tx := fx - ix
	var tz := fz - iz
	var a := heights[iz * width + ix]
	var b := heights[iz * width + ix + 1]
	var c := heights[(iz + 1) * width + ix]
	var d := heights[(iz + 1) * width + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## Biome name painted at a world x/z ("" off the map).
func biome_at(x: float, z: float) -> String:
	var ix := int(roundf(x + half_w()))
	var iz := int(roundf(z + half_d()))
	if ix < 0 or iz < 0 or ix >= width or iz >= depth:
		return ""
	return _nearest_biome(_biome.get_pixel(ix, iz))


## Steepness in degrees at a world x/z (from the 1 m heightfield).
func slope_deg(x: float, z: float) -> float:
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	return rad_to_deg(atan(Vector2(dx, dz).length() * 0.5))


func _nearest_biome(c: Color) -> String:
	var best := ""
	var bd := 1e9
	for k in PALETTE:
		var p: Color = PALETTE[k]
		var dd := (c.r - p.r) * (c.r - p.r) + (c.g - p.g) * (c.g - p.g) + (c.b - p.b) * (c.b - p.b)
		if dd < bd:
			bd = dd
			best = k
	return best


# ---------------------------------------------------------------- collision
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.set_meta("material", "stone")
	var shape := HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = depth
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# ---------------------------------------------------------------- visual mesh
func _build_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # safe either winding; terrain is never seen from below anyway
	var cos_cliff := cos(deg_to_rad(cliff_angle_deg))
	var step := maxi(1, mesh_step)
	var qx := (width - 1) / step
	var qz := (depth - 1) / step
	var hw := half_w()
	var hd := half_d()
	var cache := {}   # biome lookups are slow-ish: cache by colour
	for cz0 in range(0, qz, chunk_quads):
		for cx0 in range(0, qx, chunk_quads):
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			for qz_i in range(cz0, mini(cz0 + chunk_quads, qz)):
				for qx_i in range(cx0, mini(cx0 + chunk_quads, qx)):
					var ix := qx_i * step
					var iz := qz_i * step
					var p00 := Vector3(ix - hw, heights[iz * width + ix], iz - hd)
					var p10 := Vector3(ix + step - hw, heights[iz * width + ix + step], iz - hd)
					var p01 := Vector3(ix - hw, heights[(iz + step) * width + ix], iz + step - hd)
					var p11 := Vector3(ix + step - hw, heights[(iz + step) * width + ix + step], iz + step - hd)
					# alternate the diagonal so the low-poly facets don't all line up
					if (qx_i + qz_i) % 2 == 0:
						_tri(verts, norms, cols, p00, p10, p11, cos_cliff, cache)
						_tri(verts, norms, cols, p00, p11, p01, cos_cliff, cache)
					else:
						_tri(verts, norms, cols, p00, p10, p01, cos_cliff, cache)
						_tri(verts, norms, cols, p10, p11, p01, cos_cliff, cache)
			if verts.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx0, cz0]
			mi.mesh = mesh
			add_child(mi)


func _tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, cos_cliff: float, cache: Dictionary) -> void:
	var n := (c - a).cross(b - a).normalized()   # Godot is clockwise-front: a, b, c seen from above
	if n.y < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	var mid := (a + b + c) / 3.0
	var px := clampi(int(roundf(mid.x + half_w())), 0, width - 1)
	var pz := clampi(int(roundf(mid.z + half_d())), 0, depth - 1)
	var raw := _biome.get_pixel(px, pz)
	var key := raw.to_rgba32()
	var bname: String = cache.get(key, "")
	if bname == "":
		bname = _nearest_biome(raw)
		cache[key] = bname
	var col: Color = PALETTE[bname]
	if n.y < cos_cliff and bname != "lava" and bname != "ice":
		col = CLIFF.get(bname, ROCK)
	# deterministic per-face brightness jitter (low-poly sparkle)
	var hsh := absf(sin(mid.x * 12.9898 + mid.z * 78.233) * 43758.5453)
	col = col * (1.0 + (hsh - floorf(hsh) - 0.5) * 2.0 * color_jitter)
	col.a = 1.0
	for v in [a, b, c]:
		verts.append(v)
		norms.append(n)
		cols.append(col)
