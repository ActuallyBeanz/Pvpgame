extends RefCounted
## Small particle builders shared by Reactive props and projectiles.
## Debug-primitive meshes only; swap for real VFX scenes later.


static func flames(size := 1.0, with_light := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Flames"
	var p := CPUParticles3D.new()
	p.amount = int(18 * clampf(size, 0.4, 2.5))
	p.lifetime = 0.55
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 18.0
	p.gravity = Vector3(0, 2.5, 0)
	p.initial_velocity_min = 0.6 * size
	p.initial_velocity_max = 1.4 * size
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25 * size
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.3, 0.95))
	grad.set_color(1, Color(0.55, 0.08, 0.02, 0.0))
	grad.add_point(0.4, Color(1.0, 0.42, 0.06, 0.9))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.45) * size
	q.material = _glow_mat()
	p.mesh = q
	root.add_child(p)
	if with_light:
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = Color(1.0, 0.6, 0.25)
		l.light_energy = 1.6
		l.omni_range = 4.0 * size
		l.position = Vector3.UP * 0.3 * size
		l.set_script(_Flicker)
		root.add_child(l)
	return root


static func burst(at: Vector3, parent: Node, color: Color, count := 20, chunk := 0.12, speed := 4.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = count
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var m := BoxMesh.new()
	m.size = Vector3.ONE * chunk
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.get_tree().create_timer(1.5).timeout.connect(p.queue_free)


static func smoke_puff(at: Vector3, parent: Node, size := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 1.2
	p.explosiveness = 0.8
	p.direction = Vector3.UP
	p.spread = 35.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	var grad := Gradient.new()
	grad.set_color(0, Color(0.5, 0.5, 0.5, 0.7))
	grad.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.6 * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	q.material = mat
	p.mesh = q
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## Floating damage number (attacker's screen). Colour by element.
static func damage_number(at: Vector3, parent: Node, amount: float, color := Color.WHITE) -> void:
	var l := Label3D.new()
	l.text = str(roundi(amount))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 56
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color(0.1, 0.05, 0.0, 0.9)
	l.render_priority = 20
	parent.add_child(l)
	l.global_position = at + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position:y", l.global_position.y + 0.9, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)


static func _glow_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1)
	return mat


const _Flicker := preload("res://systems/components/light_flicker.gd")
