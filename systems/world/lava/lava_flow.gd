@tool
extends Path3D
## A river of lava. Draw / edit the curve (it follows the ground by itself), set the width, and it
## builds: a glowing flowing ribbon hugging the terrain, hurt-zones along it, ember sparks, a glow
## light every so often, and steam where it reaches water.
## carve_channel (Inspector checkbox) digs a groove in the Terrain3D along the curve once -
## then save the scene (and the terrain, Terrain3D does that when you save).
## Everything is rebuilt at load from the curve, so only the curve + settings are saved.

const LavaZone := preload("res://systems/world/lava/lava_zone.gd")
const LAVA_SHADER := preload("res://assets/shaders/lava.gdshader")

@export var width := 4.0:
	set(v):
		width = v
		_dirty = true
@export var width_noise := 0.25            ## edges wobble by this fraction
@export var hover := 0.12                  ## metres above the ground
@export var flow_speed := 0.35:
	set(v):
		flow_speed = v
		_dirty = true
@export var current := 1.6                 ## m/s the flow drags anyone wading in it downhill
@export var light_every := 18.0            ## a warm OmniLight this many metres apart (0 = none)
@export var embers := true
@export var terrain_path: NodePath = ^"../../Terrain"   ## the island_terrain3d node (height queries)
@export_group("Carve")
@export var channel_depth := 1.2
@export var channel_extra_width := 3.0     ## soft bank beyond the lava on each side
@export var carve_channel := false:        ## tick to dig once (unticks itself)
	set(v):
		if v and is_inside_tree():
			_carve()
		carve_channel = false

var _dirty := true
var _built: Node3D
var _last_curve_hash := 0


func _ready() -> void:
	if not curve:
		curve = Curve3D.new()
	_dirty = true


func _process(_delta: float) -> void:
	var h := _curve_hash()
	if h != _last_curve_hash:
		_last_curve_hash = h
		_dirty = true
	if _dirty:
		_dirty = false
		_rebuild()


func _curve_hash() -> int:
	if curve == null:
		return 0
	return hash(curve.get_baked_points())


func _ground(x: float, z: float) -> float:
	var t := get_node_or_null(terrain_path)
	if t and t.has_method("height_at"):
		return t.height_at(x, z)
	return global_position.y


