extends Node3D
## The battle-royale island (M3a greybox). Terrain comes from the repaintable maps in
## assets/maps/island (see art_src/map/make_island_maps.py); this script adds water, the
## landmarks, bridges, cover, trees, rocks, the 12 spawn points and loot.
## Everything is placed deterministically (fixed seeds + names) so every peer builds the
## same world; Reactive props / pickups sync by node path.
## Layout numbers mirror the generator: change both together.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PickupScene := preload("res://scenes/items/pickup.tscn")

@export_group("Layout (world metres, x east / z south)")
@export var center := Vector2(0, -60)                 ## Wellspring Ring plaza
@export var keep_pos := Vector2(-160, -140)           ## Frosthollow keep
@export var fortress_pos := Vector2(120, -135)        ## Emberfall fortress
@export var temple_pos := Vector2(150, 95)            ## Sunscorch temple
@export var ruin_circles: Array[Vector3] = [Vector3(-165, 15, 12), Vector3(-150, 150, 14)]  ## x, z, radius
@export var crater := Vector2(160, -200)              ## volcano lava pool
@export var crater_radius := 13.0
## x, z, radius, water level, kind ("water" / "frozen")
@export var lakes: Array[Vector4] = [Vector4(-75, -150, 26, 13.0), Vector4(105, 140, 12, 6.0), Vector4(-200, 90, 11, 5.0)]
@export var lake_kinds: PackedStringArray = ["frozen", "water", "water"]
## Path polylines (same as the generator): bridges, cover and loot follow them.
var paths: Array = [
	[Vector2(0, -60), Vector2(25, 0), Vector2(30, 60), Vector2(40, 140), Vector2(60, 160), Vector2(140, 120)],
	[Vector2(0, -60), Vector2(-55, -110), Vector2(-110, -120), Vector2(-160, -140)],
	[Vector2(0, -60), Vector2(55, -110), Vector2(100, -125), Vector2(120, -135)],
	[Vector2(0, -60), Vector2(-60, -30), Vector2(-120, -10), Vector2(-165, 15), Vector2(-170, 80), Vector2(-150, 150)],
	[Vector2(0, -60), Vector2(60, -30), Vector2(120, -40), Vector2(180, -20), Vector2(200, 40)],
	[Vector2(0, -60), Vector2(-22, -140), Vector2(-28, -200)],
	[Vector2(-150, 150), Vector2(-60, 190), Vector2(40, 140)],
	[Vector2(150, 95), Vector2(110, 200), Vector2(60, 230)],
	[Vector2(-160, -140), Vector2(-90, -175), Vector2(-5, -200), Vector2(60, -175), Vector2(120, -135)],
]

@export_group("Structures")
## Greybox landmark buildings are off while their real models are made. Their spots stay
## reserved (no trees/cover/spawns) so the models drop straight in later.
@export var build_landmarks := false

@export_group("Test islet (every item + targets, like the old test arena)")
@export var test_islet := Vector3(-220, 222, 30)        ## x, z, radius (generator TEST_ISLET)
@export var build_test_islet := false                   ## the test area lives in "Host Test Arena" now
@export var spawn_on_test_islet := false                ## dev: everyone starts on the test islet

@export_group("Spawns")
@export var spawn_count := 12
@export var spawn_min_spacing := 100.0
@export var spawn_seed := 5

@export_group("Scatter")
@export var tree_id := "env.tree.oak_a"
@export var rock_id := "env.rock.basic"
@export var max_trees := 520
@export var max_rocks := 140
@export var cover_every := 11.0               ## metres between cover pieces along paths
@export var scatter_seed := 42

@export_group("Loot (until chests exist)")
@export var loot_every := 28.0                ## metres between ground loot along paths
@export var loot_seed := 1234
## rarity tier -> items. Rarer tiers show up more toward the centre and at landmarks.
@export var loot_tiers: Dictionary = {
	"common": ["slingstones", "arrows", "slingstones", "arrows"],   # herbs / food / ore grow in the world instead (forage_sets)
	"uncommon": ["slingshot_thornfork", "sword_dawnsteel", "bow_basic", "boomerang_basic", "shield_gildcrest", "ironvein_ore"],
	"rare": ["greatsword_emberfang", "maul_quakeheart", "grappleclaw", "bomb_blastgourd", "trap_snapjaw",
		"fan_galeleaf", "staff_sandspire", "rod_rimecaller"],
	"legendary": ["skytether", "starsilver_ore"],
}
@export var tier_weights := Vector4(70, 26, 4, 0)      ## loose ground loot: common, uncommon, rare, legendary (edge of map)
@export var tier_weights_center := Vector4(45, 40, 15, 0)

@onready var terrain: Node3D = $Terrain
@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var overview_camera: Camera3D = $OverviewCamera

var spawn_points: Array[Vector3] = []
var _landmark_zones: Array[Vector3] = []        ## x, z, radius: keep scatter out
var _props: Node3D
var _mats := {}


func _ready() -> void:
	terrain.build()
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_make_mats()
	_build_water()
	_build_landmarks()
	_build_bridges()
	_place_cover()
	_place_trees_and_rocks()
	_pick_spawns()
	_place_loot()
	spawner.spawn_function = _build_player
	overview_camera.look_at_from_position(Vector3(0, 260, 260), Vector3(0, 0, -20))
	if multiplayer.is_server():
		Lobby.all_peers_loaded.connect(_spawn_all_players, CONNECT_ONE_SHOT)
		NetworkManager.peer_disconnected.connect(_on_peer_left)
	Lobby.report_match_loaded()
	Audio.play_ambience("amb.field")
	Audio.play("ui.match_start")
	tree_exiting.connect(func() -> void:
		Audio.stop_ambience(0.3)
		Water.clear())


func ground(x: float, z: float) -> float:
	return terrain.height_at(x, z)


