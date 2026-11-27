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
const LockReticle := preload("res://scenes/player/lock_reticle.gd")

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
	if preload("res://systems/element_impacts.gd").smoke_blocks(get_tree(), _eye(), p):
		return false                                  # can't lock on through Smolderpuff smoke
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
	if _reticle == null and t:
		_reticle = LockReticle.create(get_tree().current_scene, reticle_color)
		_reticle.height = reticle_height
		_reticle.close_time = reticle_close_time
	if _reticle:
		_reticle.follow(t)
	target_changed.emit(t)


func _exit_tree() -> void:
	if is_instance_valid(_reticle):
		_reticle.queue_free()
