extends Node3D
## A lit Blastgourd Bomb in the world (thrown, dropped, or blown up in your hands).
## Bounces and rolls, flashes faster as the fuse runs out, then explodes: blunt damage in a
## radius (falling off with distance), knocks the local player back, sets off nearby bombs.
## The thrower's copy deals damage; every other peer runs a cosmetic copy from rpc.

const FX := preload("res://systems/components/element_fx.gd")
const RADIUS := 0.14
const Impacts := preload("res://systems/element_impacts.gd")

var velocity := Vector3.ZERO
var fuse := 4.0
var stats: Resource
var cosmetic := false
var shooter_rid := RID()
var exploded := false
var model_id := "item.bomb.blastgourd"
var _rest := false
var _model: Node3D
var _flash: StandardMaterial3D
var _sparks: CPUParticles3D
var _t := 0.0


func _ready() -> void:
	add_to_group("bombs")
	_model = AssetRegistry.instantiate(model_id)
	add_child(_model)
	_flash = StandardMaterial3D.new()
	_flash.albedo_color = Color(1, 0.2, 0.1, 0.0)
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.emission_enabled = true
	_flash.emission = Color(1.0, 0.15, 0.05)
	for m in _model.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).material_overlay = _flash
	if not _vial():
		_sparks = fuse_sparks()
		_model.add_child(_sparks)
		_sparks.position = Vector3(0, 0.22, 0)


static func fuse_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.3
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, -3, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.8, 0.3)
	q.material = mat
	p.mesh = q
	return p


func _physics_process(delta: float) -> void:
	if exploded:
		return
	_t += delta
	if _vial():
		_move(delta)                               # vials: no fuse, they break when they hit something
		return
	fuse -= delta
	# OoT: the bomb flashes red faster and faster near the end
	var rate := 3.0 if fuse > 1.5 else lerpf(14.0, 5.0, clampf(fuse / 1.5, 0.0, 1.0))
	var on := sin(_t * rate * TAU) > 0.2 and fuse < 2.5
	_flash.albedo_color.a = 0.55 if on else 0.0
	_flash.emission_energy_multiplier = 2.0 if on else 0.0
	_model.scale = Vector3.ONE * (1.0 + (0.08 if on else 0.0))
	if fuse <= 0.0:
		explode()
		return
	_move(delta)


func _move(delta: float) -> void:
	var g: float = stats.gravity if stats else 18.0
	var space := get_world_3d().direct_space_state
	if _rest:
		# rolling / sitting: slow down, fall off edges
		var h := Vector3(velocity.x, 0, velocity.z)
		h = h.move_toward(Vector3.ZERO, (stats.friction if stats else 3.0) * delta)
		velocity = Vector3(h.x, 0, h.z)
		var down := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * (RADIUS + 0.15), 1)
		if space.intersect_ray(down).is_empty():
			_rest = false
	else:
		velocity.y -= g * delta
	if Water.depth_at(global_position) > 0.2:
		velocity = velocity.move_toward(Vector3(0, -0.5, 0), 6.0 * delta)   # sinks, fuse keeps going
	var to := global_position + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(global_position, to + velocity.normalized() * RADIUS, 3 if _vial() else 1)
	if shooter_rid.is_valid():
		q.exclude = [shooter_rid]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		global_position = to
	elif _vial():
		_shatter(hit.position, hit.collider)
		return
	else:
		var n: Vector3 = hit.normal
		global_position = hit.position + n * RADIUS
		velocity = velocity.bounce(n) * (stats.bounce if stats else 0.35)
		if n.y > 0.6 and absf(velocity.y) < 1.2:
			velocity.y = 0.0
			_rest = true
	if velocity.length() > 0.2:
		_model.rotate(Vector3.UP.cross(velocity.normalized()).normalized() if Vector3(velocity.x, 0, velocity.z).length() > 0.1 else Vector3.RIGHT, velocity.length() * delta / RADIUS * 0.3)


func _vial() -> bool:
	return stats != null and "shatter_element" in stats and stats.shatter_element != ""