func _rebuild() -> void:
	if _built:
		_built.queue_free()
		_built = null
	if curve == null or curve.point_count < 2 or not is_inside_tree():
		return
	_built = Node3D.new()
	_built.name = "_Built"
	add_child(_built)                       # no owner: not saved, rebuilt every load
	var pts := curve.get_baked_points()
	var step := 1.0
	var length := curve.get_baked_length()
	var samples: Array[Vector3] = []
	var d := 0.0
	while d <= length:
		samples.append(curve.sample_baked(d))
		d += step
	if samples.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = samples.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var vs: Array[float] = []
	var dist := 0.0
	for i in samples.size():
		var p: Vector3 = global_transform * samples[i]
		var a: Vector3 = global_transform * samples[maxi(i - 1, 0)]
		var b: Vector3 = global_transform * samples[mini(i + 1, samples.size() - 1)]
		var tan := (b - a)
		tan.y = 0.0
		tan = tan.normalized() if tan.length() > 0.01 else Vector3.FORWARD
		var right := tan.cross(Vector3.UP).normalized()
		var w := width * (1.0 + rng.randf_range(-width_noise, width_noise)) * _taper(i, samples.size())
		var l := p - right * w * 0.5
		var r := p + right * w * 0.5
		l.y = _ground(l.x, l.z) + hover
		r.y = _ground(r.x, r.z) + hover
		var mid_y := _ground(p.x, p.z) + hover
		l.y = minf(l.y, mid_y + 0.4)
		r.y = minf(r.y, mid_y + 0.4)
		lefts.append(l)
		rights.append(r)
		if i > 0:
			dist += samples[i].distance_to(samples[i - 1])
		vs.append(dist / maxf(width, 0.5))
	var inv := global_transform.affine_inverse()
	for i in samples.size() - 1:
		var q := [inv * lefts[i], inv * rights[i], inv * rights[i + 1], inv * lefts[i + 1]]
		var uvq := [Vector2(0, vs[i]), Vector2(1, vs[i]), Vector2(1, vs[i + 1]), Vector2(0, vs[i + 1])]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uvq[k])
			st.set_normal(Vector3.UP)
			st.add_vertex(q[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = LAVA_SHADER
	mat.set_shader_parameter("flow_speed", flow_speed)
	mat.set_shader_parameter("shore_crust", 0.12)        # a ribbon is thin: crust from the UV banks
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_built.add_child(mi)
	# hurt-zones + lights + embers along the flow
	var since_light := light_every
	for i in range(0, samples.size() - 1, 2):
		var c := (lefts[i] + rights[i] + lefts[mini(i + 2, samples.size() - 1)] + rights[mini(i + 2, samples.size() - 1)]) * 0.25
		var along := (lefts[mini(i + 2, samples.size() - 1)] + rights[mini(i + 2, samples.size() - 1)]) * 0.5 - (lefts[i] + rights[i]) * 0.5
		var w2 := lefts[i].distance_to(rights[i])
		if along.length() < 0.05:
			continue
		var xf := Transform3D(Basis.looking_at(along.normalized(), Vector3.UP), c + Vector3.UP * 0.4)
		var push := Vector3(along.x, 0.0, along.z).normalized() * current
		LavaZone.make_box(_built, xf, Vector3(w2 * 0.85, 1.2, along.length() + 0.4), push)
		since_light += 2.0
		if light_every > 0.0 and since_light >= light_every:
			since_light = 0.0
			var lt := OmniLight3D.new()
			lt.light_color = Color(1.0, 0.45, 0.15)
			lt.light_energy = 2.2
			lt.omni_range = maxf(8.0, width * 3.0)
			lt.shadow_enabled = false
			_built.add_child(lt)
			lt.global_position = c + Vector3.UP * 2.0
	if embers and not Engine.is_editor_hint():
		for i in range(4, samples.size(), 9):
			var e := _ember_particles()
			_built.add_child(e)
			e.global_position = (lefts[i] + rights[i]) * 0.5 + Vector3.UP * 0.3
	# steam where it runs into water
	var last := (lefts[lefts.size() - 1] + rights[rights.size() - 1]) * 0.5
	if not Engine.is_editor_hint() and Water.depth_at(last + Vector3.UP * 0.2) > 0.0:
		var s := _steam()
		_built.add_child(s)
		s.global_position = last


func _taper(i: int, n: int) -> float:
	# narrow start at the source, full width after a few metres
	return clampf(0.45 + float(i) / 6.0, 0.45, 1.0)


func _ember_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.4, 0.1, 2.0)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.scale_amount_min = 0.5
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.6, 0.2)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.15)
	m.emission_energy_multiplier = 4.0
	q.material = m
	p.mesh = q
	return p


func _steam() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 30
	p.lifetime = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = width * 0.6
	p.direction = Vector3.UP
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_max = 1.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.9, 0.9, 0.92, 0.35)
	q.material = m
	p.mesh = q
	return p


## Dig a groove into the Terrain3D along the curve (editor tool, run once).
func _carve() -> void:
	var t := get_node_or_null(terrain_path)
	var t3d: Node = t.get("t3d") if t else null
	if t3d == null:
		for c in (t.get_children() if t else []):
			if c.get_class() == "Terrain3D":
				t3d = c
	if t3d == null or curve == null:
		push_warning("LavaFlow: no Terrain3D to carve")
		return
	var data: Object = t3d.data
	var half := width * 0.5 + channel_extra_width
	var length := curve.get_baked_length()
	var done := {}
	var d := 0.0
	while d <= length:
		var p: Vector3 = global_transform * curve.sample_baked(d)
		for ox in range(-int(half) - 1, int(half) + 2):
			for oz in range(-int(half) - 1, int(half) + 2):
				var x := roundf(p.x) + ox
				var z := roundf(p.z) + oz
				var key := Vector2i(int(x), int(z))
				var dd := Vector2(x - p.x, z - p.z).length()
				if dd > half:
					continue
				var k := 1.0 - smoothstep(width * 0.5, half, dd)
				var want: float = float(data.get_height(Vector3(x, 0, z))) - channel_depth * k
				if not done.has(key) or float(done[key]) > want:
					done[key] = want
		d += 1.0
	for key: Vector2i in done:
		data.set_height(Vector3(key.x, 0, key.y), float(done[key]))
	data.update_maps()
	_dirty = true
	print("[lava] carved %d points" % done.size())