# ---------------------------------------------------------------- players (same flow as the test arena)
func _spawn_all_players() -> void:
	var ids := Lobby.players.keys()
	ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		var entry: Dictionary = Lobby.players[id]
		var pos: Vector3 = spawn_points[i % spawn_points.size()] if not spawn_points.is_empty() else Vector3(0, 20, 0)
		if spawn_on_test_islet:
			var a := TAU * i / maxf(1.0, ids.size())
			var p2 := Vector2(test_islet.x, test_islet.y) + Vector2(cos(a), sin(a)) * 4.0 + Vector2(0, 8)
			pos = Vector3(p2.x, ground(p2.x, p2.y) + 0.6, p2.y)
		spawner.spawn({ "id": id, "pos": pos, "name": entry.name, "color": entry.color,
			"model": str(entry.get("model", "")) })


func _build_player(data: Variant) -> Node:
	var d: Dictionary = data
	var p := PLAYER_SCENE.instantiate()
	p.name = str(d.id)
	p.position = d.pos
	p.spawn_point = d.pos
	p.display_name = d.name
	p.color_index = d.color
	if str(d.get("model", "")) != "":
		p.model_id = d.model
	return p


func _on_peer_left(id: int) -> void:
	var n := players_root.get_node_or_null(str(id))
	if n:
		n.queue_free()


# ---------------------------------------------------------------- materials
func _make_mats() -> void:
	var base := { "stone": Color(0.72, 0.7, 0.64), "darkstone": Color(0.3, 0.27, 0.27), "sandstone": Color(0.86, 0.68, 0.45),
			"wood": Color(0.48, 0.32, 0.2), "icestone": Color(0.78, 0.84, 0.9), "mossstone": Color(0.5, 0.56, 0.44),
			"basalt": Color(0.2, 0.18, 0.19) }
	for k in base:
		var m := StandardMaterial3D.new()
		m.albedo_color = base[k]
		m.roughness = 0.92
		_mats[k] = m
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.4, 0.8, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.35, 0.75, 1.0)
	glow.emission_energy_multiplier = 3.0
	_mats["crystal"] = glow
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.55, 0.45, 0.75)
	accent.emission_enabled = true
	accent.emission = Color(0.5, 0.35, 1.0)
	accent.emission_energy_multiplier = 0.4
	_mats["accent"] = accent
	var lava := StandardMaterial3D.new()
	lava.albedo_color = Color(1.0, 0.4, 0.08)
	lava.emission_enabled = true
	lava.emission = Color(1.0, 0.35, 0.05)
	lava.emission_energy_multiplier = 2.5
	_mats["lava"] = lava
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.75, 0.9, 1.0, 0.85)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.roughness = 0.1
	ice.metallic = 0.2
	_mats["ice"] = ice


# ---------------------------------------------------------------- building blocks
## Solid greybox box. `at` = centre of the bottom face.
func _block(parent: Node, at: Vector3, size: Vector3, mat: String, rot_y := 0.0, mat_meta := "stone") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("material", mat_meta)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mats[mat]
	mi.position.y = size.y * 0.5
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	parent.add_child(body)
	body.position = at
	body.rotation.y = rot_y
	return body


