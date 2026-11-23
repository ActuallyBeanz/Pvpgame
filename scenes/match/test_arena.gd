extends Node3D
## Test arena: movement playground until the M3 map greybox exists.
## Host spawns one player per roster entry once every peer has loaded.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@export var demo_prop_ids: PackedStringArray = [
	"prop.crate.wood", "env.tree.oak_a", "env.rock.basic", "env.wall.cracked",
]
@export var demo_prop_radius := 22.0

@export_group("Pickups")
const PickupScene := preload("res://scenes/items/pickup.tscn")
@export var pickup_counts: Dictionary[String, int] = { "bow_basic": 4, "arrows": 8, "boomerang_basic": 4 }
@export var pickup_seed := 7
@export var pickup_ring := Vector2(4.0, 20.0)    ## min / max distance from centre
@export var pickup_spacing := 3.0

@export_group("Targets")
@export var target_id := "prop.target.archery"
@export var target_positions: PackedVector3Array = [Vector3(10, 0, -6), Vector3(20, 0, -2), Vector3(32, 0, 2.5)]

@export_group("Training dummies")
@export var dummy_id := "prop.target.dummy"
## Spread across the course: open ground, behind cover, on the platform, behind
## the steps, in the grove, out by the tree ring.
@export var dummy_positions: PackedVector3Array = [
	Vector3(-6, 0, -6), Vector3(7, 0, 5), Vector3(-8, 0, 12.5), Vector3(0, 3, -22),
	Vector3(12, 0, -18), Vector3(-15, 0, 15), Vector3(-24, 0, -8), Vector3(22, 0, 16),
	Vector3(-12, 0, -16), Vector3(26, 0, -14),
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
	_place_targets()
	_place_dummies()
	_place_pickups()
	_place_trees()
	if multiplayer.is_server():
		Lobby.all_peers_loaded.connect(_spawn_all_players, CONNECT_ONE_SHOT)
		NetworkManager.peer_disconnected.connect(_on_peer_left)
	Lobby.report_match_loaded()
	Audio.play_ambience("amb.field")
	Audio.play("ui.match_start")
	tree_exiting.connect(func() -> void: Audio.stop_ambience(0.3))


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
	for pos in spots:
		var tree := AssetRegistry.instantiate(tree_id)
		tree.position = pos
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(tree_scale_range.x, tree_scale_range.y)
		$Props.add_child(tree)


func _try_spot(pos: Vector3, taken: Array[Vector3], out: Array[Vector3], limit: int) -> void:
	if out.size() >= limit:
		return
	for t in taken:
		if Vector2(t.x - pos.x, t.z - pos.z).length() < tree_spacing:
			return
	taken.append(pos)
	out.append(pos)


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


# Same seed on every peer -> same pickups with the same node names (RPC paths match).
func _place_pickups() -> void:
	var root := Node3D.new()
	root.name = "Pickups"
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = pickup_seed
	var taken: Array[Vector3] = []
	for p in $Props.get_children():
		taken.append((p as Node3D).position)
	for c in $Course.get_children():
		taken.append(Vector3((c as Node3D).position.x, 0.0, (c as Node3D).position.z))
	var ids := pickup_counts.keys()
	ids.sort()
	var n := 0
	for id: String in ids:
		for i in pickup_counts[id]:
			for attempt in 40:
				var a := rng.randf() * TAU
				var r := rng.randf_range(pickup_ring.x, pickup_ring.y)
				var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)
				var ok := true
				for t in taken:
					if Vector2(t.x - pos.x, t.z - pos.z).length() < pickup_spacing:
						ok = false
						break
				if not ok:
					continue
				taken.append(pos)
				var pu := PickupScene.instantiate()
				pu.name = "Pickup_%d" % n
				pu.item_id = id
				pu.position = pos
				root.add_child(pu)
				n += 1
				break
