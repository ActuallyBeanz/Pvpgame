extends Panel
## One inventory slot (hotbar or bag). Shows the item's icon, count and state frame
## (gold = equipped weapon, teal = worn shield, soft gold = ammo in use).
## While the inventory is open (GameConfig.inventory_open) you can drag its item onto
## any other slot: Equipment.move_item does the move / swap / stack merge.
## Right-click: menu (equip / split / drop). Drag it outside the inventory: drop it on the ground
## (the drop zone lives in weapon_hud.gd). No item logic here.

signal hover_changed(slot: int, on: bool)

const Tooltip := preload("res://ui/item_tooltip.gd")

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
var _craft_hint := ""                      ## while something is dragged over me: what dropping makes
var _hint_label: Label
const CRAFT := Color(0.45, 1.0, 0.55)


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
	_hint_label = _label(12, CRAFT)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint_label.position.y = -20
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
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
	tooltip_text = it.display_name if open else ""     # the real tooltip is _make_custom_tooltip
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
	elif cur_w and it.kind == "ammo" and equipment.current_ammo_id() == id:
		border = IN_USE
		width = 3
	if _hover:
		border = border.lerp(HOVER, 0.6)
		width = maxi(width, 3)
	if not _hover or not get_viewport().gui_is_dragging():
		_craft_hint = ""
	if _craft_hint != "":
		border = CRAFT
		width = 4
	_hint_label.text = ("-> " + _craft_hint) if _craft_hint != "" else ""
	_style.border_color = border
	_style.set_border_width_all(width)
	_style.bg_color = FILLED_BG.lightened(0.12) if width >= 4 or _hover else FILLED_BG
	_icon.modulate = Color(1, 1, 1, 0.35) if _dragging_me() else Color.WHITE
	scale = Vector2.ONE * (1.08 if grow_equipped and id == equipment.sync_weapon_id and not open else 1.0)


## Hover tooltip: everything the item does (ui/item_tooltip.gd builds it from data).
func _make_custom_tooltip(_for_text: String) -> Object:
	var id := item_id()
	if id == "" or get_viewport().gui_is_dragging():
		return null
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.94)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.custom_minimum_size = Vector2(340, 0)
	rt.text = Tooltip.build(equipment, id)
	panel.add_child(rt)
	return panel


func _dragging_me() -> bool:
	if not get_viewport().gui_is_dragging():
		return false
	var d: Variant = get_viewport().gui_get_drag_data()
	return d is Dictionary and d.get("inv_slot", -1) == slot


# ---------------------------------------------------------------- right-click menu
enum Act { EQUIP, UNEQUIP, TO_HOTBAR, SPLIT_HALF, SPLIT_ONE, DROP_ONE, DROP_ALL, SPLIT_CHOOSE, EAT, CRAFT_BASE = 100, AMMO_BASE = 200, LOAD_BASE = 300 }
var _ammo_ids: Array[String] = []          ## menu: arrow types listed for this bow
var _load_bows: Array[String] = []         ## menu: bows these arrows can be loaded into
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
		_menu.add_theme_constant_override("icon_max_width", 32)
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
	_ammo_ids.clear()
	_load_bows.clear()
	if it.kind == "weapon" and it.action_tag == "shoot":
		# arrow type: pick with an icon (the one in use is ticked)
		var opts: Array[String] = equipment.ammo_options(id)
		if opts.size() > 1:
			_menu.add_separator("Arrow type")
			var cur: String = str(equipment.selected_ammo.get(id, opts[0]))
			for a_id in opts:
				var a: Resource = ItemDB.get_item(a_id)
				var n_a := int(equipment.ammo.get(a_id, 0))
				var k := _ammo_ids.size()
				_ammo_ids.append(a_id)
				var tex: Texture2D = icons.get_icon(a_id) if icons else null
				var label: String = "%s (%d)" % [a.display_name if a else a_id, n_a]
				if tex:
					_menu.add_icon_radio_check_item(tex, label, Act.AMMO_BASE + k)
				else:
					_menu.add_radio_check_item(label, Act.AMMO_BASE + k)
				var idx := _menu.get_item_index(Act.AMMO_BASE + k)
				_menu.set_item_checked(idx, a_id == cur)
				_menu.set_item_disabled(idx, n_a <= 0)
			_menu.add_separator()
	if it.kind == "ammo":
		# special arrows: load them into a bow you carry
		for w_id in equipment.inventory:
			var w: Resource = ItemDB.get_item(w_id) if w_id != "" else null
			if w and w.kind == "weapon" and not _load_bows.has(w_id) and equipment.ammo_options(w_id).size() > 1 \
					and equipment.ammo_options(w_id).has(id):
				_menu.add_item("Load into %s" % w.display_name, Act.LOAD_BASE + _load_bows.size())
				_load_bows.append(w_id)
	if it.heal > 0.0:
		_menu.add_item("Eat (+%d)" % roundi(it.heal), Act.EAT)
	var singles: Array = equipment.single_recipes(id)
	for k in singles.size():
		_menu.add_item("Make %s" % equipment.recipe_label(singles[k]), Act.CRAFT_BASE + k)
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
		Act.EAT:
			ok = equipment.eat(slot)
		Act.DROP_ONE:
			ok = equipment.drop_item(slot, 1)
		Act.DROP_ALL:
			ok = equipment.drop_item(slot, 0)
		_:
			if act >= Act.LOAD_BASE:
				var b := act - Act.LOAD_BASE
				ok = b < _load_bows.size()
				if ok:
					equipment.select_ammo(_load_bows[b], id)
			elif act >= Act.AMMO_BASE:
				var k := act - Act.AMMO_BASE
				ok = k < _ammo_ids.size() and int(equipment.ammo.get(_ammo_ids[k], 0)) > 0
				if ok:
					equipment.select_ammo(id, _ammo_ids[k])
			elif act >= Act.CRAFT_BASE:
				var singles: Array = equipment.single_recipes(id)
				var k := act - Act.CRAFT_BASE
				ok = k < singles.size() and equipment.craft_single(singles[k])
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
	var ok: bool = GameConfig.inventory_open and data is Dictionary and data.has("inv_slot")
	_craft_hint = ""
	if ok and is_instance_valid(equipment) and int(data.inv_slot) != slot:
		var from: int = int(data.inv_slot)
		var r: Dictionary = equipment.find_recipe(equipment.inventory[from], item_id())
		if not r.is_empty():
			_craft_hint = equipment.recipe_label(r)   # glow green + show what it makes
	return ok


## Drop: a recipe crafts; otherwise move / swap / merge like before.
func _drop_data(_at: Vector2, data: Variant) -> void:
	if not is_instance_valid(equipment):
		return
	var from := int(data.inv_slot)
	_craft_hint = ""
	if equipment.try_craft(from, slot):
		return
	Audio.play("ui.hover" if equipment.move_item(from, slot) else "ui.error")