func _column(parent: Node, at: Vector3, r: float, h: float, mat: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("material", "stone")
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.85
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = _mats[mat]
	mi.position.y = h * 0.5
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position.y = h * 0.5
	body.add_child(cs)
	parent.add_child(body)
	body.position = at
	return body


func _group(n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	add_child(g)
	return g


func _on_ground(x: float, z: float, sink := 0.3) -> Vector3:
	return Vector3(x, ground(x, z) - sink, z)


## Ring of wall segments around (cx, cz), skipping the given gap angles (radians).
func _wall_ring(parent: Node, c: Vector2, r: float, seg: int, h: float, mat: String, gaps: Array = [], broken := 0.0, rseed := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rseed
	for i in seg:
		var a := TAU * (i + 0.5) / seg
		var skip := false
		for g in gaps:
			if absf(wrapf(a - float(g), -PI, PI)) < PI / seg * 1.2:
				skip = true
		if skip:
			continue
		var hh := h * (1.0 - rng.randf() * broken)
		var p := c + Vector2(cos(a), sin(a)) * r
		var seg_len := TAU * r / seg * 1.02
		_block(parent, _on_ground(p.x, p.y, 0.5), Vector3(seg_len, hh + 0.5, 1.2), mat, -a + PI * 0.5)


# ---------------------------------------------------------------- water, lava, ice
func _build_water() -> void:
	Water.clear()
	Water.sea_level = 0.0
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://assets/shaders/water.gdshader")
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	pm.subdivide_width = 80
	pm.subdivide_depth = 80
	sea.mesh = pm
	sea.material_override = water_mat
	add_child(sea)
	for i in lakes.size():
		var l: Vector4 = lakes[i]
		var kind: String = lake_kinds[i] if i < lake_kinds.size() else "water"
		Water.add_body(Vector2(l.x, l.y), l.z, l.w, kind)
		if kind == "frozen":
			# walkable ice sheet (melting comes with the element pass)
			var ice := _block(self, Vector3(l.x, l.w - 0.6, l.y), Vector3(l.z * 2.0, 0.6, l.z * 2.0), "ice", 0.0, "ice")
			ice.name = "FrozenLake_%d" % i
		else:
			var mi := MeshInstance3D.new()
			mi.name = "Lake_%d" % i
			var lp := PlaneMesh.new()
			lp.size = Vector2(l.z * 2.4, l.z * 2.4)
			lp.subdivide_width = 12
			lp.subdivide_depth = 12
			mi.mesh = lp
			mi.material_override = water_mat
			mi.position = Vector3(l.x, l.w, l.y)
			add_child(mi)
	# volcano lava pool: glowing plane, a light, and a fire zone (arrows flying over it light up)
	var floor_y := ground(crater.x, crater.y)
	var lava_y := floor_y + 0.8
	Water.add_body(crater, crater_radius, lava_y, "lava")
	var lava := MeshInstance3D.new()
	lava.name = "Lava"
	var lm := PlaneMesh.new()
	lm.size = Vector2(crater_radius * 2.4, crater_radius * 2.4)
	lava.mesh = lm
	lava.material_override = _mats["lava"]
	lava.position = Vector3(crater.x, lava_y, crater.y)
	add_child(lava)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.15)
	light.light_energy = 4.0
	light.omni_range = 40.0
	light.position = Vector3(crater.x, lava_y + 6.0, crater.y)
	add_child(light)
	var fz := Area3D.new()
	fz.name = "LavaFireZone"
	fz.collision_layer = WorldRules.FIRE_ZONE_LAYER
	fz.collision_mask = 0
	fz.monitoring = false
	fz.set_meta("fire_zone", true)
	var fcs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(crater_radius * 1.8, 4.0, crater_radius * 1.8)
	fcs.shape = box
	fz.add_child(fcs)
	add_child(fz)
	fz.position = Vector3(crater.x, lava_y + 1.5, crater.y)


# ---------------------------------------------------------------- landmarks (greybox)
func _build_landmarks() -> void:
	if build_test_islet:
		_landmark_zones.append(Vector3(test_islet.x, test_islet.y, test_islet.z + 4))
		_build_test_islet()
	if not build_landmarks:
		for z in [Vector3(center.x, center.y, 46), Vector3(keep_pos.x, keep_pos.y, 26), Vector3(fortress_pos.x, fortress_pos.y, 28),
				Vector3(temple_pos.x, temple_pos.y, 30)]:
			_landmark_zones.append(z)
		for rc in ruin_circles:
			_landmark_zones.append(Vector3(rc.x, rc.y, rc.z + 4))
		return
	_build_wellspring()
	_build_keep()
	_build_fortress()
	_build_temple()
	for i in ruin_circles.size():
		_build_ruin_circle(i, ruin_circles[i])


func _build_wellspring() -> void:
	var g := _group("Wellspring")
	var c := center
	var top := ground(c.x, c.y)
	_landmark_zones.append(Vector3(c.x, c.y, 46))
	# fountain: basin ring, pool, pillar, glowing crystal
	for i in 12:
		var a := TAU * i / 12.0
		var p := c + Vector2(cos(a), sin(a)) * 6.0
		_block(g, Vector3(p.x, top - 0.2, p.y), Vector3(3.3, 1.1, 0.8), "stone", -a + PI * 0.5)
	var pool := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(11, 11)
	pool.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://assets/shaders/water.gdshader")
	pool.material_override = wm
	pool.position = Vector3(c.x, top + 0.6, c.y)
	g.add_child(pool)
	_column(g, Vector3(c.x, top - 0.2, c.y), 1.2, 5.0, "stone")
	var cr := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(1.4, 2.6, 1.4)
	cr.mesh = prism
	cr.material_override = _mats["crystal"]
	cr.position = Vector3(c.x, top + 6.2, c.y)
	g.add_child(cr)
	var l := OmniLight3D.new()
	l.light_color = Color(0.45, 0.8, 1.0)
	l.light_energy = 3.0
	l.omni_range = 22.0
	l.position = Vector3(c.x, top + 6.5, c.y)
	g.add_child(l)
	# ring of columns on the middle terrace + arches toward the bridges
	for i in 10:
		var a := TAU * (i + 0.5) / 10.0
		var p := c + Vector2(cos(a), sin(a)) * 31.0
		_column(g, _on_ground(p.x, p.y), 0.9, 6.0, "stone")
	# low broken outer wall on the plateau edge (cover)
	_wall_ring(g, c, 58.0, 28, 1.4, "mossstone", [PI * 0.5, -PI * 0.5, PI, 0.0, -2.2, -0.95], 0.6, 3)


func _build_keep() -> void:
	var g := _group("FrosthollowKeep")
	var c := keep_pos
	_landmark_zones.append(Vector3(c.x, c.y, 26))
	var y := ground(c.x, c.y)
	var half := 12.0
	for side in 4:
		var dir := Vector2.RIGHT.rotated(side * PI * 0.5)
		var nrm := dir.orthogonal()
		for k in 5:
			if side == 2 and k == 2:
				continue                                   # gate (faces the plaza road)
			if (side + k) % 4 == 3:
				continue                                   # collapsed bits
			var p := c + nrm * half + dir * (-half + 2.4 + k * 4.8)
			_block(g, Vector3(p.x, ground(p.x, p.y) - 0.5, p.y), Vector3(4.8, 6.5 - (k % 2) * 1.5, 1.4), "icestone", -dir.angle())
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var p := c + Vector2(sx, sz) * half
			_block(g, Vector3(p.x, ground(p.x, p.y) - 0.5, p.y), Vector3(4, 11 + (sx + sz) * 1.5, 4), "icestone")
	_block(g, Vector3(c.x, y - 0.3, c.y + 2), Vector3(9, 4.5, 7), "icestone")       # great hall stump
	_block(g, Vector3(c.x, y + 4.2, c.y + 2), Vector3(10, 0.5, 8), "wood", 0.0, "wood")   # roof deck (climb up)


func _build_fortress() -> void:
	var g := _group("EmberfallFortress")
	var c := fortress_pos
	_landmark_zones.append(Vector3(c.x, c.y, 28))
	var hx := 17.0
	var hz := 12.0
	for side in 4:
		var along_x := side % 2 == 0
		var length := hx * 2.0 if along_x else hz * 2.0
		var n := int(length / 5.0)
		for k in n:
			var t := -length * 0.5 + 2.5 + k * 5.0
			var p: Vector2
			if along_x:
				p = c + Vector2(t, hz if side == 0 else -hz)
			else:
				p = c + Vector2(hx if side == 1 else -hx, t)
			if side == 0 and absf(t) < 3.0:
				continue                                   # south gate
			_block(g, Vector3(p.x, ground(p.x, p.y) - 0.5, p.y), Vector3(5.0, 8.0, 1.6) if along_x else Vector3(1.6, 8.0, 5.0), "basalt")
	for sx in [-1, 1]:
		var p := c + Vector2(sx * hx, hz)
		_block(g, Vector3(p.x, ground(p.x, p.y) - 0.5, p.y), Vector3(5, 14, 5), "darkstone")
	_block(g, Vector3(c.x, ground(c.x, c.y) - 0.5, c.y - 4), Vector3(12, 9, 8), "darkstone")    # keep
	_block(g, Vector3(c.x, ground(c.x, c.y) + 8.5, c.y - 4), Vector3(13, 0.6, 9), "basalt")


func _build_temple() -> void:
	var g := _group("SunscorchTemple")
	var c := temple_pos
	_landmark_zones.append(Vector3(c.x, c.y, 30))
	var y := ground(c.x, c.y) - 0.5
	var sizes := [24.0, 17.0, 10.0]
	for i in sizes.size():
		var s: float = sizes[i]
		_block(g, Vector3(c.x, y + i * 3.0, c.y), Vector3(s, 3.5, s), "sandstone")
	# stairs up the south face
	for k in 9:
		_block(g, Vector3(c.x, y, c.y + 12.0 + 2.6 - k * 1.0), Vector3(4, 1.0 * (k + 1), 1.0), "sandstone")
	_block(g, Vector3(c.x, y + 9.0, c.y), Vector3(5, 3.0, 5), "stone")               # shrine
	for i in 10:
		var a := TAU * (i + 0.5) / 10.0
		var p := c + Vector2(cos(a), sin(a)) * 18.5
		_column(g, _on_ground(p.x, p.y), 0.8, 5.5 if i % 3 else 3.0, "sandstone")


func _build_ruin_circle(i: int, rc: Vector3) -> void:
	var g := _group("ThornwoodRuin_%d" % i)
	var c := Vector2(rc.x, rc.y)
	_landmark_zones.append(Vector3(c.x, c.y, rc.z + 4))
	var n := 10
	for k in n:
		var a := TAU * k / n
		var p := c + Vector2(cos(a), sin(a)) * rc.z
		if k % 4 == 3:
			continue                                       # fallen stones
		_block(g, _on_ground(p.x, p.y, 0.4), Vector3(1.6, 4.5, 1.1), "mossstone", -a + PI * 0.5)
		if k % 2 == 0 and (k + 1) % 4 != 3:
			var q := c + Vector2(cos(a + TAU / n * 0.5), sin(a + TAU / n * 0.5)) * rc.z
			_block(g, Vector3(q.x, ground(q.x, q.y) + 4.0, q.y), Vector3(rc.z * TAU / n + 1.2, 0.8, 1.1), "mossstone", -(a + TAU / n * 0.5) + PI * 0.5)
	_block(g, _on_ground(c.x, c.y, 0.2), Vector3(3, 1.1, 2), "stone")                  # altar


# ---------------------------------------------------------------- test islet
## The old test arena on an islet: an infinite stand for every item, training dummies, a torch
## and a brazier, respawning ice, archery targets and a grapple pillar with a dummy on top.
func _build_test_islet() -> void:
	var g := _group("TestIslet")
	var c := Vector2(test_islet.x, test_islet.y)
	var root := Node3D.new()
	root.name = "TestPickups"
	add_child(root)
	var ids: Array = ItemDB.all_ids()
	var cols := 8
	for i in ids.size():
		var p := c + Vector2(-14.0 + (i % cols) * 4.0, -16.0 + int(i / cols) * 4.0)
		var pu := PickupScene.instantiate()
		pu.name = "TestStand_%d" % i
		pu.item_id = str(ids[i])
		pu.infinite = true
		pu.show_label = true
		pu.position = Vector3(p.x, ground(p.x, p.y), p.y)
		root.add_child(pu)
	var props := [
		["prop.torch.stone", Vector2(-8, 4)], ["prop.brazier.stone", Vector2(8, 4)],
		["prop.target.dummy", Vector2(-6, 14)], ["prop.target.dummy", Vector2(-1, 15.5)], ["prop.target.dummy", Vector2(4, 14)],
		["prop.ice.block", Vector2(12, 8)], ["prop.ice.block", Vector2(14, 11)],
		["prop.crate.wood", Vector2(11, 14)], ["prop.crate.wood", Vector2(12.6, 15)],
		["prop.target.archery", Vector2(-16, 18)], ["prop.target.archery", Vector2(16, 20)],
	]
	for i in props.size():
		var off: Vector2 = props[i][1]
		var p := c + off
		var prop := AssetRegistry.instantiate(str(props[i][0]))
		prop.name = "Test_%d" % i
		g.add_child(prop)
		prop.position = Vector3(p.x, ground(p.x, p.y), p.y)
		if prop.has_node("Reactive") and str(props[i][0]) == "prop.ice.block":
			prop.get_node("Reactive").respawn_time = 5.0
		var look := Vector3(c.x, prop.position.y, c.y)
		if prop.position.distance_to(look) > 0.5:
			prop.look_at(look, Vector3.UP)
	# grapple pillar (purple, hookable) with a dummy on top
	var pp := c + Vector2(-20, 4)
	var pillar := _block(g, Vector3(pp.x, ground(pp.x, pp.y) - 0.5, pp.y), Vector3(2, 8.5, 2), "accent")
	pillar.name = "GrapplePillar"
	pillar.add_to_group("hook_targets")
	var top := AssetRegistry.instantiate("prop.target.dummy")
	top.name = "Test_PillarDummy"
	g.add_child(top)
	top.position = Vector3(pp.x, ground(pp.x, pp.y) + 8.0, pp.y)


# ---------------------------------------------------------------- bridges (found automatically where paths cross water)
func _build_bridges() -> void:
	var g := _group("Bridges")
	var count := 0
	for pts in paths:
		var samples: Array[Vector2] = []
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var steps := int(a.distance_to(b))
			for s in steps:
				samples.append(a.lerp(b, float(s) / steps))
		samples.append(pts[-1])
		var wet_start := -1
		for i in samples.size():
			var wet := ground(samples[i].x, samples[i].y) < 0.6
			if wet and wet_start < 0:
				wet_start = i
			elif not wet and wet_start >= 0:
				# walk out of the channel up each bank until the ground stops rising (bank top)
				var ia := wet_start
				while ia > 0 and wet_start - ia < 16 and _sample_h(samples, ia - 1) >= _sample_h(samples, ia) - 0.05:
					ia -= 1
				var ib := i
				while ib < samples.size() - 1 and ib - i < 16 and _sample_h(samples, ib + 1) >= _sample_h(samples, ib) - 0.05:
					ib += 1
				_bridge(g, samples[ia], samples[ib], count)
				count += 1
				wet_start = -1
	print("[island] %d bridges" % count)


func _sample_h(samples: Array[Vector2], i: int) -> float:
	return ground(samples[i].x, samples[i].y)


func _bridge(parent: Node, a: Vector2, b: Vector2, idx: int) -> void:
	var pa := Vector3(a.x, ground(a.x, a.y), a.y)
	var pb := Vector3(b.x, ground(b.x, b.y), b.y)
	var mid := (pa + pb) * 0.5
	var span := pb - pa
	var length := span.length() + 2.0
	var body := StaticBody3D.new()
	body.name = "Bridge_%d" % idx
	body.set_meta("material", "wood")
	parent.add_child(body)
	body.look_at_from_position(mid + Vector3.UP * 0.15, mid + Vector3.UP * 0.15 + span, Vector3.UP)
	for part in [[Vector3(0, 0, 0), Vector3(4.2, 0.4, length), "wood"],
			[Vector3(2.0, 0.6, 0), Vector3(0.25, 1.0, length), "wood"],
			[Vector3(-2.0, 0.6, 0), Vector3(0.25, 1.0, length), "wood"]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[1]
		mi.mesh = bm
		mi.material_override = _mats[part[2]]
		mi.position = part[0]
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = part[1]
		cs.shape = sh
		cs.position = part[0]
		body.add_child(cs)
	# posts at the river bed so it doesn't float
	for t in [0.3, 0.7]:
		var p := pa.lerp(pb, t)
		var bed := ground(p.x, p.z)
		var post_h := p.y - bed
		if post_h > 1.0:
			_block(parent, Vector3(p.x, bed - 0.5, p.z), Vector3(1.0, post_h + 0.5, 1.0), "wood", 0.0, "wood")


# ---------------------------------------------------------------- cover + scatter
func _path_samples(spacing: float) -> Array:
	var out := []    # [pos: Vector2, dir: Vector2]
	for pts in paths:
		var carry := 0.0
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := a.distance_to(b)
			var t := spacing - carry
			while t < d:
				out.append([a.lerp(b, t / d), (b - a).normalized()])
				t += spacing
			carry = d - (t - spacing)
	return out


func _dist_to_paths(p: Vector2) -> float:
	var best := 1e9
	for pts in paths:
		for i in pts.size() - 1:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


func _in_landmark(p: Vector2, pad := 0.0) -> bool:
	for z in _landmark_zones:
		if p.distance_to(Vector2(z.x, z.y)) < z.z + pad:
			return true
	return false


func _dry_flat(p: Vector2, max_slope := 25.0) -> bool:
	var h := ground(p.x, p.y)
	if h < 0.8 or Water.depth_at(Vector3(p.x, h, p.y)) > 0.0 or Water.kind_at(Vector3(p.x, h + 0.2, p.y)) != "":
		return false
	return terrain.slope_deg(p.x, p.y) <= max_slope


## Land in every direction for `r` metres (keeps spawns off islets and the very shoreline).
func _inland(p: Vector2, r: float) -> bool:
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var q: Vector2 = p + d * r
		if ground(q.x, q.y) < 0.5:
			return false
	return true


func _place_cover() -> void:
	var g := _group("Cover")
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed + 7
	var i := 0
	for s in _path_samples(cover_every):
		var pos: Vector2 = s[0]
		var dir: Vector2 = s[1]
		var side := 1.0 if i % 2 == 0 else -1.0
		var p := pos + dir.orthogonal() * side * rng.randf_range(4.0, 6.5)
		i += 1
		if _in_landmark(p, 4.0) or not _dry_flat(p, 22.0):
			continue
		var biome: String = terrain.biome_at(p.x, p.y)
		var rot := dir.angle() * -1.0 + rng.randf_range(-0.3, 0.3)
		match biome:
			"snow":
				_block(g, _on_ground(p.x, p.y, 0.4), Vector3(3.2, 1.6, 1.0), "icestone", rot)
			"ash":
				_block(g, _on_ground(p.x, p.y, 0.4), Vector3(2.6, 2.0, 1.6), "basalt", rot + 0.6)
			"sand", "mesa", "beach":
				_block(g, _on_ground(p.x, p.y, 0.4), Vector3(2.4, 1.5, 1.4), "sandstone", rot)
			_:
				var prop: Node3D
				if rng.randf() < 0.45:
					prop = AssetRegistry.instantiate("prop.crate.wood")      # burnable soft cover
				else:
					prop = _make_rock(["rock_boulder_a", "rock_boulder_b", "rock_mossy"][i % 3], "Cover_%d" % i)
				prop.name = "Cover_%d" % i                                     # fixed names (Reactive sync)
				g.add_child(prop)
				prop.position = _on_ground(p.x, p.y, 0.05)
				prop.rotation.y = rot


const NATURE := "res://assets/models/nature/%s.glb"
const ReactiveScript := preload("res://systems/components/reactive.gd")

## What grows where (biome painted in biome.png). [model, weight]; "env.tree.oak_a" = registry id.
var tree_sets := {
	"forest": [["tree_oak_b", 3], ["tree_oak_c", 3], ["env.tree.oak_a", 2], ["tree_birch", 2], ["tree_pine", 2], ["tree_autumn", 1], ["tree_pine_small", 1]],
	"grass": [["tree_oak_b", 2], ["tree_oak_c", 1], ["tree_birch", 2], ["tree_autumn", 1], ["env.tree.oak_a", 1]],
	"snow": [["tree_pine_snow", 3], ["tree_pine_snow_small", 3], ["tree_pine", 1]],
	"ash": [["tree_dead", 1]],
	"sand": [["cactus", 3], ["tree_palm", 1], ["tree_dead", 1]],
	"mesa": [["cactus", 1]],
	"beach": [["tree_palm", 1]],
}
var tree_density := { "forest": 0.85, "grass": 0.12, "snow": 0.22, "ash": 0.1, "sand": 0.08, "mesa": 0.05, "beach": 0.12 }
var rock_sets := {
	"forest": ["rock_mossy", "rock_boulder_a", "rock_cluster", "rock_mossy"],
	"grass": ["rock_boulder_a", "rock_boulder_b", "rock_slab", "rock_cluster", "rock_spire"],
	"snow": ["rock_snow", "rock_snow", "rock_boulder_b", "rock_spire"],
	"ash": ["rock_basalt", "rock_basalt", "rock_spire"],
	"sand": ["rock_sand", "rock_slab", "rock_sand"], "mesa": ["rock_sand"], "beach": ["rock_slab", "rock_boulder_a"],
	"plaza": ["rock_slab"], "path": ["rock_cluster"],
}
## Ground cover (no collision, MultiMesh): per biome [model, density per m²]
var cover_sets := {
	"grass": [["grass_tuft_a", 0.09], ["grass_tuft_b", 0.05], ["grass_tall", 0.015], ["flowers_red", 0.006], ["flowers_yellow", 0.008],
		["flowers_blue", 0.005], ["flowers_white", 0.006], ["bush_round", 0.004]],
	"forest": [["grass_tuft_a", 0.05], ["fern", 0.04], ["mushrooms", 0.01], ["bush_round", 0.008], ["bush_berry", 0.005],
		["flowers_white", 0.004], ["grass_tall", 0.01]],
	"plaza": [["grass_tuft_a", 0.02]],
	"snow": [["grass_snow", 0.03]],
	"sand": [["grass_dry", 0.02], ["shrub_dry", 0.006]],
	"mesa": [["shrub_dry", 0.005]],
	"beach": [["grass_dry", 0.012]],
	"ash": [["shrub_dry", 0.004]],
	"path": [["grass_tuft_a", 0.01]],
}
## Herbs / food / ore growing in the world (natural pickups): biome -> [item, per 1000 m²]
var forage_sets := {
	"forest": [["muddlemoss", 0.5], ["smolderpuff", 0.4], ["lumenbell", 0.4], ["amberdrip_comb", 0.25], ["hearthapple", 0.3]],
	"grass": [["glarepetal", 0.35], ["sparkthistle", 0.3], ["stoutroot", 0.35], ["hearthapple", 0.25], ["coppergleam_ore", 0.15]],
	"snow": [["frostcap", 0.9], ["ironvein_ore", 0.3], ["starsilver_ore", 0.05]],
	"ash": [["cinderpepper", 0.9], ["coppergleam_ore", 0.3], ["starsilver_ore", 0.08]],
	"sand": [["sparkthistle", 0.3], ["ironvein_ore", 0.25], ["cinderpepper", 0.2]],
	"mesa": [["coppergleam_ore", 0.4], ["ironvein_ore", 0.3]],
	"beach": [["dewbloom", 0.3]],
}
@export var cover_view_distance := 90.0          ## grass / flowers fade out past this (performance)
@export var cover_chunk := 64.0
@export var path_stone_spacing := 1.5
var _scene_cache := {}
var _mesh_cache := {}


func _nature_scene(id: String) -> PackedScene:
	if not _scene_cache.has(id):
		var path := NATURE % id
		_scene_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _scene_cache[id]


## First mesh inside a nature glb (for MultiMesh ground cover / path stones).
func _nature_mesh(id: String) -> Mesh:
	if not _mesh_cache.has(id):
		var mesh: Mesh = null
		var ps := _nature_scene(id)
		if ps:
			var inst := ps.instantiate()
			var mi := inst.find_children("*", "MeshInstance3D", true, false)
			if not mi.is_empty():
				mesh = (mi[0] as MeshInstance3D).mesh
			inst.free()
		_mesh_cache[id] = mesh
	return _mesh_cache[id]


func _pick_weighted(rng: RandomNumberGenerator, entries: Array) -> String:
	var total := 0.0
	for e in entries:
		total += float(e[1])
	var r := rng.randf() * total
	for e in entries:
		r -= float(e[1])
		if r <= 0.0:
			return str(e[0])
	return str(entries[-1][0])


func _aabb_of(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## A tree from the nature set (or a registry scene): static trunk collision, grapple-able,
## burnable (Reactive wood). Fixed name so its fire state syncs.
func _make_tree(id: String, nm: String) -> Node3D:
	if id.begins_with("env."):
		var t := AssetRegistry.instantiate(id)
		t.name = nm
		return t
	var ps := _nature_scene(id)
	if ps == null:
		return null
	var body := StaticBody3D.new()
	body.name = nm
	body.add_to_group("hook_targets")
	body.set_meta("material", "wood")
	var model := ps.instantiate()
	model.name = "Model"
	body.add_child(model)
	var box := _aabb_of(model)
	var h := maxf(box.size.y, 1.0)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3 if id != "cactus" else 0.28
	cyl.height = minf(h * 0.6, 4.0)
	cs.shape = cyl
	cs.position.y = cyl.height * 0.5
	body.add_child(cs)
	var r := ReactiveScript.new()
	r.name = "Reactive"
	r.material_id = "wood"
	r.max_hp_override = 120.0
	r.fire_height = h * 0.55
	r.fire_size = clampf(h * 0.3, 1.0, 2.2)
	body.add_child(r)
	return body


func _make_rock(id: String, nm: String) -> Node3D:
	var ps := _nature_scene(id)
	if ps == null:
		return AssetRegistry.instantiate(rock_id)
	var body := StaticBody3D.new()
	body.name = nm
	body.set_meta("material", "stone")
	var model := ps.instantiate()
	model.name = "Model"
	body.add_child(model)
	var box := _aabb_of(model)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(0.3, minf(box.size.x, box.size.z) * 0.45)
	cyl.height = maxf(0.3, box.size.y * 0.9)
	cs.shape = cyl
	cs.position.y = cyl.height * 0.5
	body.add_child(cs)
	return body


func _place_trees_and_rocks() -> void:
	var g := _group("Nature")
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed
	var taken: Array[Vector2] = []
	var trees := 0
	var tries := 0
	var hw: float = terrain.half_w() - 6.0
	while trees < max_trees and tries < max_trees * 40:
		tries += 1
		var p := Vector2(rng.randf_range(-hw, hw), rng.randf_range(-hw, hw))
		var b: String = terrain.biome_at(p.x, p.y)
		if not tree_sets.has(b) or rng.randf() > float(tree_density.get(b, 0.0)):
			continue
		if not _dry_flat(p, 30.0) or _in_landmark(p, 3.0) or _dist_to_paths(p) < 4.0:
			continue
		var ok := true
		for t in taken:
			if t.distance_squared_to(p) < 30.0:
				ok = false
				break
		if not ok:
			continue
		var tree := _make_tree(_pick_weighted(rng, tree_sets[b]), "Tree_%d" % trees)
		if tree == null:
			continue
		taken.append(p)
		g.add_child(tree)
		tree.position = _on_ground(p.x, p.y, 0.2)
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.25)
		trees += 1
	var rocks := 0
	tries = 0
	while rocks < max_rocks and tries < max_rocks * 30:
		tries += 1
		var p := Vector2(rng.randf_range(-hw, hw), rng.randf_range(-hw, hw))
		var b: String = terrain.biome_at(p.x, p.y)
		if not rock_sets.has(b) or not _dry_flat(p, 38.0) or _in_landmark(p, 2.0) or _dist_to_paths(p) < 3.0:
			continue
		var list: Array = rock_sets[b]
		var rock := _make_rock(str(list[rng.randi() % list.size()]), "Rock_%d" % rocks)
		g.add_child(rock)
		rock.position = _on_ground(p.x, p.y, 0.25)
		rock.rotation.y = rng.randf() * TAU
		rock.scale = Vector3.ONE * rng.randf_range(0.6, 1.7)
		rocks += 1
	print("[island] %d trees, %d rocks" % [trees, rocks])
	_place_ground_cover()
	_place_path_stones()
	_place_forage()


## Grass, flowers, ferns, bushes, mushrooms: MultiMesh per (chunk, model), faded by distance.
func _place_ground_cover() -> void:
	var g := _group("GroundCover")
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed + 11
	var buckets := {}    # "cx,cz,id" -> Array[Transform3D]
	var hw: float = terrain.half_w() - 2.0
	var step := 2.0
	var x := -hw
	while x < hw:
		var z := -hw
		while z < hw:
			var p := Vector2(x + rng.randf() * step, z + rng.randf() * step)
			z += step
			var b: String = terrain.biome_at(p.x, p.y)
			if not cover_sets.has(b):
				continue
			for e in cover_sets[b]:
				if rng.randf() > float(e[1]) * step * step:
					continue
				var h := ground(p.x, p.y)
				if h < 0.4 or terrain.slope_deg(p.x, p.y) > 40.0 or Water.kind_at(Vector3(p.x, h + 0.1, p.y)) != "":
					break
				var key := "%d,%d,%s" % [int(floor(p.x / cover_chunk)), int(floor(p.y / cover_chunk)), e[0]]
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.75, 1.3))
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(Transform3D(basis, Vector3(p.x, h - 0.03, p.y)))
				break
		x += step
	var count := 0
	for key in buckets:
		var id: String = str(key).get_slice(",", 2)
		var mesh := _nature_mesh(id)
		if mesh == null:
			continue
		var xf: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not id.begins_with("bush") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = cover_view_distance * (1.6 if id.begins_with("bush") else 1.0)
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		g.add_child(mmi)
		count += xf.size()
	print("[island] %d ground cover plants" % count)


## Flat stones laid along the paths (walk-over, no collision).
func _place_path_stones() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed + 23
	var ids := ["flagstone_a", "flagstone_b", "flagstone_c", "stepstone_round"]
	var buckets := {}
	for s in _path_samples(path_stone_spacing):
		var pos: Vector2 = s[0]
		var dir: Vector2 = s[1]
		var p := pos + dir.orthogonal() * rng.randf_range(-1.2, 1.2) + dir * rng.randf_range(-0.3, 0.3)
		var h := ground(p.x, p.y)
		if h < 0.6 or Water.kind_at(Vector3(p.x, h + 0.1, p.y)) != "" or terrain.slope_deg(p.x, p.y) > 30.0:
			continue
		var id: String = ids[rng.randi() % (3 if rng.randf() < 0.85 else 4)]
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2))
		if not buckets.has(id):
			buckets[id] = []
		buckets[id].append(Transform3D(basis, Vector3(p.x, h - 0.04, p.y)))
	var g := _group("PathStones")
	for id in buckets:
		var mesh := _nature_mesh(id)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var xf: Array = buckets[id]
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 160.0
		g.add_child(mmi)


