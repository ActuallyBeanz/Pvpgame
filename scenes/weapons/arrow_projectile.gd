extends Node3D
## Ballistic arrow: gravity + drag, swept raycast each physics step (no tunnelling),
## sticks into whatever it hits. Spawned by Equipment via launch().
## Model points -Z with its origin at the tip, so it embeds nicely on hit.

signal hit(collider: Object, position: Vector3, damage: float)

@export var collision_mask := 3            ## 1 = world, 2 = players
@export var embed_depth := 0.12            ## how far the tip sinks into a surface
@export var model_id := "weapon.arrow.basic"

var velocity := Vector3.ZERO
var gravity := 14.0
var drag := 0.08
var lifetime := 6.0
var stick_time := 12.0
var damage := 0.0
var shooter_rid := RID()
var cosmetic := false                      ## remote copies: visuals only, no damage

var _age := 0.0
var _stuck := false


func _ready() -> void:
	add_child(AssetRegistry.instantiate(model_id))


func launch(from: Vector3, vel: Vector3, stats: Resource, dmg: float, shooter: RID) -> void:
	global_position = from
	velocity = vel
	gravity = stats.gravity
	drag = stats.drag
	lifetime = stats.lifetime
	stick_time = stats.stick_time
	damage = dmg
	shooter_rid = shooter
	_face(velocity)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	_age += delta
	if _stuck:
		if _age > stick_time:
			queue_free()
		return
	if _age > lifetime:
		queue_free()
		return
	velocity.y -= gravity * delta
	velocity *= maxf(0.0, 1.0 - drag * delta)
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	if shooter_rid.is_valid():
		q.exclude = [shooter_rid]
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		global_position = to
		_face(velocity)
		return
	_stick(res)


func _stick(res: Dictionary) -> void:
	_stuck = true
	_age = 0.0
	var dir := velocity.normalized()
	global_position = res.position + dir * embed_depth
	_face(dir)
	var col: Object = res.collider
	if col is Node3D and not (col is StaticBody3D):
		reparent(col)  # ride along with moving things (players, props)
	if not (col and col.has_method("react_to_hit")):
		Audio.play_at("arrow.hit", res.position)
	if col and col.has_method("react_to_hit"):
		col.react_to_hit(maxf(damage, 8.0), dir, cosmetic)
	if not cosmetic:
		hit.emit(col, res.position, damage)
		print("[arrow] hit %s at %.1fm from origin, dmg %.0f" % [
			(col as Node).name if col is Node else "?", res.position.length(), damage])


func _face(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
	look_at(global_position + dir, up)
