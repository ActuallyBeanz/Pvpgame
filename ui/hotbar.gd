extends HBoxContainer
## 9-slot hotbar along the bottom: every item you hold (weapons, shield, ammo) with
## its icon, slot key and count. Equipped weapon = gold frame, worn shield = teal frame,
## ammo your weapon is using = soft gold. Reads the local player's Equipment; no logic.

const ItemIcons := preload("res://ui/item_icons.gd")

@export var slot_size := 64
@export var equipped_color := Color(1.0, 0.8, 0.25)
@export var worn_color := Color(0.35, 0.9, 0.95)
@export var in_use_color := Color(1.0, 0.85, 0.45, 0.55)
@export var empty_color := Color(0.05, 0.05, 0.08, 0.45)
@export var filled_color := Color(0.08, 0.08, 0.12, 0.7)

var equipment: Node
var _icons: Node
var _slots: Array = []        ## [{panel, style, icon, key, count, name}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	_icons = ItemIcons.new()
	_icons.name = "ItemIcons"
	add_child(_icons)
	for i in 9:
		_slots.append(_make_slot(i))


func _make_slot(i: int) -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(slot_size, slot_size)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = empty_color
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.15)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6
	icon.offset_top = 6
	icon.offset_right = -6
	icon.offset_bottom = -6
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	var name_lbl := _label(panel, 11, Color(1, 1, 1, 0.8))   # fallback when no icon (headless)
	name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	var key := _label(panel, 13, Color(1, 1, 1, 0.7))
	key.text = str(i + 1)
	key.position = Vector2(5, 1)
	var count := _label(panel, 15, Color(1, 1, 1))
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -40
	count.offset_top = -22
	count.offset_right = -5
	count.offset_bottom = -2
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return { "panel": panel, "style": style, "icon": icon, "key": key, "count": count, "name": name_lbl }


func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _process(_delta: float) -> void:
	visible = is_instance_valid(equipment)
	if not visible:
		return
	var inv: Array = equipment.inventory
	var cur_w: Resource = equipment.weapon()
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var id: String = inv[i] if i < inv.size() else ""
		var it: Resource = ItemDB.get_item(id) if id != "" else null
		var style: StyleBoxFlat = s.style
		var icon: TextureRect = s.icon
		if it == null:
			icon.texture = null
			s.name.text = ""
			s.count.text = ""
			style.bg_color = empty_color
			style.border_color = Color(1, 1, 1, 0.12)
			style.set_border_width_all(2)
			s.panel.scale = Vector2.ONE
			continue
		icon.texture = _icons.get_icon(id)
		s.name.text = "" if icon.texture else it.display_name
		s.count.text = _count_text(it)
		style.bg_color = filled_color
		var border := Color(1, 1, 1, 0.3)
		var width := 2
		if id == equipment.sync_weapon_id:
			border = equipped_color
			width = 4
		elif id == equipment.sync_shield_id:
			border = worn_color
			width = 3
		elif cur_w and it.kind == "ammo" and cur_w.ammo_item_id == id:
			border = in_use_color
			width = 3
		style.border_color = border
		style.set_border_width_all(width)
		style.bg_color = filled_color.lightened(0.12) if width >= 4 else filled_color
		s.panel.pivot_offset = s.panel.size * 0.5
		s.panel.scale = Vector2.ONE * (1.08 if id == equipment.sync_weapon_id else 1.0)


func _count_text(it: Resource) -> String:
	if it.kind == "ammo":
		return str(int(equipment.ammo.get(it.id, 0)))
	if it.kind == "weapon" and it.ammo_item_id != "":
		return ""
	return ""