## Herbs, food and ore growing where they belong (natural pickups: no glow ring, sit in the ground).
func _place_forage() -> void:
	var root := Node3D.new()
	root.name = "Forage"
	add_child(root)
	var rng := _match_rng(2)
	var hw: float = terrain.half_w() - 6.0
	var n := 0
	var cell := 10.0                          # one roll per 100 m² cell
	var x := -hw
	while x < hw:
		var z := -hw
		while z < hw:
			var p := Vector2(x + rng.randf() * cell, z + rng.randf() * cell)
			z += cell
			var b: String = terrain.biome_at(p.x, p.y)
			if not forage_sets.has(b) or not _dry_flat(p, 35.0) or _in_landmark(p, 1.0):
				continue
			for e in forage_sets[b]:
				if rng.randf() > float(e[1]) * cell * cell / 1000.0:
					continue
				if not ItemDB.has_item(str(e[0])):
					break
				var pu := PickupScene.instantiate()
				pu.name = "Forage_%d" % n
				pu.item_id = str(e[0])
				pu.natural = true
				pu.position = Vector3(p.x, ground(p.x, p.y) - 0.03, p.y)
				root.add_child(pu)
				n += 1
				break
		x += cell
	print("[island] %d forage nodes" % n)


# ---------------------------------------------------------------- spawns
## 12 spread-out spawn spots: candidate grid on dry, gentle land away from landmarks, then
## farthest-point picking (each new spawn as far as possible from the others).
func _pick_spawns() -> void:
	var cands: Array[Vector2] = []
	var hw: float = terrain.half_w() - 10.0
	var x := -hw
	while x <= hw:
		var z := -hw
		while z <= hw:
			var p := Vector2(x, z)
			if _dry_flat(p, 18.0) and not _in_landmark(p, 18.0) and p.distance_to(center) > 95.0 \
					and terrain.biome_at(p.x, p.y) != "lava" and _inland(p, 22.0):
				cands.append(p)
			z += 8.0
		x += 8.0
	if cands.is_empty():
		push_warning("island: no spawn candidates")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed
	var picked: Array[Vector2] = [cands[rng.randi() % cands.size()]]
	while picked.size() < spawn_count:
		var best := Vector2.ZERO
		var best_d := -1.0
		for c in cands:
			var dmin := 1e9
			for q in picked:
				dmin = minf(dmin, c.distance_to(q))
			if dmin > best_d:
				best_d = dmin
				best = c
		picked.append(best)
	var min_gap := 1e9
	for i in picked.size():
		for j in range(i + 1, picked.size()):
			min_gap = minf(min_gap, picked[i].distance_to(picked[j]))
	spawn_points.clear()
	var g := _group("Spawns")
	for i in picked.size():
		var p := picked[i]
		spawn_points.append(Vector3(p.x, ground(p.x, p.y) + 0.6, p.y))
		var m := Marker3D.new()
		m.name = "Spawn_%d" % i
		m.position = spawn_points[-1]
		g.add_child(m)
	print("[island] %d spawns, closest pair %.0fm (target %.0fm)" % [picked.size(), min_gap, spawn_min_spacing])
	if min_gap < spawn_min_spacing:
		push_warning("island: spawns only %.0fm apart" % min_gap)


