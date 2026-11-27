extends Node3D
## Test arena: movement playground until the M3 map greybox exists.
## Host spawns one player per roster entry once every peer has loaded.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
var allow_respawn := true                 ## test area: you come back a few seconds after dying

@export var demo_prop_ids: PackedStringArray = [
	"prop.crate.wood", "env.tree.oak_a", "env.rock.basic", "env.wall.cracked",
]
@export var demo_prop_radius := 22.0

@export_group("Reaction yard")
## Brazier + crate chain + ice: shoot through the brazier to light arrows, burn the
## crates, watch fire spread and melt the ice. Boomerang the lone ice block to shatter it.
@export var yard_items: Array[Dictionary] = [
	{ "id": "prop.brazier.stone", "pos": Vector3(12, 0, 4.6) },
	{ "id": "prop.crate.wood", "pos": Vector3(16.0, 0, 6.0) },
	{ "id": "prop.crate.wood", "pos": Vector3(17.6, 0, 6.5) },
	{ "id": "prop.crate.wood", "pos": Vector3(19.2, 0, 7.0) },
	{ "id": "prop.ice.block", "pos": Vector3(19.0, 0, 9.4), "respawn": 5.0 },
	{ "id": "prop.ice.block", "pos": Vector3(13.5, 0, 11.5), "respawn": 5.0 },
]

@export_group("Weapon lane")
## In front of the item stands: a torch and three slightly offset dummies, to try the
## boomerang's multi-target throw (pick the torch first for fire hits) and the sword.
@export var lane_items: Array[Dictionary] = [
	{ "id": "prop.torch.stone", "pos": Vector3(-3.5, 0, 10.0) },
	{ "id": "prop.target.dummy", "pos": Vector3(-1.5, 0, 14.0) },
	{ "id": "prop.target.dummy", "pos": Vector3(1.2, 0, 15.3) },
	{ "id": "prop.target.dummy", "pos": Vector3(4.0, 0, 13.6) },
]
@export var lane_face_point := Vector3(0, 0, 3.5)

@export_group("Item stands")
const PickupScene := preload("res://scenes/items/pickup.tscn")
## Test area: one of every item on the ground, never runs out (take again for more ammo).
@export var item_stands: Array[Dictionary] = [
	{ "id": "bow_basic", "pos": Vector3(-5.0, 0, 3.5) },
	{ "id": "arrows", "pos": Vector3(-2.5, 0, 3.5) },
	{ "id": "boomerang_basic", "pos": Vector3(0.0, 0, 3.5) },
	{ "id": "sword_dawnsteel", "pos": Vector3(2.5, 0, 3.5) },
	{ "id": "shield_gildcrest", "pos": Vector3(5.0, 0, 3.5) },
	{ "id": "grappleclaw", "pos": Vector3(-7.5, 0, 3.5) },
	{ "id": "skytether", "pos": Vector3(-10.0, 0, 3.5) },
	]

@export_group("Water + sand (tool / swimming tests)")
## Raised pool (walls you can walk up on stairs) with deep water: swim, dive, freeze ice bridges.
@export var pool_center := Vector3(27, 0, -27)
@export var pool_size := Vector2(16, 16)
@export var pool_depth := 3.2                  ## water depth (walls are a little taller)
## Sand patch with dunes next to it (Sandspire pillars, bombs, traps).
@export var sand_center := Vector3(-27, 0, -27)
@export var sand_size := Vector2(16, 16)

@export_group("Targets")
@export var target_id := "prop.target.archery"
@export var target_positions: PackedVector3Array = [Vector3(10, 0, -6), Vector3(20, 0, -2), Vector3(32, 0, 2.5)]

@export_group("Training dummies")
@export var dummy_id := "prop.target.dummy"
## Spread across the course: open ground, behind cover, on the platform, behind
## the steps, in the grove, out by the tree ring, and on top of the purple grapple pillar.
@export var dummy_positions: PackedVector3Array = [
	Vector3(-6, 0, -6), Vector3(7, 0, 5), Vector3(-8, 0, 12.5), Vector3(0, 3, -22),
	Vector3(12, 0, -18), Vector3(-15, 0, 15), Vector3(-24, 0, -8), Vector3(22, 0, 16),
	Vector3(-12, 0, -16), Vector3(26, 0, -14), Vector3(-12, 8, -12),
]

