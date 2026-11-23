extends Node3D
## Thrown boomerang (Gyrewing). Spawned by Equipment.
##  • No targets: flies at the aim point, turns back after out_time (OoT En_Boom).
##  • Picked targets (hold-LMB multi-aim): visits them in order, homing harder between
##    them, then comes home. Torches count as targets: passing through any flame sets
##    it on fire and every hit after that is a fire hit.
##  • Hitting anything that isn't one of its targets bounces it home early (OoT).
## Returns to the thrower through walls (OoT). Owner copy deals hits; remote copies
## fly the same path for visuals / wobble only (cosmetic).

signal caught
signal hit(collider: Object, position: Vector3, damage: float)

const FX := preload("res://systems/components/element_fx.gd")

@export var model_id := "weapon.boomerang.basic"
@export var collision_mask := 3            ## 1 = world, 2 = players
@export var model_tilt_deg := 12.0         ## slight bank while spinning

var cosmetic := false
var stats: Resource
var thrower: Node3D
var targets: Array[Node3D] = []
var aim_point := Vector3.ZERO
var velocity := Vector3.ZERO
var returning := false
var element := ""

var _age := 0.0
var _out_age := 0.0
var _ti := 0
var _target_time := 0.0
var _spin: Node3D
var _shape := SphereShape3D.new()
var _hit_ids: Dictionary = {}
var _exclude: Array[RID] = []
var _flames: Node3D


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


func launch(from: Vector3, aim: Vector3, tgts: Array[Node3D], s: Resource, thrower_body: Node3D) -> void:
	stats = s
	thrower = thrower_body
	targets = tgts
	aim_point = aim
	_shape.radius = s.hit_radius
	_exclude = [thrower_body.get_rid()]
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
	var before := global_position
	if returning:
		_fly_back(delta)
	else:
		_fly_out(delta)
	if element != "fire" and WorldRules.fire_zone_on_segment(get_world_3d(), before, global_position):
		_set_element("fire")


func _fly_out(delta: float) -> void:
	_out_age += delta
	var goal := aim_point
	if _ti < targets.size():
		var t := targets[_ti]
		if not _target_ok(t):
			_advance()
			return
		goal = t.get_lock_point()
		_target_time += delta
		if global_position.distance_to(goal) <= stats.reach_radius:
			_strike(t, goal)
			_advance()
			return
		if _target_time > stats.per_target_timeout:
			_advance()
			return
		_steer_toward(goal, delta, stats.multi_steer_min if targets.size() > 1 else stats.steer_min)
	elif goal.distance_to(global_position) <= stats.speed * delta:
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
	q.exclude = _exclude
	var frac := space.cast_motion(q)
	if frac[1] < 1.0:
		q.transform.origin = global_position + motion * frac[1]
		q.motion = Vector3.ZERO
		var info := space.get_rest_info(q)
		global_position += motion * frac[0]
		if info.is_empty():
			_begin_return()
			return
		var col := instance_from_id(info.collider_id)
		var owner_target := _target_owning(col)
		_strike_collider(col, info.point)
		_exclude.append(info.rid)                 # fly on through it next step
		if owner_target == null:
			_begin_return()                       # OoT: bounce home off anything else
		elif _ti < targets.size() and targets[_ti] == owner_target:
			_advance()
		return
	global_position += motion
	if targets.is_empty() and _out_age >= stats.out_time:
		_begin_return()


func _fly_back(delta: float) -> void:
	var hand := thrower.global_position + Vector3.UP * 1.3
	if global_position.distance_to(hand) <= stats.catch_radius:
		_catch()
		return
	_steer_toward(hand, delta, stats.steer_min)
	global_position += velocity * delta


## OoT steering: close a fraction of the angle each 1/20 s, more when close.
func _steer_toward(goal: Vector3, delta: float, min_frac: float) -> void:
	var to := goal - global_position
	var dist := to.length()
	if dist < 0.001:
		return
	var f := clampf((stats.steer_near_distance - dist) / stats.steer_near_distance, min_frac, 1.0)
	var k := 1.0 - pow(1.0 - f, delta * 20.0)
	var dir := velocity.normalized().slerp(to / dist, k)
	velocity = dir.normalized() * stats.speed


func _advance() -> void:
	_ti += 1
	_target_time = 0.0
	if _ti >= targets.size():
		_begin_return()


func _begin_return() -> void:
	returning = true


func _target_ok(t: Node3D) -> bool:
	return is_instance_valid(t) and t.is_inside_tree() and not (t.has_method("is_lockable") and not t.is_lockable())


## Which picked target (if any) a collider belongs to.
func _target_owning(col: Object) -> Node3D:
	for t in targets:
		if is_instance_valid(t) and (col == t or (col is Node and t.is_ancestor_of(col))):
			return t
	return null


func _strike(t: Node3D, point: Vector3) -> void:
	var col: Object = t
	if not (t is CollisionObject3D):
		var body := t.find_children("*", "CollisionObject3D", true, false)
		if body.size() > 0:
			col = body[0]
	_strike_collider(col, point)


func _strike_collider(col: Object, point: Vector3) -> void:
	if col == null or _hit_ids.has(col.get_instance_id()):
		return
	_hit_ids[col.get_instance_id()] = true
	if col.has_method("blocks_hit") and col.blocks_hit(velocity.normalized()):
		col.on_blocked(point)
		_begin_return()
		return
	var hit_info := WorldRules.make_hit(stats.damage, "blunt", element, velocity.normalized())
	if not WorldRules.deliver_hit(col, hit_info, cosmetic):
		Audio.play_at("arrow.hit", point, -3.0, 1.3)
	if not cosmetic:
		hit.emit(col, point, hit_info.damage)
		print("[boomerang] hit %s (%s dmg %.0f)" % [(col as Node).name if col is Node else "?",
			element if element != "" else "plain", hit_info.damage])


func _set_element(e: String) -> void:
	element = e
	if e == "fire" and _flames == null:
		_flames = FX.flames(0.45, true)
		add_child(_flames)
		Audio.play_at("fire.ignite", global_position, -4.0, 1.2)
		if not cosmetic:
			print("[boomerang] caught fire")


func _catch() -> void:
	caught.emit()
	queue_free()
