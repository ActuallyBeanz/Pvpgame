extends Node3D
## Thrown boomerang. Outbound: flies at the aim point, or homes in on a locked target.
## Turns back after out_time or on hitting anything, then homes back to the thrower
## (ignoring walls, like OoT) and is caught when close. Spawned by Equipment.
## Owner copy deals hits; remote copies are cosmetic (same path, same wobble reactions).

signal caught
signal hit(collider: Object, position: Vector3, damage: float)

@export var model_id := "weapon.boomerang.basic"
@export var collision_mask := 3            ## 1 = world, 2 = players
@export var model_tilt_deg := 12.0         ## slight bank while spinning

var cosmetic := false
var stats: Resource
var thrower: Node3D
var target: Node3D
var aim_point := Vector3.ZERO
var velocity := Vector3.ZERO
var returning := false

var _age := 0.0
var _out_age := 0.0
var _spin: Node3D
var _shape := SphereShape3D.new()
var _hit_ids: Dictionary = {}


func _ready() -> void:
	_spin = Node3D.new()
	add_child(_spin)
	var vis := AssetRegistry.instantiate(model_id)
	vis.rotation_degrees.x = model_tilt_deg
	_spin.add_child(vis)
	var light := OmniLight3D.new()            # small glint so it reads in flight
	light.light_color = Color(0.5, 1.0, 0.95)
	light.light_energy = 0.6
	light.omni_range = 1.5
	add_child(light)
	Audio.attach_loop("boomerang.spin", self)


func launch(from: Vector3, aim: Vector3, tgt: Node3D, s: Resource, thrower_body: Node3D) -> void:
	stats = s
	thrower = thrower_body
	target = tgt
	aim_point = aim
	_shape.radius = s.hit_radius
	global_position = from
	var dir := (aim - from)
	velocity = (dir.normalized() if dir.length() > 0.01 else -thrower_body.global_basis.z) * s.speed
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if stats == null:
		return
	_age += delta
	_spin.rotate_y(stats.spin_speed * delta)
	if not is_instance_valid(thrower):
		queue_free()
		return
	if _age > stats.max_flight_time:
		if returning:
			_catch()
			return
		_begin_return()
	if returning:
		_fly_back(delta)
	else:
		_fly_out(delta)


func _fly_out(delta: float) -> void:
	_out_age += delta
	var locked := is_instance_valid(target) and target.has_method("get_lock_point")
	var goal: Vector3 = target.get_lock_point() if locked else aim_point
	var to_goal := goal - global_position
	if locked:
		_steer_toward(goal, delta)
	elif to_goal.length() <= stats.speed * delta:
		global_position = goal
		_begin_return()
		return
	var motion := velocity * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis(), global_position)
	q.motion = motion
	q.collision_mask = collision_mask
	q.exclude = [thrower.get_rid()]
	var frac := space.cast_motion(q)
	if frac[1] < 1.0:
		q.transform.origin = global_position + motion * frac[1]
		q.motion = Vector3.ZERO
		var info := space.get_rest_info(q)
		global_position += motion * frac[0]
		if not info.is_empty():
			_on_hit(instance_from_id(info.collider_id), info.point)
		_begin_return()
		return
	global_position += motion
	if _out_age >= stats.out_time:
		_begin_return()


func _fly_back(delta: float) -> void:
	var hand := thrower.global_position + Vector3.UP * 1.3
	if global_position.distance_to(hand) <= stats.catch_radius:
		_catch()
		return
	_steer_toward(hand, delta)
	global_position += velocity * delta


## OoT steering: close a fraction of the angle each 1/20 s, more when close.
func _steer_toward(goal: Vector3, delta: float) -> void:
	var to := goal - global_position
	var dist := to.length()
	if dist < 0.001:
		return
	var f := clampf((stats.steer_near_distance - dist) / stats.steer_near_distance, stats.steer_min, 1.0)
	var k := 1.0 - pow(1.0 - f, delta * 20.0)
	var dir := velocity.normalized().slerp(to / dist, k)
	velocity = dir.normalized() * stats.speed


func _begin_return() -> void:
	returning = true


func _on_hit(col: Object, point: Vector3) -> void:
	if col == null or _hit_ids.has(col.get_instance_id()):
		return
	_hit_ids[col.get_instance_id()] = true
	var hit_info := WorldRules.make_hit(stats.damage, "blunt", "", velocity.normalized())
	if not WorldRules.deliver_hit(col, hit_info, cosmetic):
		Audio.play_at("arrow.hit", point, -3.0, 1.3)
	if not cosmetic:
		hit.emit(col, point, stats.damage)
		print("[boomerang] hit %s" % ((col as Node).name if col is Node else "?"))


func _catch() -> void:
	caught.emit()
	queue_free()
