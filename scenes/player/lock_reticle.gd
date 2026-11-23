extends Node3D
## OoT-style lock-on marker: three triangles that close in on a target and circle it.
## Used by focus (yellow) and the boomerang's multi-target aim (yellow = can select,
## red = selected). Local only; drawn on top of everything.

var target: Node3D
var close_time := 0.18
var height := 0.55
var start_radius := 1.1
var end_radius := 0.32

var _t := 0.0
var _mat: StandardMaterial3D


static func create(parent: Node, color: Color, size := 1.0) -> Node3D:
	var r: Node3D = (load("res://scenes/player/lock_reticle.gd") as GDScript).new()
	r.name = "LockReticle"
	r.top_level = true
	r._build(color, size)
	parent.add_child(r)
	return r


func follow(t: Node3D) -> void:
	if t != target:
		_t = 0.0
	target = t
	visible = t != null


func set_color(c: Color) -> void:
	_mat.albedo_color = c


func pulse() -> void:
	_t = 0.0  # re-run the close-in animation (on select)


func _build(color: Color, size: float) -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = color
	_mat.no_depth_test = true
	_mat.render_priority = 10
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.22, 0.26, 0.05) * size
	for i in 3:
		var tri := MeshInstance3D.new()
		tri.mesh = mesh
		tri.material_override = _mat
		tri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.add_child(tri)
		tri.rotation = Vector3(0.0, 0.0, PI)          # point down at the target
		holder.rotation.y = -TAU * i / 3.0 + PI * 0.5  # face outward
		add_child(holder)
	start_radius *= size
	end_radius *= size


func _process(delta: float) -> void:
	if not visible or not is_instance_valid(target) or not target.is_inside_tree():
		return
	_t += delta
	var close := clampf(_t / close_time, 0.0, 1.0)
	var radius := lerpf(start_radius, end_radius, close * close * (3.0 - 2.0 * close))
	global_position = target.get_lock_point() + Vector3.UP * (height + sin(_t * 4.0) * 0.05)
	rotation.y += delta * 2.5
	for i in get_child_count():
		var a := TAU * i / get_child_count()
		(get_child(i) as Node3D).position = Vector3(cos(a), 0.0, sin(a)) * radius
