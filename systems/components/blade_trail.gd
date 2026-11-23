extends MeshInstance3D
## Swing trail: a fading ribbon between a blade's base and tip (OoT draws its sword
## and boomerang trails the same way, "EffectBlure"). Follows any Node3D; turn it on
## with `active` while a swing can hit. World-space, rebuilt every frame.

@export var base_local := Vector3(0, 0.15, 0)
@export var tip_local := Vector3(0, 1.3, 0)
@export var lifetime := 0.14              ## how long a trail sample lasts
@export var color := Color(0.55, 0.95, 1.0, 0.85)

var follow: Node3D
var active := false

var _pts: Array = []                      ## [base, tip, age]
var _im := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	material_override = mat


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	for p in _pts:
		p[2] += delta
	while not _pts.is_empty() and _pts[0][2] > lifetime:
		_pts.pop_front()
	if active and is_instance_valid(follow) and follow.is_inside_tree():
		var xf := follow.global_transform
		_pts.append([xf * base_local, xf * tip_local, 0.0])
	_im.clear_surfaces()
	if _pts.size() < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _pts:
		var a := clampf(1.0 - p[2] / lifetime, 0.0, 1.0)
		var c := Color(color.r, color.g, color.b, color.a * a)
		_im.surface_set_color(Color(c.r, c.g, c.b, c.a * 0.15))
		_im.surface_add_vertex(p[0])
		_im.surface_set_color(c)
		_im.surface_add_vertex(p[1])
	_im.surface_end()
