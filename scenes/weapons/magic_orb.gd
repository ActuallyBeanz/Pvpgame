extends Node3D
## Rimecaller Rod bolt: a glowing orb that flies straight (no drop), hits the first thing in its
## path and bursts. Frost by default; the rod's infusion (Cinderpepper / Sparkthistle) changes
## the element. The shooter's copy deals damage; other peers run a cosmetic copy (rpc from tools.gd).

const FX := preload("res://systems/components/element_fx.gd")

var velocity := Vector3.ZERO
var element := "frost"
var damage := 12.0
var splash_radius := 1.2                   ## also hits things this close to the burst (half damage)
var lifetime := 1.5
var radius := 0.18
var shooter_rid := RID()
var cosmetic := false

var _age := 0.0
var _done := false
var _light: OmniLight3D


func _ready() -> void:
	var col := WorldRules.element_color(element)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col.lightened(0.35)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	sm.material = m
	mi.mesh = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var shell := MeshInstance3D.new()                      # soft outer glow
	var ss := SphereMesh.new()
	ss.radius = radius * 1.9
	ss.height = radius * 3.8
	ss.radial_segments = 10
	ss.rings = 5
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.albedo_color = Color(col.r, col.g, col.b, 0.35)
	ss.material = gm
	shell.mesh = ss
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 1.6
	_light.omni_range = 3.0
	add_child(_light)
	add_child(_trail(col))
	var tw := shell.create_tween().set_loops()
	tw.tween_property(shell, "scale", Vector3.ONE * 1.25, 0.12)
	tw.tween_property(shell, "scale", Vector3.ONE, 0.12)


func _trail(col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.35
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.8
	p.gravity = Vector3(0, -0.5, 0) if element != "fire" else Vector3(0, 1.5, 0)
	p.initial_velocity_max = 0.4
	p.scale_amount_min = 0.5
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = col
	q.material = m
	p.mesh = q
	return p


func launch(from: Vector3, vel: Vector3) -> void:
	global_position = from
	velocity = vel
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age > lifetime:
		_burst(global_position, null, velocity.normalized())
		return
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to + velocity.normalized() * radius, 3)
	if shooter_rid.is_valid():
		q.exclude = [shooter_rid]
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	# fire fizzles in water, frost skims across it
	if element == "fire" and Water.depth_at(to) > 0.0:
		FX.smoke_puff(to, get_tree().current_scene, 0.6)
		Audio.play_at("fire.extinguish", to, -4.0, 1.2)
		_finish()
		return
	if res.is_empty():
		global_position = to
		return
	var col: Object = res.collider
	if col and col.has_method("blocks_hit") and col.blocks_hit(velocity.normalized()):
		col.on_blocked(res.position)             # raised shield: absorbed
		_burst(res.position, null, velocity.normalized(), false)
		return
	_burst(res.position, col, velocity.normalized())


func _burst(at: Vector3, direct: Object, dir: Vector3, splash := true) -> void:
	var scene := get_tree().current_scene
	var col := WorldRules.element_color(element)
	FX.burst(at, scene, col, 18, 0.07, 4.0)
	if element == "fire":
		FX.smoke_puff(at, scene, 0.5)
	Audio.play_at("ice.hit" if element == "frost" else ("fire.ignite" if element == "fire" else "target.hit"), at, 0.0, 1.2)
	if not cosmetic:
		var hit_ids := {}
		if direct:
			hit_ids[direct.get_instance_id()] = true
			WorldRules.deliver_hit(direct, WorldRules.make_hit(damage, "magic", element, dir), false)
		if splash and splash_radius > 0.0:
			var shape := SphereShape3D.new()
			shape.radius = splash_radius
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.transform = Transform3D(Basis(), at)
			q.collision_mask = 3
			if shooter_rid.is_valid():
				q.exclude = [shooter_rid]
			for r in get_world_3d().direct_space_state.intersect_shape(q, 12):
				var c: Object = r.collider
				if c == null or hit_ids.has(c.get_instance_id()):
					continue
				if c.has_method("react_to_hit_info") or c.has_method("react_to_hit") or WorldRules.reactive_of(c) != null:
					hit_ids[c.get_instance_id()] = true
					WorldRules.deliver_hit(c, WorldRules.make_hit(damage * 0.5, "magic", element, dir), false)
	elif direct:
		WorldRules.deliver_hit(direct, WorldRules.make_hit(damage, "magic", element, dir), true)
	_finish()


func _finish() -> void:
	_done = true
	queue_free()
