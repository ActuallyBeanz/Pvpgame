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
var element := ""                          ## "fire" etc. Set by special ammo, or by flying through a fire zone

var _age := 0.0
var _stuck := false


const FX := preload("res://systems/components/element_fx.gd")

var _flames: Node3D


func _ready() -> void:
	add_child(AssetRegistry.instantiate(model_id))
	if element != "":
		_show_element()


## Light the arrow (fire zone, or fire ammo). Every peer does this from its own copy.
func set_element(e: String) -> void:
	if element == e:
		return
	element = e
	_show_element()
	if e == "fire":
		Audio.play_at("fire.ignite", global_position, -6.0, 1.3)


func _show_element() -> void:
	if element == "fire" and _flames == null and is_inside_tree():
		_flames = FX.flames(0.35, true)
		add_child(_flames)
		_flames.position = Vector3(0, 0, 0.05)


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
	if element != "fire" and WorldRules.fire_zone_on_segment(get_world_3d(), from, to if res.is_empty() else res.position):
		set_element("fire")
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
	var hit_info := WorldRules.make_hit(maxf(damage, 8.0), "pierce", element, dir)
	if not WorldRules.deliver_hit(col, hit_info, cosmetic):
		Audio.play_at("arrow.hit", res.position)
	var r := WorldRules.reactive_of(col)
	if r:
		r.destroyed.connect(queue_free)  # don't float in the air when the prop breaks
	if _flames:
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if is_instance_valid(_flames):
				_flames.queue_free())
	if not cosmetic:
		hit.emit(col, res.position, damage)
		print("[arrow] hit %s at %.1fm from origin, dmg %.0f" % [
			(col as Node).name if col is Node else "?", res.position.length(), damage])


func _face(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
	look_at(global_position + dir, up)