# ---------------------------------------------------------------- loot: chests + loose items (new spots every match)
const ChestScript := preload("res://scenes/props/loot/chest.gd")

@export_group("Chests")
@export var chest_counts := { "common": 34, "uncommon": 20, "rare": 9, "legendary": 3 }
@export var chest_min_gap := 14.0
@export var loose_items := 45                  ## loose ground loot (ammo / basic gear) at random spots
## What each chest tier can hold (rolls = how many items come out).
@export var chest_loot := {
	"common": ["slingstones", "arrows", "slingshot_thornfork", "bow_basic", "hearthapple", "wood", "slingstones", "arrows"],
	"uncommon": ["sword_dawnsteel", "bow_basic", "boomerang_basic", "shield_gildcrest", "slingshot_thornfork", "arrows", "slingstones"],
	"rare": ["greatsword_emberfang", "maul_quakeheart", "grappleclaw", "bomb_blastgourd", "trap_snapjaw", "fan_galeleaf",
		"staff_sandspire", "rod_rimecaller", "arrows"],
	"legendary": ["skytether", "greatsword_emberfang", "maul_quakeheart", "bomb_blastgourd", "rod_rimecaller", "starsilver_ore"],
}
@export var chest_rolls := { "common": Vector2i(1, 2), "uncommon": Vector2i(1, 2), "rare": Vector2i(2, 2), "legendary": Vector2i(2, 3) }


