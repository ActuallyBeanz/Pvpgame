extends Node3D
## Test arena: every item, every reaction, every traversal tool - laid out in districts.
##   HUB (centre)          spawn plaza, signposts, one chest of each tier
##   ARMORY (north)        item stalls by category: Melee & Shields / Bows & Throwing / Tools &
##                         Bombs / Ammo / Plants / Food / Materials (new items sort themselves)
##   RANGE (east)          archery lane with distance markers, dummy field with cover
##   ELEMENT YARD (west)   braziers, torches, crates, barrels, a shack, ice, a wading pool, trees
##   TRAVERSAL (south)     platform + ramp + steps, grapple pillar, swim pool, sand, secret hut
## Everything is placed in code from the exports below (same on every peer: fixed names /
## seeds so Reactive props and pickups sync). Host spawns players once every peer has loaded.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PickupScene := preload("res://scenes/items/pickup.tscn")
const ReactiveScript := preload("res://systems/components/reactive.gd")
const CrackedWall := preload("res://scenes/props/world/cracked_wall.gd")
const ChestScript := preload("res://scenes/props/loot/chest.gd")
const NATURE := "res://assets/models/nature/%s.glb"
var allow_respawn := true                 ## test area: you come back a few seconds after dying

@export var arena_half := 90.0            ## ground is 2x this wide (match the Ground node in the scene)
@export var decor_seed := 42              ## same seed = same trees / grass on every peer

@export_group("Hub")
@export var hub_radius := 10.0
@export var chest_spot := Vector3(-8, 0, 7)        ## chest of each tier, in a row going +x

@export_group("Armory (items)")
## Stalls in order; each item goes to the first stall whose rule matches (see _stall_of).
@export var stall_order: PackedStringArray = ["Melee & Shields", "Bows & Throwing", "Tools & Bombs",
	"Brews", "Ammo", "Plants", "Food", "Materials"]
@export var armory_rows: Array[float] = [-22.0, -42.0]     ## z of each stall row (first 3 stalls, then the rest)
@export var stall_cols := 4
@export var item_gap := 2.6

@export_group("Range")
@export var lane_start := Vector3(24, 0, -10)      ## shooting line; targets go out along +x
@export var lane_distances: PackedFloat32Array = [10.0, 20.0, 35.0, 50.0]
@export var dummy_field := Vector3(40, 0, 14)      ## centre of the dummy field
@export var target_id := "prop.target.archery"
@export var dummy_id := "prop.target.dummy"

@export_group("Element yard")
@export var yard_center := Vector3(-42, 0, 0)

@export_group("Traversal")
@export var course_center := Vector3(0, 0, 40)     ## platform / ramp / steps / grapple pillar (scene's Course nodes)
@export var pool_center := Vector3(30, 0, 44)
@export var pool_size := Vector2(16, 16)
@export var pool_depth := 3.2
@export var sand_center := Vector3(-32, 0, 44)
@export var sand_size := Vector2(18, 18)
@export var stash_test_pos := Vector3(0, 0, 68)

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var overview_camera: Camera3D = $OverviewCamera

var _keep: Array[Rect2] = []              ## areas the grass / trees stay out of


func _ready() -> void:
	spawner.spawn_function = _build_player
	overview_camera.look_at_from_position(Vector3(0, 60, 70), Vector3.ZERO)
	Water.clear()
	_build_hub()
	_build_armory()
	_build_range()
	_build_yard()
	_build_traversal()
	_build_paths()
	_scatter_nature()
	if multiplayer.is_server():
		Lobby.all_peers_loaded.connect(_spawn_all_players, CONNECT_ONE_SHOT)
		NetworkManager.peer_disconnected.connect(_on_peer_left)
	Lobby.report_match_loaded()
	Audio.play_ambience("amb.field")
	Audio.play("ui.match_start")
	tree_exiting.connect(func() -> void:
		Audio.stop_ambience(0.3)
		Water.clear())


