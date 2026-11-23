extends Node
## Hold "focus" (RMB / left trigger) — OoT Z-targeting.
##  • No lock-on weapon: free focus. You turn to face where the camera is pointing and
##    keep that plane while you side-step; the mouse stays free to look around.
##  • A target in range (group "lock_targets", anything with get_lock_point()) locks on
##    with ANY weapon or none: you face it and the camera swings onto it. Whether a
##    weapon then flies to it is the weapon's call (boomerang homes, arrows don't).
##    A weapon's stats can override the range with lock_on_range. Players can join the
##    group later without changing this script.
## Local input only; the player replicates `active` as sync_focus for animations.

signal target_changed(target: Node3D)

const GROUP := "lock_targets"

@export var default_lock_range := 20.0    ## used unless the weapon sets lock_on_range
@export var max_cone_deg := 70.0          ## candidates must be within this of camera forward
@export var break_range_mult := 1.3       ## lock breaks past lock_range * this
@export var require_line_of_sight := true
@export var reticle_color := Color(1.0, 0.82, 0.25)
@export var reticle_height := 0.55        ## above the lock point
@export var reticle_close_time := 0.18    ## triangles close in on acquire

var active := false
var target: Node3D
var free_yaw := 0.0

var _player: CharacterBody3D
var _reticle: Node3D
var _reticle_t := 0.0


func _ready() -> void:
	_player = get_parent()


## Called by player.gd every physics tick on the owning peer.
func update(can_act: bool, weapon_lock_range: float) -> void:
	var lock_range := weapon_lock_range if weapon_lock_range > 0.0 else default_lock_range
	var held := can_act and Input.is_action_pressed("focus")
	if held and not active:
		active = true
		free_yaw = _player.camera_rig.get_yaw()  # turn to where the camera is looking
		_set_target(_find_target(lock_range) if lock_range > 0.0 else null)
	elif not held and active:
		active = false
		_set_target(null)
	elif active and target and not _still_valid(target, lock_range):
		free_yaw = _player.motor.facing
		_set_target(null)


## Where the body should face while focused.
func focus_yaw() -> float:
	if target:
		var d: Vector3 = target.get_lock_point() - _player.global_position
		if Vector2(d.x, d.z).length() > 0.05:
			return atan2(-d.x, -d.z)
	return free_yaw


func lock_point() -> Variant:
	return target.get_lock_point() if target else null


# ---------------------------------------------------------------- targeting
func _eye() -> Vector3:
	return _player.global_position + Vector3.UP * 1.5


func _find_target(lock_range: float) -> Node3D:
	var cam_yaw: float = _player.camera_rig.get_yaw()
	var fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var best: Node3D = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group(GROUP):
		if n == _player or not n.has_method("get_lock_point") or not n.is_inside_tree():
			continue
		var p: Vector3 = n.get_lock_point()
		var to := p - _eye()
		var dist := to.length()
		if dist > lock_range or dist < 0.5:
			continue
		var flat := Vector3(to.x, 0.0, to.z).normalized()
		var ang := rad_to_deg(fwd.angle_to(flat))
		if ang > max_cone_deg:
			continue
		if require_line_of_sight and not _visible(n, p):
			continue
		var score := ang / max_cone_deg + dist / lock_range  # favour what you look at, then nearest
		if score < best_score:
			best_score = score
			best = n
	return best


func _still_valid(n: Node3D, lock_range: float) -> bool:
	if not is_instance_valid(n) or not n.is_inside_tree() or lock_range <= 0.0:
		return false
	if n.has_method("is_lockable") and not n.is_lockable():
		return false
	return _eye().distance_to(n.get_lock_point()) <= lock_range * break_range_mult


func _visible(n: Node3D, p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_eye(), p, 1)
	q.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var c: Object = hit.collider
	return c == n or (c is Node and n.is_ancestor_of(c))


func _set_target(t: Node3D) -> void:
	if t == target:
		return
	target = t
	_reticle_t = 0.0
	if _reticle == null and t:
		_reticle = _build_reticle()
	if _reticle:
		_reticle.visible = t != null
	target_changed.emit(t)


# ---------------------------------------------------------------- reticle (local only)
func _process(delta: float) -> void:
	if _reticle == null or not _reticle.visible or not is_instance_valid(target):
		return
	_reticle_t += delta
	var close := clampf(_reticle_t / reticle_close_time, 0.0, 1.0)
	var radius := lerpf(1.1, 0.32, close * close * (3.0 - 2.0 * close))
	_reticle.global_position = target.get_lock_point() + Vector3.UP * (reticle_height + sin(_reticle_t * 4.0) * 0.05)
	_reticle.rotation.y += delta * 2.5
	for i in _reticle.get_child_count():
		var a := TAU * i / _reticle.get_child_count()
		(_reticle.get_child(i) as Node3D).position = Vector3(cos(a), 0.0, sin(a)) * radius


func _build_reticle() -> Node3D:
	var root := Node3D.new()
	root.name = "LockReticle"
	root.top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = reticle_color
	mat.no_depth_test = true
	mat.render_priority = 10
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.22, 0.26, 0.05)
	for i in 3:
		var tri := MeshInstance3D.new()
		tri.mesh = mesh
		tri.material_override = mat
		tri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.add_child(tri)
		tri.rotation = Vector3(0.0, 0.0, PI)          # point down at the target
		holder.rotation.y = -TAU * i / 3.0 + PI * 0.5  # face outward
		root.add_child(holder)
	get_tree().current_scene.add_child(root)
	return root


func _exit_tree() -> void:
	if is_instance_valid(_reticle):
		_reticle.queue_free()