@export_group("Trees")
@export var tree_id := "env.tree.oak_a"
@export var tree_seed := 42                       ## same seed = same layout on every peer
@export var outer_tree_count := 26
@export var outer_ring := Vector2(27.0, 38.0)     ## min / max distance from centre
@export var grove_center := Vector3(-15.0, 0.0, 17.0)
@export var grove_count := 6
@export var grove_radius := 5.0
@export var tree_spacing := 4.0                   ## minimum gap between trunks
@export var tree_scale_range := Vector2(0.85, 1.2)

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var overview_camera: Camera3D = $OverviewCamera


func _ready() -> void:
	spawner.spawn_function = _build_player
	overview_camera.look_at_from_position(Vector3(0, 22, 26), Vector3.ZERO)
	_place_demo_props()
	_place_reaction_yard()
	_place_weapon_lane()
	_place_targets()
	_place_dummies()
	_place_pickups()
	Water.clear()
	_build_pool()
	_build_sand()
	_place_trees()
	if multiplayer.is_server():
		Lobby.all_peers_loaded.connect(_spawn_all_players, CONNECT_ONE_SHOT)
		NetworkManager.peer_disconnected.connect(_on_peer_left)
	Lobby.report_match_loaded()
	Audio.play_ambience("amb.field")
	Audio.play("ui.match_start")
	tree_exiting.connect(func() -> void:
		Audio.stop_ambience(0.3)
		Water.clear())


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


# Local-only scenery (identical on every peer) to eyeball Asset Registry placeholders.
func _place_demo_props() -> void:
	var count := demo_prop_ids.size() * 3
	for i in count:
		var prop := AssetRegistry.instantiate(demo_prop_ids[i % demo_prop_ids.size()])
		prop.name = "Prop_%d" % i  # fixed names: Reactive props sync by node path
		var angle := TAU * (i + 0.5) / count
		prop.position = Vector3(cos(angle), 0.0, sin(angle)) * demo_prop_radius
		prop.rotation.y = -angle
		$Props.add_child(prop)


# Local-only scenery, deterministic from tree_seed so every peer sees the same trees.
func _place_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var taken: Array[Vector3] = []
	for p in $Props.get_children():
		taken.append((p as Node3D).position)
	for c in $Course.get_children():
		taken.append(Vector3((c as Node3D).position.x, 0.0, (c as Node3D).position.z))
	for p in get_tree().get_nodes_in_group("pickups"):
		taken.append((p as Node3D).position)
	var spots: Array[Vector3] = []
	for i in outer_tree_count * 8:
		if spots.size() >= outer_tree_count:
			break
		var a := rng.randf() * TAU
		var r := rng.randf_range(outer_ring.x, outer_ring.y)
		_try_spot(Vector3(cos(a) * r, 0.0, sin(a) * r), taken, spots, outer_tree_count)
	var grove: Array[Vector3] = []
	for i in grove_count * 10:
		if grove.size() >= grove_count:
			break
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * grove_radius
		_try_spot(grove_center + Vector3(cos(a) * r, 0.0, sin(a) * r), taken, grove, grove_count)
	spots.append_array(grove)
	for i in spots.size():
		var pos := spots[i]
		var tree := AssetRegistry.instantiate(tree_id)
		tree.name = "Tree_%d" % i
		tree.position = pos
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(tree_scale_range.x, tree_scale_range.y)
		$Props.add_child(tree)


func _try_spot(pos: Vector3, taken: Array[Vector3], out: Array[Vector3], limit: int) -> void:
	if out.size() >= limit:
		return
	for c in [[pool_center, pool_size], [sand_center, sand_size]]:     # keep the pool / sand clear
		var cc: Vector3 = c[0]
		var sz: Vector2 = c[1]
		if absf(pos.x - cc.x) < sz.x * 0.5 + 4.0 and absf(pos.z - cc.z) < sz.y * 0.5 + 4.0:
			return
	for t in taken:
		if Vector2(t.x - pos.x, t.z - pos.z).length() < tree_spacing:
			return
	taken.append(pos)
	out.append(pos)


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