func _match_rng(salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Lobby.match_seed + salt * 7919)
	return rng


func _random_dry_spot(rng: RandomNumberGenerator, near_center_bias := 0.0) -> Vector2:
	var hw: float = terrain.half_w() - 10.0
	for t in 60:
		var p := Vector2(rng.randf_range(-hw, hw), rng.randf_range(-hw, hw))
		if near_center_bias > 0.0:
			p = p.lerp(center, rng.randf() * near_center_bias)
		if _dry_flat(p, 28.0) and _inland(p, 6.0) and terrain.biome_at(p.x, p.y) != "lava":
			return p
	return Vector2.INF


func _place_loot() -> void:
	var root := Node3D.new()
	root.name = "Loot"
	add_child(root)
	var rng := _match_rng(1)
	# chests: richer tiers lean toward the centre / landmark spots
	var chest_spots: Array[Vector2] = []
	var bias := { "common": 0.0, "uncommon": 0.25, "rare": 0.5, "legendary": 0.75 }
	var n := 0
	for tier in ["legendary", "rare", "uncommon", "common"]:
		for k in int(chest_counts.get(tier, 0)):
			var p := Vector2.INF
			for t in 20:
				var q := _random_dry_spot(rng, float(bias[tier]))
				if q == Vector2.INF:
					continue
				var ok := true
				for c in chest_spots:
					if c.distance_to(q) < chest_min_gap:
						ok = false
						break
				if ok:
					p = q
					break
			if p == Vector2.INF:
				continue
			chest_spots.append(p)
			_spawn_chest(root, tier, p, rng, n)
			n += 1
	# fair start: a common chest near every spawn
	for sp in spawn_points:
		var a := rng.randf() * TAU
		var p := Vector2(sp.x, sp.z) + Vector2(cos(a), sin(a)) * rng.randf_range(7.0, 12.0)
		if _dry_flat(p, 30.0):
			_spawn_chest(root, "common", p, rng, n)
			n += 1
	# loose items anywhere
	var loose := 0
	for k in loose_items:
		var p := _random_dry_spot(rng)
		if p == Vector2.INF:
			continue
		var item_id := _roll_item(rng, p)
		if item_id == "" or not ItemDB.has_item(item_id):
			continue
		var pu := PickupScene.instantiate()
		pu.name = "Loot_%d" % loose
		pu.item_id = item_id
		pu.position = Vector3(p.x, ground(p.x, p.y), p.y)
		root.add_child(pu)
		loose += 1
	print("[island] seed %d: %d chests, %d loose items" % [Lobby.match_seed, n, loose])


