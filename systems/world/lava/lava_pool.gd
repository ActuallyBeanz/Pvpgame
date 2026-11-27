@tool
extends Node3D
## A pool of lava: an irregular glowing disc at this node's height, a hurt-zone, a big warm light,
## bubbling embers. Move it, set the radius; it rebuilds itself. Sink the node a little into the
## ground (or carve a hollow with the Terrain3D tools) so the edges sit inside the terrain.

const LavaZone := preload("res://systems/world/lava/lava_zone.gd")
const LAVA_SHADER := preload("res://assets/shaders/lava.gdshader")

@export var radius := 8.0:
	set(v):
		radius = v
		_dirty = true
@export var edge_wobble := 0.18:
	set(v):
		edge_wobble = v
		_dirty = true
@export var light_energy := 5.0
@export var crust_amount := 0.45

var _dirty := true
var _built: Node3D


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	if _built:
		_built.queue_free()
	_built = Node3D.new()
	_built.name = "_Built"
	add_child(_built)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(16, int(radius * 3.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(radius * 100.0)
	var ring: Array[Vector3] = []
	for k in n:
		var a := TAU * float(k) / float(n)
		var r := radius * (1.0 + rng.randf_range(-edge_wobble, edge_wobble))
		ring.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for k in n:
		for v in [Vector3.ZERO, ring[(k + 1) % n], ring[k]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = LAVA_SHADER
	mat.set_shader_parameter("world_uv", true)
	mat.set_shader_parameter("crust_amount", crust_amount)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_built.add_child(mi)
	LavaZone.make_box(_built, Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(radius * 1.7, 1.2, radius * 1.7))
	var lt := OmniLight3D.new()
	lt.light_color = Color(1.0, 0.45, 0.15)
	lt.light_energy = light_energy
	lt.omni_range = radius * 4.0
	_built.add_child(lt)
	lt.position = Vector3(0, radius * 0.6 + 2.0, 0)
	if not Engine.is_editor_hint():
		var p := CPUParticles3D.new()
		p.amount = int(radius * 4.0)
		p.lifetime = 1.4
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = radius * 0.7
		p.direction = Vector3.UP
		p.spread = 20.0
		p.gravity = Vector3(0, 0.5, 0)
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 2.0
		var q := QuadMesh.new()
		q.size = Vector2(0.1, 0.1)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = Color(1.0, 0.6, 0.2)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.5, 0.15)
		m.emission_energy_multiplier = 4.0
		q.material = m
		p.mesh = q
		_built.add_child(p)
		p.position = Vector3.UP * 0.2