## Raised stone pool: deep enough to swim and dive, stairs up the side, a ramp out of the water.
func _build_pool() -> void:
	var g := Node3D.new()
	g.name = "Pool"
	$Course.add_child(g)
	var c := pool_center
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
	# a ramp inside so swimmers can walk back out
	var ramp := _box(g, c + Vector3(hx - 2.0, pool_depth * 0.5 - 0.2, hz - 3.5), Vector3(3.0, 0.4, 7.5), stone)
	ramp.rotation.x = -atan2(pool_depth, 7.0)
	var level := c.y + pool_depth
	Water.add_rect_body(Vector2(c.x, c.z), Vector2(hx, hz), level, "water")
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = pool_size
	pm.subdivide_width = 16
	pm.subdivide_depth = 16
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://assets/shaders/water.gdshader")
	water.material_override = wm
	g.add_child(water)
	water.position = Vector3(c.x, level, c.z)


## Sand patch with a few dunes.
func _build_sand() -> void:
	var g := Node3D.new()
	g.name = "Sand"
	$Course.add_child(g)
	var sand := Color(0.88, 0.76, 0.52)
	_box(g, sand_center + Vector3(0, 0.05, 0), Vector3(sand_size.x, 0.1, sand_size.y), sand, "sand")
	var dunes := [[Vector3(-4, 0, -3), Vector3(5, 1.2, 3)], [Vector3(3, 0, 4), Vector3(4, 0.8, 5)], [Vector3(4, 0, -5), Vector3(3, 1.8, 3)]]
	for d in dunes:
		var off: Vector3 = d[0]
		var sz: Vector3 = d[1]
		var b := _box(g, sand_center + off + Vector3(0, sz.y * 0.5, 0), sz, sand.darkened(0.06), "sand")
		b.rotation.y = off.x * 0.2


# Local scenery with fixed names (Reactive state syncs by node path).
func _place_reaction_yard() -> void:
	for i in yard_items.size():
		var item: Dictionary = yard_items[i]
		var prop := AssetRegistry.instantiate(str(item.id))
		prop.name = "Yard_%d" % i
		prop.position = item.pos
		prop.rotation.y = float(item.get("rot", 0.0))
		if item.has("respawn") and prop.has_node("Reactive"):
			prop.get_node("Reactive").respawn_time = float(item.respawn)
		$Props.add_child(prop)


func _place_weapon_lane() -> void:
	for i in lane_items.size():
		var item: Dictionary = lane_items[i]
		var prop := AssetRegistry.instantiate(str(item.id))
		prop.name = "Lane_%d" % i
		$Props.add_child(prop)
		prop.position = item.pos
		var look := Vector3(lane_face_point.x, prop.position.y, lane_face_point.z)
		prop.look_at(look, Vector3.UP)  # dummies face (-Z) the stands


func _place_targets() -> void:
	for pos in target_positions:
		var t := AssetRegistry.instantiate(target_id)
		$Props.add_child(t)
		t.position = pos
		t.look_at(Vector3(0, pos.y, 0) if pos.length() > 0.1 else Vector3.FORWARD, Vector3.UP)
		t.rotate_y(PI)  # board face (+Z) toward the centre


# Local scenery with fixed names so boomerang lock-on RPCs resolve on every peer.
func _place_dummies() -> void:
	for i in dummy_positions.size():
		var pos := dummy_positions[i]
		var d := AssetRegistry.instantiate(dummy_id)
		d.name = "Dummy_%d" % i
		$Props.add_child(d)
		d.position = pos
		var look := Vector3(0, pos.y, 0)
		if Vector2(pos.x, pos.z).length() > 0.1:
			d.look_at(look, Vector3.UP)  # face (-Z) the arena centre


# Fixed infinite stands; same names on every peer so pickup RPC paths match.
func _place_pickups() -> void:
	var root := Node3D.new()
	root.name = "Pickups"
	add_child(root)
	var stands := item_stands.duplicate()
	var listed := {}
	for st in stands:
		listed[str(st.id)] = true
	var extra := 0
	for id in ItemDB.all_ids():                  # anything not placed by hand gets a stand too
		if not listed.has(str(id)):
			stands.append({ "id": str(id), "pos": Vector3(-12.5 + (extra % 10) * 2.5, 0, -2.0 - int(extra / 10) * 2.5) })
			extra += 1
	for i in stands.size():
		var st: Dictionary = stands[i]
		if not ItemDB.has_item(str(st.id)):
			continue
		var pu := PickupScene.instantiate()
		pu.name = "Pickup_%d" % i
		pu.item_id = str(st.id)
		pu.infinite = true
		pu.show_label = true
		pu.position = st.pos
		root.add_child(pu)
