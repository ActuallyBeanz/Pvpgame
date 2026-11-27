extends Node3D
## Mendingdew: a glowing puddle that slowly heals whoever stands in it. Every peer spawns its own
## copy and heals only its own player.

@export var radius := 2.5
@export var life := 6.0
@export var heal_per_sec := 4.0

var _t := 0.0
var _tick := 0.0
var _disc: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	var col := WorldRules.element_color("mendingdew")
	_disc = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.04
	cm.radial_segments = 24
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(col.r, col.g, col.b, 0.45)
	cm.material = _mat
	_disc.mesh = cm
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	_disc.position.y = 0.05
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius * 0.9
	p.emission_ring_inner_radius = 0.2
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.gravity = Vector3(0, 1.0, 0)
	p.initial_velocity_max = 0.6
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_color = col
	q.material = pm
	p.mesh = q
	add_child(p)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 1.2
	l.omni_range = radius * 2.0
	add_child(l)
	l.position.y = 0.6


func _process(delta: float) -> void:
	_t += delta
	_tick -= delta
	_mat.albedo_color.a = 0.45 * clampf((life - _t) / 1.0, 0.0, 1.0)
	if _tick <= 0.0:
		_tick = 0.5
		for pl in get_tree().get_nodes_in_group("players"):
			if pl.is_local() and not pl.sync_dead:
				var d: Vector3 = (pl as Node3D).global_position - global_position
				if Vector2(d.x, d.z).length() <= radius and absf(d.y) < 1.5:
					pl.health.heal(heal_per_sec * 0.5)
	if _t >= life:
		queue_free()
