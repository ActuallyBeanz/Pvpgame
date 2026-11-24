extends HBoxContainer
## 9-slot hotbar along the bottom (keys 1-9): weapons, shield, ammo with icon + count.
## Equipped weapon = gold frame, worn shield = teal, ammo in use = soft gold.
## With the inventory open (Tab) its slots also take drag & drop (ui/inventory_slot.gd).

const ItemIcons := preload("res://ui/item_icons.gd")
const Slot := preload("res://ui/inventory_slot.gd")

signal slot_hovered(slot: int, on: bool)

@export var slot_size := 64

var equipment: Node
var icons: Node
var slots: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	icons = ItemIcons.new()
	icons.name = "ItemIcons"
	add_child(icons)
	for i in 9:
		var s := Slot.new()
		s.name = "Slot%d" % (i + 1)
		s.setup(i, slot_size, str(i + 1), icons)
		s.hover_changed.connect(func(slot: int, on: bool) -> void: slot_hovered.emit(slot, on))
		add_child(s)
		slots.append(s)


func _process(_delta: float) -> void:
	visible = is_instance_valid(equipment)
	if not visible:
		return
	for s in slots:
		s.equipment = equipment
		s.refresh()
