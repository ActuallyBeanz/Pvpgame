extends Control
## Weapon HUD: crosshair (while drawn), bow draw-power bar, weapon/ammo line, pickup
## prompt, and OoT-style letterbox bars while focusing (hold RMB).
## Reads the local player's Equipment / Focus every frame; no gameplay logic here.

@export var crosshair_color := Color(1, 1, 1, 0.9)
@export var charge_full_color := Color(1.0, 0.82, 0.3)
@export var hook_color := Color(1.0, 0.3, 0.25)       ## crosshair over something the grapple can latch
@export var focus_bar_height := 0.075      ## fraction of screen height per bar
@export var focus_bar_speed := 10.0

@onready var crosshair: Control = %Crosshair
@onready var charge_bar: ProgressBar = %ChargeBar
@onready var ammo_label: Label = %AmmoLabel
@onready var prompt_label: Label = %PromptLabel

var _player: Node
var _equipment: Node
var _bars: Array[ColorRect] = []
var _bar := 0.0


const Hotbar := preload("res://ui/hotbar.gd")
const InventoryPanel := preload("res://ui/inventory_panel.gd")

var _hotbar: Control
var inventory: Control                     ## Tab bag panel (ui/inventory_panel.gd)


func _ready() -> void:
	_hotbar = Hotbar.new()
	_hotbar.name = "Hotbar"
	add_child(_hotbar)
	_hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hotbar.offset_bottom = -14
	inventory = InventoryPanel.new()
	inventory.name = "Inventory"
	inventory.icons = _hotbar.icons
	add_child(inventory)
	inventory.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	inventory.grow_horizontal = Control.GROW_DIRECTION_BOTH
	inventory.grow_vertical = Control.GROW_DIRECTION_BEGIN
	inventory.offset_bottom = -96             # sits right above the hotbar
	_hotbar.slot_hovered.connect(inventory.set_hovered)
	for top in [true, false]:
		var r := ColorRect.new()
		r.color = Color(0, 0, 0, 0.92)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		move_child(r, 0)
		r.set_meta("top", top)
		_bars.append(r)


func _process(delta: float) -> void:
	if not is_instance_valid(_equipment):
		_player = _find_local_player()
		_equipment = _player.get_node_or_null("Equipment") if _player else null
		_hotbar.equipment = _equipment
		inventory.equipment = _equipment
		if _equipment == null:
			visible = false
			return
	visible = true
	_update_bars(delta)
	var w: Resource = _equipment.weapon()
	var kind: String = _equipment.weapon_type()
	var drawn: bool = _equipment.sync_drawn and w != null
	var locked: bool = _player.focus.target != null
	# Homing throws don't need a crosshair while locked; the bow always aims by hand.
	crosshair.visible = drawn and kind != "slash" and not (kind == "throw" and (_equipment.sync_thrown or (locked and not _equipment.sync_aiming)))
	var power := 0.0
	if kind == "shoot":
		power = _equipment.stats().charge_to_power(_equipment.charge)
	charge_bar.visible = kind == "shoot" and drawn and _equipment.charge > 0.0
	charge_bar.value = power * 100.0
	charge_bar.modulate = charge_full_color if _equipment.charge >= 1.0 else Color.WHITE
	crosshair.modulate = crosshair_color
	if kind == "hook" and _equipment.hook.aim_on_hookable():
		crosshair.modulate = hook_color   # red: the claw would stick there
	crosshair.scale = Vector2.ONE * lerpf(1.6, 0.8, power) if kind == "shoot" and drawn else Vector2.ONE
	ammo_label.text = _weapon_line(w, kind)
	ammo_label.visible = not GameConfig.inventory_open
	prompt_label.visible = not GameConfig.inventory_open
	var p: Node = _equipment.nearest_pickup
	if p:
		prompt_label.text = "[E] Pick up %s" % p.display_name()
	elif drawn and _player.focus.active and not locked:
		prompt_label.text = "No target in range"
	else:
		prompt_label.text = ""


func _weapon_line(w: Resource, kind: String) -> String:
	if w == null:
		return ""
	var status := ""
	match kind:
		"shoot":
			status = "fire arrow!" if _equipment.sync_arrow_element == "fire" else "hold LMB to draw"
		"throw":
			status = "returning..." if _equipment.sync_thrown else "hold LMB: sweep to pick targets"
		"hook":
			var hk: Node = _equipment.hook
			if hk.pulling():
				status = "reeling in..."
			elif hk.busy():
				status = "chain out..."
			else:
				status = "hold LMB aim · release: fire (%.0fm)" % _equipment.stats().max_range
		"slash":
			status = "charged! release" if _equipment.melee.charged else ("charging..." if _equipment.melee.charging else "LMB combo · hold: spin")
	var sh: Resource = _equipment.shield_item()
	var shield := "   ·   RMB/F shield" if sh and (kind == "slash" or not _equipment.sync_drawn) else ""
	return "%s   ·   %s%s   ·   [Q] %s" % [w.display_name, status, shield, "holster" if _equipment.sync_drawn else "draw"]


func _update_bars(delta: float) -> void:
	var on: bool = _player.focus.active
	_bar = lerpf(_bar, 1.0 if on else 0.0, 1.0 - exp(-focus_bar_speed * delta))
	var h := size.y * focus_bar_height * _bar
	for r in _bars:
		r.visible = h > 0.5
		r.size = Vector2(size.x, h)
		r.position = Vector2(0, 0 if r.get_meta("top") else size.y - h)


func _find_local_player() -> Node:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_node("Players"):
		return null
	return scene.get_node("Players").get_node_or_null(str(multiplayer.get_unique_id()))
