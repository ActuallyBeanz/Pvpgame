extends Control
## Weapon HUD: crosshair (while drawn), bow draw-power bar, weapon/ammo line, pickup
## prompt, and OoT-style letterbox bars while focusing (hold RMB).
## Reads the local player's Equipment / Focus every frame; no gameplay logic here.

@export var crosshair_color := Color(1, 1, 1, 0.9)
@export var charge_full_color := Color(1.0, 0.82, 0.3)
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


func _ready() -> void:
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
	crosshair.scale = Vector2.ONE * lerpf(1.6, 0.8, power) if kind == "shoot" and drawn else Vector2.ONE
	ammo_label.text = _weapon_line(w, kind)
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
	var slots := PackedStringArray()
	for i in _equipment.weapons.size():
		var it: Resource = ItemDB.get_item(_equipment.weapons[i])
		var mark := ">" if _equipment.weapons[i] == _equipment.sync_weapon_id else " "
		slots.append("%s[%d] %s" % [mark, i + 1, it.display_name if it else "?"])
	var status := ""
	match kind:
		"shoot":
			status = "Arrows %d" % _equipment.ammo_count()
		"throw":
			status = "returning..." if _equipment.sync_thrown else "hold LMB: sweep to pick targets"
		"slash":
			status = "charged! release" if _equipment.melee.charged else ("charging..." if _equipment.melee.charging else "LMB combo · hold: spin")
	var sh: Resource = _equipment.shield_item()
	var shield := "   ·   [F] %s" % sh.display_name if sh else ""
	return "%s   ·   %s%s   [Q] %s" % ["  ".join(slots), status, shield, "holster" if _equipment.sync_drawn else "draw"]


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