# ================================================================ players
# Server only.
func _spawn_all_players() -> void:
	var ids := Lobby.players.keys()
	ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		var entry: Dictionary = Lobby.players[id]
		var angle := TAU * i / ids.size()
		var pos := Vector3(cos(angle), 0.0, sin(angle)) * GameConfig.settings.test_spawn_radius
		pos.y = 0.2
		spawner.spawn({ "id": id, "pos": pos, "name": entry.name, "color": entry.color,
			"model": str(entry.get("model", "")) })


# Runs on every peer with identical data (MultiplayerSpawner).
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
		n.queue_free()  # spawner despawns it on clients too


# ================================================================ helpers
func _group(nm: String) -> Node3D:
	var g := Node3D.new()
	g.name = nm
	$Props.add_child(g)
	return g


func _keep_out(center: Vector3, size: Vector2) -> void:
	_keep.append(Rect2(Vector2(center.x, center.z) - size * 0.5, size))


func _box(parent: Node, at: Vector3, size: Vector3, color: Color, meta := "stone") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("material", meta)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)
	body.position = at
	return body


## Flat stone pad (walkable, barely raised).
func _pad(parent: Node, center: Vector3, size: Vector2, color := Color(0.66, 0.63, 0.58)) -> void:
	_box(parent, center + Vector3(0, 0.06, 0), Vector3(size.x, 0.12, size.y), color)
	_keep_out(center, size + Vector2(2, 2))


## Wooden signpost with a big floating title (readable from anywhere).
func _sign(parent: Node, at: Vector3, title: String, color := Color(1, 0.92, 0.7), size := 96) -> void:
	_box(parent, at + Vector3(0, 1.1, 0), Vector3(0.2, 2.2, 0.2), Color(0.42, 0.28, 0.16), "wood")
	_box(parent, at + Vector3(0, 2.1, 0), Vector3(2.4, 0.7, 0.12), Color(0.55, 0.38, 0.22), "wood")
	var l := Label3D.new()
	l.text = title
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.font_size = size
	l.outline_size = 14
	l.pixel_size = 0.01
	l.modulate = color
	l.position = at + Vector3(0, 3.4, 0)
	parent.add_child(l)


func _place(parent: Node, id: String, nm: String, at: Vector3, yaw := 0.0, respawn := -1.0) -> Node3D:
	var prop := AssetRegistry.instantiate(id)
	prop.name = nm
	prop.position = at
	prop.rotation.y = yaw
	if respawn > 0.0 and prop.has_node("Reactive"):
		prop.get_node("Reactive").respawn_time = respawn
	parent.add_child(prop)
	return prop


func _stand(parent: Node, id: String, nm: String, at: Vector3) -> void:
	if not ItemDB.has_item(id):
		return
	var pu := PickupScene.instantiate()
	pu.name = nm
	pu.item_id = id
	pu.infinite = true
	pu.show_label = true
	pu.position = at
	parent.add_child(pu)


func _nature(id: String) -> PackedScene:
	var path := NATURE % id
	return load(path) as PackedScene if ResourceLoader.exists(path) else null


