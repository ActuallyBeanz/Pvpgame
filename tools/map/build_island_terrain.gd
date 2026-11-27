extends Node
## ONE-TIME CONVERTER (re-runnable): builds the island as a Terrain3D terrain from the old PNGs
##   assets/maps/island/heightmap.png + biome.png  ->  assets/terrain/island/ (Terrain3D data)
##   + assets/terrain/island_material.tres, island_assets.tres, scenes/world/island_terrain3d.tscn
## After this, edit the terrain IN GODOT (Terrain3D toolbar: sculpt / paint / foliage). Running
## this again OVERWRITES those edits - only re-run on purpose.
## Run (from the project folder):
##   Godot_console.exe --headless --path . res://tools/map/build_island_terrain.tscn

const HEIGHTMAP := "res://assets/maps/island/heightmap.png"
const BIOMEMAP := "res://assets/maps/island/biome.png"
const DATA_DIR := "res://assets/terrain/island"
const TEX_DIR := "res://assets/terrain/textures/"
const TerrainQuery := preload("res://systems/world/island_terrain3d.gd")

@export var h_min := -8.0
@export var h_step := 0.25
@export var detail_height := 0.45          ## small noise added on land (breaks flat areas up)
@export var uv_scale := 0.25               ## texture repeats per metre (64 px tile = 4 m)


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var himg := Image.load_from_file(ProjectSettings.globalize_path(HEIGHTMAP))
	var bimg := Image.load_from_file(ProjectSettings.globalize_path(BIOMEMAP))
	var w := himg.get_width()
	var d := himg.get_height()
	# heights: PNG steps -> metres, blur the 0.25 m terraces away, add a little detail on land
	var raw := PackedFloat32Array()
	raw.resize(w * d)
	for z in d:
		for x in w:
			raw[z * w + x] = h_min + himg.get_pixel(x, z).r * 255.0 * h_step
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var img := Image.create_empty(w, d, false, Image.FORMAT_RF)
	for z in d:
		for x in w:
			var s := 0.0
			var n := 0
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					var xx := clampi(x + ox, 0, w - 1)
					var zz := clampi(z + oz, 0, d - 1)
					s += raw[zz * w + xx]
					n += 1
			var h := s / n
			if h > 0.6:
				h += noise.get_noise_2d(x, z) * detail_height * clampf((h - 0.6) / 2.0, 0.0, 1.0)
			img.set_pixel(x, z, Color(h, 0, 0, 1))
	# the terrain
	var t: Node = ClassDB.instantiate("Terrain3D")
	t.name = "Terrain3D"
	add_child(t)
	t.region_size = 256
	t.collision_mode = 3                                  # FULL_GAME: everything collides (projectiles far away too)
	t.material.world_background = 0                       # NONE: the sea covers the edge
	t.material.texture_filtering = 3                      # NEAREST: pixel-art look
	t.material.auto_shader_enabled = false
	t.material.set_shader_param("flat_terrain_normals", true)   # faceted low-poly shading (Megabonk)
	for i in TerrainQuery.LAYERS.size():
		t.assets.set_texture_asset(i, _texture_asset(TerrainQuery.LAYERS[i], i))
	t.data.import_images([img, null, null], Vector3(-w * 0.5, 0, -d * 0.5), 0.0, 1.0)
	print("[build] heights imported (%d ms)" % (Time.get_ticks_msec() - t0))
	# paint: biome texture as base, its cliff rock as overlay blended in by slope
	for z in d:
		for x in w:
			var p := Vector3(x - w * 0.5, 0, z - d * 0.5)
			var biome := TerrainQuery.nearest_biome(bimg.get_pixel(x, z))
			var base: int = TerrainQuery.BIOMES.find(biome)
			var cliff: int = TerrainQuery.LAYERS.find(TerrainQuery.CLIFF_OF.get(biome, "rock"))
			var hx := _h(img, x + 1, z) - _h(img, x - 1, z)
			var hz := _h(img, x, z + 1) - _h(img, x, z - 1)
			var slope := rad_to_deg(atan(Vector2(hx, hz).length() * 0.5))
			t.data.set_control_base_id(p, maxi(base, 0))
			t.data.set_control_overlay_id(p, cliff)
			t.data.set_control_blend(p, smoothstep(30.0, 46.0, slope))
	t.data.update_maps()
	print("[build] painted (%d ms)" % (Time.get_ticks_msec() - t0))
	# save: data, material, assets, then a scene you can instance / edit
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	print("[build] saving data")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	t.data.save_directory(DATA_DIR)
	ResourceSaver.save(t.material, "res://assets/terrain/island_material.tres")
	ResourceSaver.save(t.assets, "res://assets/terrain/island_assets.tres")
	var regions: int = t.data.get_region_count()
	# the scene: a fresh (not yet loaded) Terrain3D that just points at the saved files
	var out: Node = ClassDB.instantiate("Terrain3D")
	out.name = "Terrain3D"
	out.region_size = 256
	out.collision_mode = 3
	out.data_directory = DATA_DIR
	out.material = load("res://assets/terrain/island_material.tres")
	out.assets = load("res://assets/terrain/island_assets.tres")
	var ps := PackedScene.new()
	ps.pack(out)
	ResourceSaver.save(ps, "res://scenes/world/island_terrain3d.tscn")
	out.free()
	print("[build] DONE in %d ms: %d regions" % [Time.get_ticks_msec() - t0, regions])
	get_tree().quit()


func _h(img: Image, x: int, z: int) -> float:
	return img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(z, 0, img.get_height() - 1)).r


func _texture_asset(layer: String, id: int) -> Resource:
	var a: Resource = ClassDB.instantiate("Terrain3DTextureAsset")
	a.name = layer.capitalize()
	a.albedo_texture = _tex(TEX_DIR + layer + "_albedo.png")
	a.normal_texture = _tex(TEX_DIR + layer + "_normal.png")
	a.uv_scale = uv_scale
	a.normal_depth = 0.6
	a.detiling_rotation = 0.0
	a.detiling_shift = 0.0
	return a


## The imported PNG (lossless + mipmaps, see its .import) so the assets file links to it:
## edit the PNG (or re-run art_src/terrain/make_terrain_textures.py) and the terrain updates.
func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D
