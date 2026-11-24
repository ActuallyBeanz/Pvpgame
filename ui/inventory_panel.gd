extends PanelContainer
## Tab inventory: the bag grid that opens above the hotbar. Drag items between any bag
## and hotbar slot to move / swap them; hover an item and press 1-9 to drop it on that
## hotbar slot. You keep walking while it's open (see GameConfig.inventory_open);
## match_hud.gd opens / closes it (Tab, Esc).

const Slot := preload("res://ui/inventory_slot.gd")

@export var columns := 9
@export var slot_size := 64

var equipment: Node
var icons: Node                             ## shared with the hotbar (one icon renderer)
var slots: Array = []
var hovered := -1

var _grid: GridContainer
var _name_label: Label
var _built := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # empty space: clicks fall through to the world
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.05, 0.08, 0.78)
	bg.set_corner_radius_all(12)
	bg.set_border_width_all(2)
	bg.border_color = Color(1.0, 0.85, 0.45, 0.35)
	bg.content_margin_left = 14
	bg.content_margin_right = 14
	bg.content_margin_top = 10
	bg.content_margin_bottom = 12
	add_theme_stylebox_override("panel", bg)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var title := _label("Inventory", 20, Color(1.0, 0.88, 0.55))
	head.add_child(title)
	_name_label = _label("", 16, Color(1, 1, 1, 0.9))
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_name_label)
	head.add_child(_label("drag to move  ·  hover + 1-9: to hotbar  ·  Tab / Esc close", 12, Color(1, 1, 1, 0.55)))
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_grid)
	hide()


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Bag slots = every inventory slot after the hotbar.
func _build() -> void:
	_built = true
	for i in range(equipment.inventory_size, equipment.inventory.size()):
		var s := Slot.new()
		s.name = "Bag%d" % (i - equipment.inventory_size + 1)
		s.setup(i, slot_size, "", icons)
		s.grow_equipped = false
		s.hover_changed.connect(set_hovered)
		_grid.add_child(s)
		slots.append(s)


func set_hovered(slot: int, on: bool) -> void:
	if on:
		hovered = slot
	elif hovered == slot:
		hovered = -1


func _process(_delta: float) -> void:
	visible = GameConfig.inventory_open and is_instance_valid(equipment)
	if not is_instance_valid(equipment):
		return
	if not _built:
		_build()
	if not GameConfig.inventory_open:
		hovered = -1
	equipment.ui_hover_slot = hovered
	if not visible:
		return
	for s in slots:
		s.equipment = equipment
		s.refresh()
	var id: String = equipment.inventory[hovered] if hovered >= 0 else ""
	var it: Resource = ItemDB.get_item(id) if id != "" else null
	_name_label.text = it.display_name if it else ""