func _aabb_of(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Burnable, grapple-able tree from the nature set (like the island's).
func _tree(parent: Node, id: String, nm: String, at: Vector3, yaw: float, scale_k: float, respawn := 30.0) -> void:
	var ps := _nature(id)
	if ps == null:
		return
	var body := StaticBody3D.new()
	body.name = nm
	body.add_to_group("hook_targets")
	body.set_meta("material", "wood")
	var model := ps.instantiate()
	model.name = "Model"
	body.add_child(model)
	var h := maxf(_aabb_of(model).size.y, 1.0)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = minf(h * 0.6, 4.0)
	cs.shape = cyl
	cs.position.y = cyl.height * 0.5
	body.add_child(cs)
	var r := ReactiveScript.new()
	r.name = "Reactive"
	r.material_id = "wood"
	r.max_hp_override = 40.0
	r.fire_height = h * 0.55
	r.fire_size = clampf(h * 0.3, 1.0, 2.2)
	r.respawn_time = respawn
	body.add_child(r)
	body.position = at
	body.rotation.y = yaw
	body.scale = Vector3.ONE * scale_k
	parent.add_child(body)


func _rock(parent: Node, id: String, nm: String, at: Vector3, yaw: float, scale_k: float) -> void:
	var ps := _nature(id)
	if ps == null:
		return
	var body := StaticBody3D.new()
	body.name = nm
	body.set_meta("material", "stone")
	body.add_to_group("harvest_rock")
	var model := ps.instantiate()
	body.add_child(model)
	var box := _aabb_of(model)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(0.3, minf(box.size.x, box.size.z) * 0.45)
	cyl.height = maxf(0.3, box.size.y * 0.9)
	cs.shape = cyl
	cs.position.y = cyl.height * 0.5
	body.add_child(cs)
	body.position = at
	body.rotation.y = yaw
	body.scale = Vector3.ONE * scale_k
	parent.add_child(body)


## Decoration only (no collision): grass, flowers, flagstones.
func _decor(parent: Node, id: String, at: Vector3, yaw: float, scale_k: float) -> void:
	var ps := _nature(id)
	if ps == null:
		return
	var n := ps.instantiate() as Node3D
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale_k
	parent.add_child(n)


# ================================================================ HUB
func _build_hub() -> void:
	var g := _group("Hub")
	_keep_out(Vector3.ZERO, Vector2.ONE * hub_radius * 2.0)
	# round flagstone plaza
	var rng := RandomNumberGenerator.new()
	rng.seed = decor_seed + 1
	for ring in range(0, int(hub_radius), 2):
		var n := maxi(1, int(TAU * ring / 1.6))
		for k in n:
			var a := TAU * (float(k) + rng.randf() * 0.3) / float(n)
			_decor(g, ["flagstone_a", "flagstone_b", "flagstone_c"][(k + ring) % 3],
				Vector3(cos(a) * ring, 0.01, sin(a) * ring), rng.randf() * TAU, 1.3)
	_sign(g, Vector3(0, 0, -hub_radius + 1), "ARMORY  ↑", Color(1, 0.85, 0.45))
	_sign(g, Vector3(hub_radius - 1, 0, 0), "RANGE  →", Color(1, 0.6, 0.5))
	_sign(g, Vector3(-hub_radius + 1, 0, 0), "←  ELEMENT YARD", Color(0.6, 0.85, 1))
	_sign(g, Vector3(0, 0, hub_radius - 1), "TRAVERSAL  ↓", Color(0.7, 1, 0.65))
	# one chest of each tier, so you can learn the looks
	var tiers := ["common", "uncommon", "rare", "legendary"]
	var pools := {
		"common": ["arrows", "slingstones", "hearthapple", "wood"],
		"uncommon": ["sword_dawnsteel", "bow_basic", "fire_arrows", "shield_gildcrest"],
		"rare": ["greatsword_emberfang", "grappleclaw", "bomb_blastgourd", "rod_rimecaller"],
		"legendary": ["skytether", "maul_quakeheart", "bomb_arrows", "staff_sandspire"],
	}
	for i in tiers.size():
		var c := ChestScript.new()
		c.name = "HubChest_%d" % i
		c.tier = tiers[i]
		c.loot_pool = pools[tiers[i]]
		c.rolls = Vector2i(1, 2)
		g.add_child(c)
		c.position = chest_spot + Vector3(i * 2.4, 0, 0)
		c.rotation.y = PI


# ================================================================ ARMORY
## Which stall an item belongs on (by its data, so new items sort themselves).
func _stall_of(it: Resource) -> String:
	if it.category == "brew":
		return "Brews"
	if it.kind == "shield" or (it.kind == "weapon" and it.action_tag == "slash"):
		return "Melee & Shields"
	if it.kind == "weapon" and it.action_tag in ["shoot", "throw"]:
		return "Bows & Throwing"
	if it.kind == "weapon":
		return "Tools & Bombs"
	if it.kind == "ammo":
		return "Ammo"
	if it.category == "reagent":
		return "Plants"
	if it.category == "food":
		return "Food"
	return "Materials"


func _build_armory() -> void:
	var g := _group("Armory")
	var by_stall := {}
	for s in stall_order:
		by_stall[s] = []
	for id in ItemDB.all_ids():
		var it := ItemDB.get_item(str(id))
		if it == null:
			continue
		var stall := _stall_of(it)
		if not by_stall.has(stall):
			by_stall[stall] = []
		(by_stall[stall] as Array).append(str(id))
	var colors := [Color(1, 0.7, 0.5), Color(1, 0.85, 0.5), Color(0.75, 0.8, 1), Color(0.95, 0.6, 1), Color(0.9, 0.9, 0.7),
		Color(0.65, 1, 0.65), Color(1, 0.65, 0.7), Color(0.8, 0.75, 0.7)]
	var split := 4                                 # first row: weapons, tools, brews; second: the stackables
	var rows := [stall_order.slice(0, split), stall_order.slice(split)]
	var n_pickup := 0
	for r in rows.size():
		var names: PackedStringArray = rows[r]
		var widths: Array[float] = []
		var total := 0.0
		for s in names:
			var w := float(mini(stall_cols, maxi(1, (by_stall[s] as Array).size()))) * item_gap + 2.0
			widths.append(w)
			total += w
		total += 6.0 * (names.size() - 1)
		var x := -total * 0.5
		var z: float = armory_rows[mini(r, armory_rows.size() - 1)]
		for k in names.size():
			var s: String = names[k]
			var items: Array = by_stall[s]
			var w := widths[k]
			var rows_n := maxi(1, ceili(float(items.size()) / float(stall_cols)))
			var depth := rows_n * item_gap + 3.0
			var c := Vector3(x + w * 0.5, 0, z - depth * 0.5 + 1.5)
			var col: Color = colors[stall_order.find(s) % colors.size()]
			_pad(g, c, Vector2(w, depth), Color(0.62, 0.6, 0.55).lerp(col, 0.12))
			_sign(g, Vector3(c.x, 0, z + 2.6), s.to_upper(), col, 80)
			for i in items.size():
				var cx := i % stall_cols
				var cz := i / stall_cols
				var cols_here := mini(stall_cols, items.size() - cz * stall_cols)
				var px := c.x + (float(cx) - (cols_here - 1) * 0.5) * item_gap
				var pz := z - 0.2 - float(cz) * item_gap
				_stand(g, str(items[i]), "Pickup_%d" % n_pickup, Vector3(px, 0.13, pz))
				n_pickup += 1
			x += w + 6.0


# ================================================================ RANGE
func _build_range() -> void:
	var g := _group("Range")
	var start := lane_start
	_sign(g, start + Vector3(-2, 0, -5), "RANGE", Color(1, 0.6, 0.5))
	# archery lane: a shooting line and targets at marked distances
	var far: float = lane_distances[lane_distances.size() - 1] if lane_distances.size() > 0 else 50.0
	_box(g, start + Vector3(far * 0.5 + 2, 0.02, 0), Vector3(far + 6, 0.04, 7), Color(0.5, 0.62, 0.38), "stone")
	_keep_out(start + Vector3(far * 0.5 + 2, 0, 0), Vector2(far + 8, 10))
	_box(g, start + Vector3(0, 0.05, 0), Vector3(0.3, 0.1, 7), Color(0.95, 0.95, 0.9))
	for i in lane_distances.size():
		var d: float = lane_distances[i]
		var t := AssetRegistry.instantiate(target_id)
		t.name = "LaneTarget_%d" % i
		g.add_child(t)
		var tp := start + Vector3(d, 0, (i % 2) * 1.6 - 0.8)
		if d >= 35.0:
			_box(g, tp + Vector3(0, 0.75, 0), Vector3(2, 1.5, 2), Color(0.55, 0.53, 0.5))   # raised far targets
			tp.y = 1.5
		t.position = tp
		t.look_at(Vector3(start.x - 10, tp.y, tp.z), Vector3.UP)
		t.rotate_y(PI)                              # board face (+Z) back toward the line
		var l := Label3D.new()
		l.text = "%d m" % int(d)
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.font_size = 64
		l.outline_size = 10
		l.pixel_size = 0.01
		l.position = start + Vector3(d, 0.4, 3.2)
		g.add_child(l)
	# dummy field: dummies behind cover, on a ledge, and a torch for boomerang fire tests
	var f := dummy_field
	_keep_out(f, Vector2(30, 24))
	var dummies := [Vector3(-8, 0, -6), Vector3(-2, 0, -3), Vector3(4, 0, -7), Vector3(9, 0, -1),
		Vector3(-6, 0, 5), Vector3(2, 0, 6), Vector3(10, 0, 8), Vector3(-11, 0, 9)]
	for i in dummies.size():
		var d := AssetRegistry.instantiate(dummy_id)
		d.name = "Dummy_%d" % i
		g.add_child(d)
		d.position = f + (dummies[i] as Vector3)
		d.look_at(Vector3(0, d.position.y, 0), Vector3.UP)
	var ledge := _box(g, f + Vector3(12, 1.5, -9), Vector3(4, 3, 4), Color(0.58, 0.56, 0.52))
	var high := AssetRegistry.instantiate(dummy_id)
	high.name = "Dummy_High"
	g.add_child(high)
	high.position = ledge.position + Vector3(0, 1.5, 0)
	_place(g, "prop.crate.wood", "RangeCrate_0", f + Vector3(-5, 0, -4.5), 0.2, 15.0)
	_place(g, "prop.crate.wood", "RangeCrate_1", f + Vector3(6, 0, 3.6), -0.3, 15.0)
	_place(g, "prop.barrel.wood", "RangeBarrel_0", f + Vector3(0, 0, 4.2), 0.0, 15.0)
	_place(g, "prop.barrel.wood", "RangeBarrel_1", f + Vector3(-3.5, 0, 6.8), 0.0, 15.0)
	_box(g, f + Vector3(-1, 0.6, -5), Vector3(4, 1.2, 0.5), Color(0.6, 0.58, 0.54))       # stone cover
	_box(g, f + Vector3(7, 0.6, 1.5), Vector3(0.5, 1.2, 4), Color(0.6, 0.58, 0.54))
	_rock(g, "rock_boulder_a", "RangeRock_0", f + Vector3(-12, 0, 0), 0.4, 1.2)
	_rock(g, "rock_boulder_b", "RangeRock_1", f + Vector3(13, 0, 3), 1.2, 1.1)
	_place(g, "prop.torch.stone", "RangeTorch", f + Vector3(-9, 0, -2))


# ================================================================ ELEMENT YARD
func _build_yard() -> void:
	var g := _group("Yard")
	var c := yard_center
	_keep_out(c, Vector2(40, 40))
	_sign(g, c + Vector3(12, 0, -2), "ELEMENT YARD", Color(0.6, 0.85, 1))
	# fire: brazier to light arrows through, a chain of crates / barrels to watch fire spread
	_place(g, "prop.brazier.stone", "Brazier_0", c + Vector3(8, 0, -8))
	_place(g, "prop.torch.stone", "YardTorch_0", c + Vector3(8, 0, 8))
	for i in 4:
		_place(g, "prop.crate.wood", "YardCrate_%d" % i, c + Vector3(3 - i * 1.7, 0, -8 + i * 0.3), i * 0.3, 15.0)
	_place(g, "prop.barrel.wood", "YardBarrel_0", c + Vector3(-4.6, 0, -6.6), 0.0, 15.0)
	_place(g, "prop.barrel.wood", "YardBarrel_1", c + Vector3(-5.4, 0, -5.4), 0.0, 15.0)
	_place(g, "prop.shack.wood", "YardShack", c + Vector3(-10, 0, -13), 0.0, 25.0)
	# ice: melt it with fire, shatter it with blunt hits
	for i in 3:
		_place(g, "prop.ice.block", "YardIce_%d" % i, c + Vector3(6 - i * 3.0, 0, 7 + (i % 2) * 1.5), 0.0, 5.0)
	# wading pool: walk in to get Wet (then try shock on yourself... carefully)
	var wp := c + Vector3(-8, 0, 10)
	var wsize := Vector2(9, 7)
	var stone := Color(0.6, 0.58, 0.54)
	for side in [-1, 1]:
		_box(g, wp + Vector3(side * (wsize.x * 0.5 + 0.25), 0.3, 0), Vector3(0.5, 0.6, wsize.y + 1.0), stone)
	_box(g, wp + Vector3(0, 0.3, -(wsize.y * 0.5 + 0.25)), Vector3(wsize.x, 0.6, 0.5), stone)    # open on the +z side
	Water.add_rect_body(Vector2(wp.x, wp.z), wsize * 0.5, 0.5, "water")
	_water_plane(g, wp + Vector3(0, 0.5, 0), wsize)
	_sign(g, wp + Vector3(0, 0, -wsize.y * 0.5 - 1.5), "WADE: WET", Color(0.55, 0.75, 1), 64)
	# trees to burn / chop / grapple, and dummies to try statuses on
	var trees := [["tree_oak_b", Vector3(-16, 0, 2)], ["tree_birch", Vector3(-17, 0, 7)], ["tree_pine", Vector3(-14, 0, 13)],
		["tree_autumn", Vector3(-18, 0, -4)]]
	for i in trees.size():
		_tree(g, str(trees[i][0]), "YardTree_%d" % i, c + (trees[i][1] as Vector3), i * 1.3, 1.0)
	for i in 2:
		var d := AssetRegistry.instantiate(dummy_id)
		d.name = "YardDummy_%d" % i
		g.add_child(d)
		d.position = c + Vector3(4 + i * 3, 0, 2)
		d.look_at(Vector3(c.x + 20, 0, c.z), Vector3.UP)


func _water_plane(parent: Node, at: Vector3, size: Vector2) -> void:
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://assets/shaders/water.gdshader")
	water.material_override = wm
	parent.add_child(water)
	water.position = at


# ================================================================ TRAVERSAL
func _build_traversal() -> void:
	var g := _group("Traversal")
	_sign(g, course_center + Vector3(-6, 0, -12), "TRAVERSAL", Color(0.7, 1, 0.65))
	# move the scene's course blocks here (they keep their shapes / materials)
	var off := course_center - Vector3(0, 0, -22)          # the platform used to sit at (0, 1.5, -22)
	for n in ["Platform", "Ramp", "Step1", "Step2", "Step3", "GrapplePillar"]:
		var b := get_node_or_null("Course/" + n) as Node3D
		if b:
			b.position += Vector3(off.x, 0, off.z)
	for n in ["CoverLeft", "CoverRight"]:
		var b := get_node_or_null("Course/" + n) as Node3D
		if b:
			b.position = dummy_field + (Vector3(-10, 0.6, -12) if n == "CoverLeft" else Vector3(10, 0.6, 12))
	_keep_out(course_center + Vector3(0, 0, 6), Vector2(36, 26))
	var d := AssetRegistry.instantiate(dummy_id)
	d.name = "Dummy_Platform"
	g.add_child(d)
	d.position = course_center + Vector3(0, 3, 0)
	var dp := AssetRegistry.instantiate(dummy_id)
	dp.name = "Dummy_Pillar"
	g.add_child(dp)
	var pillar := get_node_or_null("Course/GrapplePillar") as Node3D
	dp.position = (pillar.position if pillar else course_center) + Vector3(0, 4, 0)
	_build_pool(g)
	_build_sand(g)
	_build_secret_test(g)


## Raised stone pool: deep enough to swim and dive, stairs up the side, a ramp out of the water.
func _build_pool(parent: Node) -> void:
	var g := Node3D.new()
	g.name = "Pool"
	parent.add_child(g)
	var c := pool_center
	_keep_out(c, pool_size + Vector2(12, 6))
	var wall_h := pool_depth + 0.6
	var stone := Color(0.62, 0.6, 0.56)
	var hx := pool_size.x * 0.5
	var hz := pool_size.y * 0.5
	for side in [-1, 1]:
		_box(g, c + Vector3(side * (hx + 0.5), wall_h * 0.5, 0), Vector3(1.0, wall_h, pool_size.y + 2.0), stone)
		_box(g, c + Vector3(0, wall_h * 0.5, side * (hz + 0.5)), Vector3(pool_size.x, wall_h, 1.0), stone)
	var steps := int(ceil(wall_h / 0.5))
	for k in steps:                                   # stairs up the outside of the west wall: tallest against it
		var h := (steps - k) * 0.5
		_box(g, c + Vector3(-hx - 1.3 - k * 0.6, h * 0.5, -hz + 2.0), Vector3(0.6, h, 2.4), stone)
	var ramp := _box(g, c + Vector3(hx - 2.0, pool_depth * 0.5 - 0.2, hz - 3.5), Vector3(3.0, 0.4, 7.5), stone)
	ramp.rotation.x = -atan2(pool_depth, 7.0)
	var level := c.y + pool_depth
	Water.add_rect_body(Vector2(c.x, c.z), Vector2(hx, hz), level, "water")
	_water_plane(g, Vector3(c.x, level, c.z), pool_size)
	_sign(g, c + Vector3(-hx - 6, 0, -hz + 6), "SWIM / DIVE / ICE", Color(0.55, 0.75, 1), 64)


## Sand patch with dunes (Sandspire pillars, bombs, traps).
func _build_sand(parent: Node) -> void:
	var g := Node3D.new()
	g.name = "Sand"
	parent.add_child(g)
	_keep_out(sand_center, sand_size + Vector2(4, 4))
	var sand := Color(0.88, 0.76, 0.52)
	_box(g, sand_center + Vector3(0, 0.05, 0), Vector3(sand_size.x, 0.1, sand_size.y), sand, "sand")
	var dunes := [[Vector3(-4, 0, -3), Vector3(5, 1.2, 3)], [Vector3(3, 0, 4), Vector3(4, 0.8, 5)], [Vector3(4, 0, -5), Vector3(3, 1.8, 3)]]
	for dn in dunes:
		var o: Vector3 = dn[0]
		var sz: Vector3 = dn[1]
		var b := _box(g, sand_center + o + Vector3(0, sz.y * 0.5, 0), sz, sand.darkened(0.06), "sand")
		b.rotation.y = o.x * 0.2
	_rock(g, "rock_sand", "SandRock_0", sand_center + Vector3(-7, 0, 6), 0.3, 1.2)
	_decor(g, "cactus", sand_center + Vector3(6, 0.1, 7), 0.5, 1.0)
	_sign(g, sand_center + Vector3(0, 0, -sand_size.y * 0.5 - 1.5), "SAND", Color(1, 0.85, 0.55), 64)


## Bombable wall to test: a secret cave (the doorway is the only way in) with a legendary chest.
const CaveScript := preload("res://scenes/props/world/cave.gd")


func _build_secret_test(parent: Node) -> void:
	var c := stash_test_pos
	_keep_out(c, Vector2(18, 18))
	var cave := CaveScript.new()
	cave.name = "TestCave"
	cave.tier = "legendary"
	parent.add_child(cave)
	cave.position = c
	cave.rotation.y = PI                                          # door faces the course (-Z)
	for m in cave.find_children("*", "Marker3D", true, false):
		if m.is_in_group("secret_spots"):
			var chest := ChestScript.new()
			chest.name = "TestSecretChest"
			chest.tier = "legendary"
			chest.loot_pool = ["skytether", "greatsword_emberfang", "maul_quakeheart", "bomb_blastgourd", "rod_rimecaller"]
			chest.rolls = Vector2i(2, 3)
			parent.add_child(chest)
			chest.global_position = (m as Node3D).global_position
			chest.global_rotation.y = (m as Node3D).global_rotation.y
	_sign(parent, c + Vector3(-7, 0, -6), "BOMB / HAMMER THE DOOR", Color(1, 0.7, 0.5), 64)


# ================================================================ paths + nature
## Flagstone paths from the hub out to each district.
func _build_paths() -> void:
	var g := _group("Paths")
	var rng := RandomNumberGenerator.new()
	rng.seed = decor_seed + 2
	var ends := [Vector3(0, 0, armory_rows[0] + 4), lane_start + Vector3(-3, 0, 0),
		yard_center + Vector3(14, 0, 0), course_center + Vector3(0, 0, -12)]
	var k := 0
	for e: Vector3 in ends:
		var from: Vector3 = e.normalized() * hub_radius
		var steps := int(from.distance_to(e) / 1.4)
		for i in steps:
			var p := from.lerp(e, float(i) / float(maxi(steps, 1)))
			var side := Vector3(-(e - from).z, 0, (e - from).x).normalized()
			for w in [-0.7, 0.7]:
				_decor(g, ["flagstone_a", "flagstone_b", "flagstone_c"][k % 3],
					p + side * w + Vector3(rng.randf_range(-0.15, 0.15), 0.01, rng.randf_range(-0.15, 0.15)),
					rng.randf() * TAU, 1.1)
				k += 1
			_keep_out(p, Vector2(3, 3))


## Trees and rocks round the edge, grass / flowers / bushes everywhere that's free.
func _scatter_nature() -> void:
	var g := _group("Nature")
	var rng := RandomNumberGenerator.new()
	rng.seed = decor_seed
	var trees := ["tree_oak_b", "tree_oak_c", "tree_birch", "tree_pine", "tree_autumn", "tree_pine_small"]
	var rocks := ["rock_boulder_a", "rock_boulder_b", "rock_mossy", "rock_cluster", "rock_slab"]
	var decor := ["grass_tuft_a", "grass_tuft_b", "grass_tall", "flowers_blue", "flowers_red", "flowers_white",
		"flowers_yellow", "fern", "bush_round", "bush_berry", "mushrooms"]
	var taken: Array[Vector2] = []
	var edge := arena_half - 4.0
	# a forest ring
	var n_tree := 0
	for i in 600:
		if n_tree >= 70:
			break
		var a := rng.randf() * TAU
		var r := rng.randf_range(edge - 16.0, edge)
		var p := Vector2(cos(a), sin(a)) * r
		p.x = clampf(p.x, -edge, edge)
		p.y = clampf(p.y, -edge, edge)
		if _blocked(p, taken, 5.0):
			continue
		taken.append(p)
		_tree(g, trees[n_tree % trees.size()], "EdgeTree_%d" % n_tree, Vector3(p.x, 0, p.y), rng.randf() * TAU,
			rng.randf_range(0.9, 1.3), 45.0)
		n_tree += 1
	var n_rock := 0
	for i in 300:
		if n_rock >= 22:
			break
		var p := Vector2(rng.randf_range(-edge, edge), rng.randf_range(-edge, edge))
		if p.length() < hub_radius + 6.0 or _blocked(p, taken, 6.0):
			continue
		taken.append(p)
		_rock(g, rocks[n_rock % rocks.size()], "Rock_%d" % n_rock, Vector3(p.x, 0, p.y), rng.randf() * TAU,
			rng.randf_range(0.8, 1.5))
		n_rock += 1
	# ground cover (no collision): clumps
	for i in 140:
		var center := Vector2(rng.randf_range(-edge, edge), rng.randf_range(-edge, edge))
		if _blocked(center, [], 0.0):
			continue
		var kind: String = decor[rng.randi() % decor.size()]
		for j in rng.randi_range(2, 5):
			var p := center + Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6))
			if _blocked(p, [], 0.0):
				continue
			_decor(g, kind, Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.8, 1.3))


func _blocked(p: Vector2, taken: Array, gap: float) -> bool:
	for r: Rect2 in _keep:
		if r.grow(1.0).has_point(p):
			return true
	for t: Vector2 in taken:
		if t.distance_to(p) < gap:
			return true
	return false