## Brew vial: glass breaks, the brew's effect happens here (every peer runs its own copy).
func _shatter(at: Vector3, col: Object) -> void:
	if exploded:
		return
	exploded = true
	var el: String = stats.shatter_element
	var scene := get_tree().current_scene
	FX.burst(at, scene, Color(0.85, 0.95, 1.0, 0.8), 12, 0.04, 3.0)          # glass
	FX.burst(at, scene, WorldRules.element_color(el), 18, 0.06, 3.5)
	Audio.play_at("ice.shatter", at, -2.0, 1.6)
	if col and not cosmetic and stats.impact_damage > 0.0:
		WorldRules.deliver_hit(col, WorldRules.make_hit(stats.impact_damage, "blunt", "", velocity.normalized()), false)
	Impacts.impact(get_tree(), el, at, stats.impact_size, not cosmetic)
	queue_free()


func explode() -> void:
	if exploded:
		return
	exploded = true
	var r: float = stats.blast_radius if stats else 3.6
	var at := global_position
	var scene := get_tree().current_scene
	FX.burst(at, scene, Color(1.0, 0.55, 0.15), 40, 0.18, 9.0)
	FX.burst(at, scene, Color(0.25, 0.22, 0.2), 24, 0.22, 5.0)
	FX.smoke_puff(at + Vector3.UP * 0.5, scene, 2.4)
	Audio.play_at("ice.shatter", at, 6.0, 0.45)
	Audio.play_at("wood.break", at, 4.0, 0.55)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 10.0
	light.omni_range = r * 3.0
	scene.add_child(light)
	light.global_position = at + Vector3.UP * 0.6
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_callback(light.queue_free)
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = r
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = shape
	qp.transform = Transform3D(Basis(), at)
	qp.collision_mask = 3
	for res in space.intersect_shape(qp, 48):
		var col: Object = res.collider
		if col == null or not (col is Node3D):
			continue
		var to: Vector3 = (col as Node3D).global_position - at
		var d := to.length()
		var dir := to.normalized() if d > 0.05 else Vector3.UP
		# knock back the local player (each peer's own copy pushes its own player)
		if col is CharacterBody3D and "motor" in col and col.is_multiplayer_authority():
			var push := (Vector3(dir.x, 0, dir.z).normalized() * 7.0 + Vector3.UP * 6.0) * clampf(1.0 - d / r, 0.3, 1.0)
			col.motor.knock(col, push)
		if cosmetic:
			continue
		if col.has_method("react_to_hit_info") or col.has_method("react_to_hit") or WorldRules.reactive_of(col) != null:
			var dmg: float = (stats.blast_damage if stats else 40.0) * lerpf(1.0, 0.4, clampf(d / r, 0.0, 1.0))
			var hit := WorldRules.make_hit(dmg, "blunt", "", dir)
			hit["blast"] = true                  # cracked walls only open for explosions
			WorldRules.deliver_hit(col, hit, false)
	# cracked walls: checked directly by distance to the wall's middle (don't rely on the
	# overlap query alone - big maps can crowd it out)
	if not cosmetic:
		for w in get_tree().get_nodes_in_group("cracked_walls"):
			if w.broken:
				continue
			var wt: Transform3D = (w as Node3D).global_transform
			var local := wt.affine_inverse() * at
			var mid := wt * Vector3(clampf(local.x, -1.8, 1.8), clampf(local.y, 0.0, 3.2), clampf(local.z, -0.4, 0.4))
			var dist := mid.distance_to(at)
			print("[bomb] cracked wall %s is %.1fm away (reach %.1fm)" % [w.name, dist, r])
			if dist <= r:
				var wh := WorldRules.make_hit(40.0, "blunt", "", (mid - at).normalized())
				wh["blast"] = true
				w.react_to_hit_info(wh, false)
	# chain reaction
	var chain: float = stats.chain_radius if stats else 3.0
	for b in get_tree().get_nodes_in_group("bombs"):
		if b != self and not b.exploded and (b as Node3D).global_position.distance_to(at) <= chain:
			b.fuse = minf(b.fuse, 0.12)
	print("[bomb] exploded%s" % (" (cosmetic)" if cosmetic else ""))
	queue_free()
