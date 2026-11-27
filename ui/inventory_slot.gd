extends Panel
## One inventory slot (hotbar or bag). Shows the item's icon, count and state frame
## (gold = equipped weapon, teal = worn shield, soft gold = ammo in use).
## While the inventory is open (GameConfig.inventory_open) you can drag its item onto
## any other slot: Equipment.move_item does the move / swap / stack merge.
## Right-click: menu (equip / split / drop). Drag it outside the inventory: drop it on the ground
## (the drop zone lives in weapon_hud.gd). No item logic here.

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
	_count.text = str(equipment.count_in_slot(slot)) if equipment.is_stackable(id) else ""
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


# ---------------------------------------------------------------- right-click menu
enum Act { EQUIP, UNEQUIP, TO_HOTBAR, SPLIT_HALF, SPLIT_ONE, DROP_ONE, DROP_ALL, SPLIT_CHOOSE }
var _menu: PopupMenu


func _gui_input(event: InputEvent) -> void:
	if not GameConfig.inventory_open or item_id() == "":
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_open_menu()
		accept_event()


func _open_menu() -> void:
	var id := item_id()
	var it: Resource = ItemDB.get_item(id)
	if it == null:
		return
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.id_pressed.connect(_on_menu)
		add_child(_menu)
	_menu.clear()
	var n: int = equipment.count_in_slot(slot)
	var stack: bool = equipment.is_stackable(id)
	if it.kind == "weapon":
		if equipment.is_hotbar_slot(slot):
			if id == equipment.sync_weapon_id:
				_menu.add_item("Unequip", Act.UNEQUIP)
			else:
				_menu.add_item("Equip", Act.EQUIP)
		else:
			_menu.add_item("Move to hotbar", Act.TO_HOTBAR)
	if stack and n > 1:
		_menu.add_item("Split...", Act.SPLIT_CHOOSE)
		_menu.add_item("Split in half (%d)" % (n / 2), Act.SPLIT_HALF)
	if stack and n > 1:
		_menu.add_item("Drop 1", Act.DROP_ONE)
	_menu.add_item("Drop all (%d)" % n if stack and n > 1 else "Drop", Act.DROP_ALL)
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.popup()


func _on_menu(act: int) -> void:
	if not is_instance_valid(equipment):
		return
	var id := item_id()
	var ok := true
	match act:
		Act.EQUIP:
			equipment._equip(id)
		Act.UNEQUIP:
			equipment._unequip()
			equipment.changed.emit()
		Act.TO_HOTBAR:
			var free: int = equipment.inventory.find("")
			ok = free >= 0 and equipment.is_hotbar_slot(free) and equipment.move_item(slot, free)
		Act.SPLIT_HALF:
			ok = equipment.split_stack(slot, equipment.count_in_slot(slot) / 2)
		Act.SPLIT_ONE:
			ok = equipment.split_stack(slot, 1)
		Act.SPLIT_CHOOSE:
			_open_split_picker()
			return
		Act.DROP_ONE:
			ok = equipment.drop_item(slot, 1)
		Act.DROP_ALL:
			ok = equipment.drop_item(slot, 0)
	Audio.play("ui.select" if ok else "ui.error")


## Split picker: slider (+ number box) for how many to move into a new stack.
var _split_pop: PopupPanel


func _open_split_picker() -> void:
	var n: int = equipment.count_in_slot(slot)
	if n < 2:
		return
	if _split_pop:
		_split_pop.queue_free()
	_split_pop = PopupPanel.new()
	add_child(_split_pop)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(260, 0)
	box.add_theme_constant_override("separation", 8)
	_split_pop.add_child(box)
	var it: Resource = ItemDB.get_item(item_id())
	var title := Label.new()
	title.text = "Split %s (%d)" % [it.display_name if it else item_id(), n]
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = n - 1
	slider.step = 1
	slider.value = maxi(1, n / 2)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(150, 24)
	row.add_child(slider)
	var num := SpinBox.new()
	num.min_value = 1
	num.max_value = n - 1
	num.step = 1
	num.value = slider.value
	row.add_child(num)
	slider.value_changed.connect(func(v: float) -> void: num.set_value_no_signal(v))
	num.value_changed.connect(func(v: float) -> void: slider.set_value_no_signal(v))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: _split_pop.hide())
	buttons.add_child(cancel)
	var ok := Button.new()
	ok.text = "Split"
	ok.pressed.connect(func() -> void:
		var good: bool = is_instance_valid(equipment) and equipment.split_stack(slot, int(slider.value))
		Audio.play("ui.select" if good else "ui.error")
		_split_pop.hide())
	buttons.add_child(ok)
	_split_pop.reset_size()
	_split_pop.position = Vector2i(get_viewport().get_mouse_position())
	_split_pop.popup()
	slider.grab_focus()


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
