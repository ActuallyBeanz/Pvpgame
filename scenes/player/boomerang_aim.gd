extends Node
## Boomerang multi-target aim (owner only). Hold LMB with the boomerang drawn:
## every target in range gets yellow triangles; sweep the crosshair over one to
## select it (triangles turn red). Release to throw: it visits them in the order
## you picked, then comes back. Torches can be picked too (flying through the flame
## sets the boomerang on fire for the targets after it).
## Groups: "lock_targets" (dummies, players later) + "boomerang_targets" (torches).

const LockReticle := preload("res://scenes/player/lock_reticle.gd")
const GROUPS := ["lock_targets", "boomerang_targets"]

@export var candidate_color := Color(1.0, 0.82, 0.25)
@export var selected_color := Color(1.0, 0.22, 0.15)
@export var select_radius_px := 70.0      ## at 1080p; scaled with screen height
@export var max_cone_deg := 75.0
@export var select_delay := 0.3           ## ignore picks while the aim camera swings in

var active := false
var selected: Array[Node3D] = []

var _player: CharacterBody3D
var _markers: Dictionary = {}             ## Node3D -> reticle
var _since := 0.0


func setup(player: CharacterBody3D) -> void:
	_player = player


func begin(preselect: Node3D) -> void:
	active = true
	_since = 0.0
	selected.clear()
	if preselect:
		_select(preselect)


## Each frame while aiming. Returns nothing; read `selected`.
func update(lock_range: float, max_targets: int) -> void:
	if not active:
		return
	_since += get_process_delta_time()
	var cam: Camera3D = _player.camera_rig.camera
	var vp := _player.get_viewport()
	var size := vp.get_visible_rect().size
	var centre := size * 0.5
	var radius := select_radius_px * size.y / 1080.0
	var seen := {}
	for n in _candidates(cam, lock_range):
		seen[n] = true
		_marker(n)
		if _since >= select_delay and selected.size() < max_targets and not selected.has(n):
			var sp := cam.unproject_position(n.get_lock_point())
			if sp.distance_to(centre) <= radius:
				_select(n)
	for n in _markers.keys():
		if not seen.has(n) and not selected.has(n):
			_drop_marker(n)


func end() -> Array[Node3D]:
	active = false
	var out: Array[Node3D] = []
	for n in selected:
		if is_instance_valid(n):
			out.append(n)
	selected.clear()
	for n in _markers.keys():
		_drop_marker(n)
	return out


func _select(n: Node3D) -> void:
	selected.append(n)
	var m := _marker(n)
	m.set_color(selected_color)
	m.pulse()
	Audio.play("ui.hover", 2.0, 0.8 + 0.12 * selected.size())
	print("[boomerang] selected %s (%d)" % [n.name, selected.size()])


func _marker(n: Node3D) -> Node3D:
	if not _markers.has(n) or not is_instance_valid(_markers[n]):
		var m := LockReticle.create(get_tree().current_scene, candidate_color, 0.85)
		m.follow(n)
		_markers[n] = m
	return _markers[n]


func _drop_marker(n: Variant) -> void:
	var m: Variant = _markers.get(n)
	if is_instance_valid(m):
		(m as Node).queue_free()
	_markers.erase(n)


func _candidates(cam: Camera3D, lock_range: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var eye := _player.global_position + Vector3.UP * 1.5
	var fwd := -cam.global_basis.z
	for g in GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			if n == _player or out.has(n) or not (n is Node3D) or not n.has_method("get_lock_point"):
				continue
			if n.has_method("is_lockable") and not n.is_lockable():
				continue
			var p: Vector3 = n.get_lock_point()
			var to := p - eye
			if to.length() > lock_range or to.length() < 0.8:
				continue
			if rad_to_deg(fwd.angle_to(p - cam.global_position)) > max_cone_deg:
				continue
			if not _visible(n, eye, p):
				continue
			out.append(n)
	return out


func _visible(n: Node3D, from: Vector3, p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, p, 1)
	q.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var c: Object = hit.collider
	return c == n or (c is Node and n.is_ancestor_of(c))


func _exit_tree() -> void:
	for n in _markers.keys():
		_drop_marker(n)