func _spawn_chest(root: Node, tier: String, p: Vector2, rng: RandomNumberGenerator, idx: int) -> void:
	var c := ChestScript.new()
	c.name = "Chest_%d" % idx
	c.tier = tier
	c.loot_pool = chest_loot.get(tier, [])
	c.rolls = chest_rolls.get(tier, Vector2i(1, 2))
	c.position = Vector3(p.x, ground(p.x, p.y) - 0.05, p.y)
	c.rotation.y = rng.randf() * TAU
	root.add_child(c)


func _roll_item(rng: RandomNumberGenerator, p: Vector2) -> String:
	var t := clampf(p.distance_to(center) / 220.0, 0.0, 1.0)      # 0 = centre, 1 = coast
	var w: Vector4 = tier_weights_center.lerp(tier_weights, t)
	if _in_landmark(p, 2.0):
		w = w.lerp(tier_weights_center, 0.6)
	var r := rng.randf() * (w.x + w.y + w.z + w.w)
	var tier := "common"
	if r > w.x:
		tier = "uncommon"
	if r > w.x + w.y:
		tier = "rare"
	if r > w.x + w.y + w.z:
		tier = "legendary"
	var pool: Array = loot_tiers.get(tier, [])
	return str(pool[rng.randi() % pool.size()]) if not pool.is_empty() else ""
