extends Panel
## One inventory slot (hotbar or bag). Shows the item's icon, count and state frame
## (gold = equipped weapon, teal = worn shield, soft gold = ammo in use).
## While the inventory is open (GameConfig.inventory_open) you can drag its item onto
## any other slot: Equipment.move_item does the move / swap. No item logic here.

signal hover_changed(slot: int, on: bool)

const EQUIPPED := Color(1.0, 0.8, 0.25)
const WORN := Color(0.35, 0.9, 0.95)
const IN_USE := Color(1.0, 0.85, 0.45, 0.55)
const HOVER := Color(1, 1, 1, 0.85)
const EMPTY_BG := Color(0.05, 0.05, 0.08, 0.45)
const FILLED_BG := Color(0.08, 0.08, 0.12, 0.7)

var slot := 0
var equipment: Node
var icons: Node
var grow_equipped := true                  ## hotbar: equipped slot pops a little bigger

var _style: StyleBoxFlat
var _icon: TextureRect
var _name: Label
var _count: Label
var _hover := false


func setup(slot_index: int, size_px: int, key_text: String, icon_source: Node) -> void:
	slot = slot_index
	icons = icon_source
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_style = StyleBoxFlat.new()
	_style.bg_color = EMPTY_BG
	_style.set_corner_radius_all(8)
	_style.set_border_width_all(2)
	add_theme_stylebox_override("panel", _style)
	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 6
	_icon.offset_top = 6
	_icon.offset_right = -6
	_icon.offset_bottom = -6
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_name = _label(11, Color(1, 1, 1, 0.8))   # fallback when no icon (headless)
	_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	if key_text != "":
		var key := _label(13, Color(1, 1, 1, 0.7))
		key.text = key_text
		key.position = Vector2(5, 1)
	_count = _label(15, Color(1, 1, 1))
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.offset_left = -40
	_count.offset_top = -22
	_count.offset_right = -5
	_count.offset_bottom = -2
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _set_hover(on: bool) -> void:
	if _hover == on:
		return
	_hover = on
	hover_changed.emit(slot, on)


func item_id() -> String:
	if not is_instance_valid(equipment) or slot >= equipment.inventory.size():
		return ""
	return equipment.inventory[slot]


## Called every frame by the hotbar / inventory panel.
func refresh() -> void:
	var open := GameConfig.inventory_open
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if not open and _hover:
		_set_hover(false)
	var id := item_id()
	var it: Resource = ItemDB.get_item(id) if id != "" else null
	pivot_offset = size * 0.5
	if it == null:
		_icon.texture = null
		_name.text = ""
		_count.text = ""
		_style.bg_color = EMPTY_BG
		_style.border_color = HOVER if _hover else Color(1, 1, 1, 0.12)
		_style.set_border_width_all(2)
		scale = Vector2.ONE
		return
	_icon.texture = icons.get_icon(id) if icons else null
	_name.text = "" if _icon.texture else it.display_name
	_count.text = str(int(equipment.ammo.get(id, 0))) if it.kind == "ammo" else ""
	var cur_w: Resource = equipment.weapon()
	var border := Color(1, 1, 1, 0.3)
	var width := 2
	if id == equipment.sync_weapon_id:
		border = EQUIPPED
		width = 4
	elif id == equipment.sync_shield_id:
		border = WORN
		width = 3
	elif cur_w and it.kind == "ammo" and cur_w.ammo_item_id == id:
		border = IN_USE
		width = 3
	if _hover:
		border = border.lerp(HOVER, 0.6)
		width = maxi(width, 3)
	_style.border_color = border
	_style.set_border_width_all(width)
	_style.bg_color = FILLED_BG.lightened(0.12) if width >= 4 or _hover else FILLED_BG
	_icon.modulate = Color(1, 1, 1, 0.35) if _dragging_me() else Color.WHITE
	scale = Vector2.ONE * (1.08 if grow_equipped and id == equipment.sync_weapon_id and not open else 1.0)


func _dragging_me() -> bool:
	if not get_viewport().gui_is_dragging():
		return false
	var d: Variant = get_viewport().gui_get_drag_data()
	return d is Dictionary and d.get("inv_slot", -1) == slot


# ---------------------------------------------------------------- drag & drop (Godot GUI)
func _get_drag_data(_at: Vector2) -> Variant:
	if not GameConfig.inventory_open or item_id() == "":
		return null
	var preview := Control.new()
	var pic := TextureRect.new()
	pic.texture = _icon.texture
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size = custom_minimum_size * 0.9
	pic.position = -pic.size * 0.5           # centred on the cursor
	pic.modulate = Color(1, 1, 1, 0.9)
	preview.add_child(pic)
	if pic.texture == null:
		var l := Label.new()
		l.text = _name.text
		l.position = pic.position
		preview.add_child(l)
	set_drag_preview(preview)
	return { "inv_slot": slot }


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return GameConfig.inventory_open and data is Dictionary and data.has("inv_slot")


func _drop_data(_at: Vector2, data: Variant) -> void:
	if is_instance_valid(equipment):
		Audio.play("ui.hover" if equipment.move_item(int(data.inv_slot), slot) else "ui.error")
