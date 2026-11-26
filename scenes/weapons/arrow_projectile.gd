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
var headshot_mult := 1.0                   ## from the bow / slingshot stats
var hit_action := "pierce"                 ## "blunt" for slingstones (shatters ice, no sticking-in look needed)
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
	headshot_mult = stats.headshot_mult if "headshot_mult" in stats else 1.0
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
	if element != "fire" and WorldRules.rules.arrows_light_in_flight and WorldRules.fire_zone_on_segment(get_world_3d(), from, to if res.is_empty() else res.position):
		set_element("fire")
	if element == "fire" and Water.depth_at(to) > 0.0:
		element = ""                               # doused flying into water
		if _flames:
			_flames.queue_free()
			_flames = null
		FX.smoke_puff(to, get_tree().current_scene, 0.4)
	if res.is_empty():
		global_position = to
		_face(velocity)
		return
	_stick(res)


func _stick(res: Dictionary) -> void:
	var col0: Object = res.collider
	if col0 and col0.has_method("blocks_hit") and col0.blocks_hit(velocity.normalized()):
		_deflect(res)
		return
	_stuck = true
	_age = 0.0
	var dir := velocity.normalized()
	global_position = res.position + dir * embed_depth
	_face(dir)
	var col: Object = res.collider
	if col is Node3D and not (col is StaticBody3D):
		reparent(col)  # ride along with moving things (players, props)
	# Don't float in the air when the prop breaks. Hook up BEFORE delivering the hit: on the
	# host a killing shot breaks the prop (ice, crate) synchronously inside deliver_hit().
	var r := WorldRules.reactive_of(col)
	if r:
		if r.dead:
			queue_free()
			return
		r.destroyed.connect(queue_free, CONNECT_ONE_SHOT)
	# head / body: targets that know where their head is (dummies, players) say which was hit
	var zone := "body"
	if col and col.has_method("hit_zone"):
		zone = str(col.hit_zone(res.position))
	var dmg := maxf(damage, 8.0) * (headshot_mult if zone == "head" else 1.0)
	var hit_info := WorldRules.make_hit(dmg, hit_action, element, dir)
	hit_info["zone"] = zone
	if zone == "head" and not cosmetic:
		_headshot_popup(res.position)
	if not WorldRules.deliver_hit(col, hit_info, cosmetic):
		Audio.play_at("arrow.hit", res.position)
	if r and r.dead:
		queue_free()   # this arrow was the one that broke it
	if _flames:
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if is_instance_valid(_flames):
				_flames.queue_free())
	if not cosmetic:
		hit.emit(col, res.position, damage)
		print("[arrow] hit %s at %.1fm from origin, dmg %.0f" % [
			(col as Node).name if col is Node else "?", res.position.length(), damage])


func _headshot_popup(at: Vector3) -> void:
	var l := Label3D.new()
	l.text = "HEADSHOT!"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 48
	l.outline_size = 10
	l.pixel_size = 0.004
	l.modulate = Color(1.0, 0.85, 0.2)
	get_tree().current_scene.add_child(l)
	l.global_position = at + Vector3.UP * 0.4
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", l.global_position + Vector3.UP * 0.8, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	tw.tween_callback(l.queue_free)
	Audio.play("target.hit", 4.0, 1.5)
	print("[arrow] HEADSHOT x%.1f" % headshot_mult)


## Bounced off a raised shield: tumble away, can't hurt anyone any more.
func _deflect(res: Dictionary) -> void:
	res.collider.on_blocked(res.position)
	var n: Vector3 = res.normal if res.has("normal") else -velocity.normalized()
	velocity = velocity.bounce(n) * 0.3 + Vector3.UP * 2.5
	global_position = res.position + n * 0.05
	collision_mask = 1         # world only from now on
	damage = 0.0
	element = ""
	if _flames:
		_flames.queue_free()
		_flames = null
	if not cosmetic:
		print("[arrow] blocked by %s's shield" % (res.collider as Node).name)


func _face(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
	look_at(global_position + dir, up)
