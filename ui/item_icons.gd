extends Node
## Renders hotbar icons from the items' own 3D models (so a new item gets an icon with
## no extra art). One small transparent SubViewport, one photo per item, cached.
## Items can override with ItemDef.icon, or pose the model with icon_rotation_deg.

signal icon_ready(item_id: String)

@export var icon_size := 128

static var _cache: Dictionary = {}           ## item_id -> Texture2D
var _queue: Array[String] = []
var _busy := false
var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D


func get_icon(item_id: String) -> Texture2D:
	if _cache.has(item_id):
		return _cache[item_id]
	var it := ItemDB.get_item(item_id)
	if it and it.icon:
		_cache[item_id] = it.icon
		return it.icon
	if not _queue.has(item_id) and DisplayServer.get_name() != "headless":
		_queue.append(item_id)
		if not _busy:
			_busy = true  # one render at a time (they share the stage)
			_render_next.call_deferred()
	return null


func _ensure_stage() -> void:
	if _vp:
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(icon_size, icon_size)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.9
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.3
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_holder = Node3D.new()
	_vp.add_child(_holder)


func _render_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	_ensure_stage()
	var item_id: String = _queue.pop_front()
	var it := ItemDB.get_item(item_id)
	for c in _holder.get_children():
		c.free()
	if it:
		var mid: String = it.icon_model_id
		if mid == "":
			mid = it.pickup_model_id if it.pickup_model_id != "" else it.model_id
		var model := AssetRegistry.instantiate(mid)
		_holder.add_child(model)
		_holder.basis = Basis(Vector3.BACK, deg_to_rad(it.icon_roll_deg)) * Basis.from_euler(it.icon_rotation_deg * PI / 180.0)
		var box := _bounds(_holder)
		var c := box.get_center()
		var extent := maxf(box.size.x, box.size.y)
		_cam.size = maxf(extent * 1.12, 0.05)
		_cam.position = Vector3(c.x, c.y, c.z + box.size.z + 5.0)
		_cam.near = 0.05
		_cam.far = box.size.z + 20.0
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for i in 3:
			await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if img and not img.is_empty():
			_cache[item_id] = ImageTexture.create_from_image(img)
			icon_ready.emit(item_id)
	_render_next()


## World-space bounds of every mesh under n (after its rotation).
func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "VisualInstance3D", true, false):
		var vi := m as VisualInstance3D
		var b := vi.global_transform * vi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out if not first else AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
