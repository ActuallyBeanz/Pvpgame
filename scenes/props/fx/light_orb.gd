extends Node3D
## Lumenbell light: a small glowing bell-flower bulb that lights the area for a while
## (dark caves, night later). Every peer spawns its own copy.

@export var life := 14.0
@export var energy := 3.0
@export var light_range := 9.0

var _t := 0.0
var _light: OmniLight3D
var _bulb: MeshInstance3D


func _ready() -> void:
	var col := WorldRules.element_color("light")
	_bulb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 8
	sm.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col.lightened(0.5)
	sm.material = m
	_bulb.mesh = sm
	_bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bulb)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = energy
	_light.omni_range = light_range
	_light.shadow_enabled = true
	add_child(_light)
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.gravity = Vector3(0, 0.3, 0)
	p.initial_velocity_max = 0.2
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_color = col
	q.material = pm
	p.mesh = q
	add_child(p)
	Audio.play_at("item.get", global_position, -6.0, 1.6)


func _process(delta: float) -> void:
	_t += delta
	var fade := clampf((life - _t) / 1.5, 0.0, 1.0)
	_light.light_energy = energy * fade * (0.9 + 0.1 * sin(_t * 5.0))
	_bulb.position.y = sin(_t * 2.0) * 0.06
	if _t >= life:
		queue_free()
