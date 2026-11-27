extends CanvasLayer
## Autoload "BugReporter": press ` (backtick, under Esc) or F9 anywhere in the game to note a
## problem spot. (Not F8: when you run from the editor, F8 stops the game.)
## Type what's wrong (or leave it empty) and press Enter - it saves, into _reports/ in the
## project folder (git-ignored):
##   report_<time>.png  what you see (taken without the note box)
##   report_<time>.md   position, camera, what you're looking at, the ground there, and every
##                      object within `scan_radius` m (path, type, position, size, collision)
## Esc cancels. tools/map/view_report.tscn re-renders a report's spot from several angles.

const KEYS := [KEY_QUOTELEFT, KEY_F9]
@export var scan_radius := 12.0
@export var max_nodes := 120

var _box: PanelContainer
var _edit: LineEdit
var _toast: Label
var _open := false
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _was_input := true


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = PanelContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_box.offset_top = 80
	_box.custom_minimum_size = Vector2(560, 0)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	_box.add_child(v)
	var t := Label.new()
	t.text = "Bug report - what's wrong here?  Enter = save, Esc = cancel"
	v.add_child(t)
	_edit = LineEdit.new()
	_edit.placeholder_text = "e.g. wall floats, rock clips through bridge, can't walk up here..."
	_edit.text_submitted.connect(func(_t: String) -> void: _save())
	v.add_child(_edit)
	_box.visible = false
	add_child(_box)
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 40
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.visible = false
	add_child(_toast)


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if (k.physical_keycode in KEYS or k.keycode in KEYS) and not _open:
		_open_box()
		get_viewport().set_input_as_handled()
	elif _open and k.physical_keycode == KEY_ESCAPE:
		_close_box()
		get_viewport().set_input_as_handled()


func _open_box() -> void:
	_open = true
	_was_mouse = Input.mouse_mode
	_was_input = GameConfig.gameplay_input_enabled
	GameConfig.gameplay_input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_edit.text = ""
	_box.visible = true
	_edit.grab_focus()
	await get_tree().process_frame
	_edit.text = ""                              # the ` key itself must not land in the note


func _close_box() -> void:
	_open = false
	_box.visible = false
	_edit.release_focus()
	GameConfig.gameplay_input_enabled = _was_input
	Input.mouse_mode = _was_mouse


func _save() -> void:
	var note := _edit.text.strip_edges()
	_close_box()
	await get_tree().process_frame                # the note box is gone from the picture
	await get_tree().process_frame
	var dir := ProjectSettings.globalize_path("res://_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var base := dir.path_join("report_" + stamp)
	var img := get_viewport().get_texture().get_image()
	img.save_png(base + ".png")
	var f := FileAccess.open(base + ".md", FileAccess.WRITE)
	f.store_string(_describe(note, "report_" + stamp))
	f.close()
	_show_toast("Report saved: _reports/report_%s" % stamp)
	print("[bugreport] saved ", base)


func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	await get_tree().create_timer(2.5).timeout
	_toast.visible = false


func _describe(note: String, id: String) -> String:
	var scene := get_tree().current_scene
	var cam := get_viewport().get_camera_3d()
	var me: Node3D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.has_method("is_local") and p.is_local():
			me = p
	var focus: Vector3 = me.global_position if me else (cam.global_position if cam else Vector3.ZERO)
	var t := "# Bug report %s\n\n" % id
	t += "**Note:** %s\n\n" % (note if note != "" else "(none)")
	t += "- scene: %s\n" % (scene.scene_file_path if scene else "?")
	t += "- time: %s\n" % Time.get_datetime_string_from_system()
	if me:
		t += "- player: pos %s  yaw %.1f deg  on_floor %s  velocity %s\n" % [_v(me.global_position),
			rad_to_deg(float(me.get("motor").facing)) if me.get("motor") else 0.0, (me as CharacterBody3D).is_on_floor(),
			_v((me as CharacterBody3D).velocity)]
	if cam:
		var fwd := -cam.global_basis.z
		t += "- camera: pos %s  looking %s  fov %.0f\n" % [_v(cam.global_position), _v(fwd), cam.fov]
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + fwd * 300.0, 0xFFFFFFFF)
		q.collide_with_areas = true
		if me:
			q.exclude = [(me as CollisionObject3D).get_rid()]
		var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var c: Node = hit.collider
			t += "- looking at: %s (%s) at %s, %.1f m away, normal %s\n" % [_path(c), c.get_class(), _v(hit.position),
				cam.global_position.distance_to(hit.position), _v(hit.normal)]
	var terrain := scene.get_node_or_null("Terrain") if scene else null
	if terrain and terrain.has_method("height_at"):
		t += "- ground under player: height %.2f  biome %s  slope %.0f deg\n" % [terrain.height_at(focus.x, focus.z),
			terrain.biome_at(focus.x, focus.z), terrain.slope_deg(focus.x, focus.z)]
	t += "\n## Objects within %.0f m of %s\n\n" % [scan_radius, _v(focus)]
	t += "| dist | path | type | position | scale | info |\n|---|---|---|---|---|---|\n"
	var rows := []
	if scene:
		_collect(scene, focus, rows)
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for r in rows.slice(0, max_nodes):
		t += "| %.1f | %s | %s | %s | %s | %s |\n" % r
	if rows.size() > max_nodes:
		t += "\n(%d more not listed)\n" % (rows.size() - max_nodes)
	return t


