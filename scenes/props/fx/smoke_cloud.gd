extends Node3D
## Smolderpuff smoke: a thick grey cloud that hangs for a few seconds, then thins out.
## Blocks lock-on through it (FocusTargeting asks ElementImpacts.smoke_blocks). Every peer
## spawns its own copy.

@export var radius := 3.0
@export var life := 7.0
@export var tint := Color(0.52, 0.52, 0.55)   ## brews tint it (Emberfog orange-grey, Muddlehaze violet)
@export var status_inside := ""            ## brews: status given to anyone standing in it (refreshed)
@export var damage_inside := 0.0           ## per second to anyone inside (fire-type)

var _t := 0.0
var _parts: Array[CPUParticles3D] = []


func _ready() -> void:
	add_to_group("smoke_clouds")
	for layer in 2:
		var p := CPUParticles3D.new()
		p.amount = 70 if layer == 0 else 30
		p.lifetime = 2.2
		p.preprocess = 1.0
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = radius * (0.8 if layer == 0 else 0.5)
		p.gravity = Vector3(0, 0.25, 0)
		p.initial_velocity_max = 0.4
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.3
		var q := QuadMesh.new()
		q.size = Vector2.ONE * (radius * 0.9 if layer == 0 else radius * 1.2)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(tint.r, tint.g, tint.b, 0.55) if layer == 0 else Color(tint.r * 0.75, tint.g * 0.75, tint.b * 0.75, 0.5)
		m.albedo_texture = _soft_dot()
		q.material = m
		p.mesh = q
		p.position = Vector3.UP * radius * 0.45
		add_child(p)
		_parts.append(p)
	Audio.play_at("fire.extinguish", global_position, 0.0, 0.6)


## 0..1: how thick it still is (thins out over the last 2 s).
func density() -> float:
	return clampf((life - _t) / 2.0, 0.0, 1.0)


var _tick := 0.0


func _process(delta: float) -> void:
	_t += delta
	_tick -= delta
	if _tick <= 0.0 and (status_inside != "" or damage_inside > 0.0) and density() > 0.3:
		_tick = 0.5
		_affect_local()
	if _t > life - 2.0:
		for p in _parts:
			p.emitting = false
	if _t > life + 2.3:
		queue_free()


## Each peer checks its own player (statuses are owner-authoritative).
func _affect_local() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_local() or p.sync_dead:
			continue
		var d: Vector3 = (p as Node3D).global_position - global_position
		if Vector2(d.x, d.z).length() <= radius and d.y < radius * 1.2 and d.y > -1.0:
			if status_inside != "":
				p.status.apply(status_inside)
			if damage_inside > 0.0:
				p.health.take_damage(damage_inside * 0.5, Vector3.ZERO, "dot_fire", "")


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	_dot = t
	return t
