extends Control
## Arrow-type wheel: hold R (pad: D-pad up) with a bow in hand. Move the mouse / right stick
## toward a slice, let go of R to load that ammo. Tap R = next type.
## Reads Equipment.ammo_options() / select_ammo(); icons come from ItemIcons. No item logic here.

@export var radius := 120.0                ## centre of the icons
@export var inner_radius := 52.0
@export var outer_radius := 170.0
@export var pick_deadzone := 28.0          ## mouse travel (px) before a slice is picked
@export var tap_time := 0.18               ## shorter press = cycle to the next type

var equipment: Node
var icons: Node

var _open := false
var _held := 0.0
var _pick := Vector2.ZERO
var _options: Array[String] = []
var _hover := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if icons and icons.has_signal("icon_ready"):
		icons.icon_ready.connect(func(_id: String) -> void: queue_redraw())


func _can_use() -> bool:
	return is_instance_valid(equipment) and GameConfig.gameplay_input_enabled \
		and not GameConfig.inventory_open and equipment.weapon_type() == "shoot" \
		and not equipment._player.sync_dead


func _process(delta: float) -> void:
	var pressed := Input.is_action_pressed("ammo_wheel")
	if not _can_use():
		_close(false)
		return
	if pressed:
		_held += delta
		if not _open and _held >= tap_time:
			_show()
		if _open:
			var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
			if stick.length() > 0.5:
				_pick = stick * 100.0
			_update_hover()
			queue_redraw()
	elif _held > 0.0:
		if _open:
			_close(true)
		else:
			_cycle()                               # quick tap
		_held = 0.0


func _input(event: InputEvent) -> void:
	if _open and event is InputEventMouseMotion:
		_pick += (event as InputEventMouseMotion).relative
		_pick = _pick.limit_length(160.0)


func _show() -> void:
	_options = _owned_options()
	_pick = Vector2.ZERO
	_hover = _options.find(equipment.current_ammo_id())
	_open = true
	visible = true
	GameConfig.wheel_open = true
	Audio.play("ui.select", -6.0, 1.3)
	queue_redraw()


func _close(apply: bool) -> void:
	if _open and apply and _hover >= 0 and _hover < _options.size():
		var id := _options[_hover]
		if id != equipment.current_ammo_id():
			equipment.select_ammo(equipment.sync_weapon_id, id)
			Audio.play("ui.select")
	_open = false
	_held = 0.0
	visible = false
	GameConfig.wheel_open = false


## Ammo types you actually carry (base ammo always shows, greyed when empty).
func _owned_options() -> Array[String]:
	var out: Array[String] = []
	for id: String in equipment.ammo_options():
		if out.is_empty() or int(equipment.ammo.get(id, 0)) > 0:
			out.append(id)
	return out


func _cycle() -> void:
	var opts := _owned_options()
	if opts.size() < 2:
		Audio.play("ui.error")
		return
	var i := opts.find(equipment.current_ammo_id())
	equipment.select_ammo(equipment.sync_weapon_id, opts[(i + 1) % opts.size()])
	Audio.play("ui.select")


func _slice_angle(i: int) -> float:
	return -PI / 2.0 + TAU * float(i) / float(maxi(_options.size(), 1))   # first slice at the top


func _update_hover() -> void:
	if _pick.length() < pick_deadzone or _options.is_empty():
		return
	var step := TAU / float(_options.size())
	var a := fposmod(_pick.angle() + PI / 2.0 + step / 2.0, TAU)
	_hover = int(a / step) % _options.size()


func _draw() -> void:
	if not _open or _options.is_empty():
		return
	var c := size / 2.0
	var n := _options.size()
	var step := TAU / float(n)
	draw_circle(c, outer_radius + 6.0, Color(0, 0, 0, 0.35))
	for i in n:
		var a0 := _slice_angle(i) - step / 2.0
		var pts := PackedVector2Array()
		for k in 17:
			var a := a0 + step * float(k) / 16.0
			pts.append(c + Vector2.from_angle(a) * outer_radius)
		for k in 17:
			var a := a0 + step - step * float(k) / 16.0
			pts.append(c + Vector2.from_angle(a) * inner_radius)
		var on := i == _hover
		var col := Color(1.0, 0.82, 0.35, 0.55) if on else Color(0.08, 0.08, 0.12, 0.72)
		if n == 1:
			draw_circle(c, outer_radius, col)
		else:
			draw_colored_polygon(pts, col)
			draw_line(c + Vector2.from_angle(a0) * inner_radius, c + Vector2.from_angle(a0) * outer_radius, Color(1, 1, 1, 0.25), 2.0)
		var id := _options[i]
		var p := c + Vector2.from_angle(_slice_angle(i)) * radius
		var count := int(equipment.ammo.get(id, 0))
		var tex: Texture2D = icons.get_icon(id) if icons else null
		var s := 64.0 if on else 54.0
		var tint := Color.WHITE if count > 0 else Color(1, 1, 1, 0.35)
		var font := ThemeDB.fallback_font
		if tex:
			draw_texture_rect(tex, Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), false, tint)
		else:
			var it: Resource = ItemDB.get_item(id)
			draw_string(font, p + Vector2(-40, 5), it.display_name if it else id, HORIZONTAL_ALIGNMENT_CENTER, 80, 13, tint)
		draw_string_outline(font, p + Vector2(4, s / 2.0 + 2), "x%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.9))
		draw_string(font, p + Vector2(4, s / 2.0 + 2), "x%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tint)
	draw_circle(c, inner_radius - 4.0, Color(0, 0, 0, 0.55))
	var label := ""
	if _hover >= 0 and _hover < n:
		var hit: Resource = ItemDB.get_item(_options[_hover])
		label = hit.display_name if hit else ""
	var f := ThemeDB.fallback_font
	draw_string(f, c + Vector2(-inner_radius, 5), label, HORIZONTAL_ALIGNMENT_CENTER, inner_radius * 2.0, 13, Color.WHITE)
	# what the hovered arrow does, under the wheel
	if _hover >= 0 and _hover < n:
		var hit2: Resource = ItemDB.get_item(_options[_hover])
		var fx := ""
		if hit2:
			fx = str(WorldRules.rules.element_info.get(hit2.element, ""))
			if hit2.explosive:
				fx = "Explodes on impact - the fuse lights when you draw."
			elif fx == "":
				fx = "Plain arrows."
		var w := 520.0
		var y := c.y + outer_radius + 34.0
		draw_rect(Rect2(Vector2(c.x - w * 0.5 - 8, y - 22), Vector2(w + 16, 52)), Color(0, 0, 0, 0.6))
		draw_multiline_string(f, Vector2(c.x - w * 0.5, y), fx, HORIZONTAL_ALIGNMENT_CENTER, w, 15, 2, Color(1, 0.95, 0.85))
	# where the mouse is pointing
	if _pick.length() >= pick_deadzone:
		draw_circle(c + _pick.normalized() * (inner_radius - 12.0), 4.0, Color(1, 0.85, 0.4))