func _collect(n: Node, focus: Vector3, rows: Array) -> void:
	var scene := get_tree().current_scene
	# skip the insides of imported models (their meshes are reported as the model node)
	var inside_model: bool = n.owner != null and n.owner != scene and String(n.owner.scene_file_path).ends_with(".glb")
	if n is Node3D and not inside_model and not (n is GPUParticles3D or n is CPUParticles3D or n is Light3D):
		var n3 := n as Node3D
		if n is CollisionObject3D or n.get_script() != null or n is MeshInstance3D or n.scene_file_path != "" or n.get_child_count() > 0:
			var d := n3.global_position.distance_to(focus)
			if d <= scan_radius and n3.is_visible_in_tree():
				rows.append([d, _path(n), n.get_class() + (" (%s)" % n.get_script().resource_path.get_file() if n.get_script() else ""),
					_v(n3.global_position), _v(n3.global_transform.basis.get_scale()), _info(n)])
	if n.is_in_group("players"):
		return
	for c in n.get_children():
		_collect(c, focus, rows)


func _info(n: Node) -> String:
	var bits := []
	if n is CollisionObject3D:
		bits.append("layer %d" % (n as CollisionObject3D).collision_layer)
		for cs in n.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape:
				var sh: Shape3D = (cs as CollisionShape3D).shape
				var sz := ""
				if sh is BoxShape3D:
					sz = _v((sh as BoxShape3D).size)
				elif sh is CylinderShape3D:
					sz = "r%.2f h%.2f" % [(sh as CylinderShape3D).radius, (sh as CylinderShape3D).height]
				elif sh is SphereShape3D:
					sz = "r%.2f" % (sh as SphereShape3D).radius
				bits.append("%s %s @%s%s" % [sh.get_class().replace("Shape3D", ""), sz, _v((cs as Node3D).global_position),
					" OFF" if (cs as CollisionShape3D).disabled else ""])
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var bb := (n as MeshInstance3D).get_aabb()
		bits.append("mesh %s" % _v(bb.size))
	for m in n.get_meta_list():
		if m in ["material", "fire_zone", "lava"]:
			bits.append("%s=%s" % [m, n.get_meta(m)])
	return ", ".join(bits)


func _path(n: Node) -> String:
	var s := get_tree().current_scene
	return str(s.get_path_to(n)) if s and (s == n or s.is_ancestor_of(n)) else str(n.get_path())


func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
