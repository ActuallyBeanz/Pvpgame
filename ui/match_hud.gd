extends CanvasLayer
## In-match HUD: pause menu (Esc), Tab inventory + mouse capture handling.
## Owns GameConfig.gameplay_input_enabled (paused) and GameConfig.inventory_open
## (Tab: mouse is free for the inventory, you can still walk around).

@onready var pause_panel: Control = %PausePanel
@onready var resume_button: Button = %ResumeButton
@onready var leave_button: Button = %LeaveButton


const WeaponHud := preload("res://ui/weapon_hud.tscn")
const SettingsPanel := preload("res://ui/settings_panel.gd")


func _ready() -> void:
	GameConfig.inventory_open = false
	add_child(WeaponHud.instantiate())
	move_child(get_child(-1), 0)  # under the pause menu
	pause_panel.hide()
	GameConfig.gameplay_input_enabled = true
	resume_button.pressed.connect(_resume)
	leave_button.pressed.connect(func() -> void: NetworkManager.leave("You left the match."))
	var settings := SettingsPanel.new()
	settings.name = "Settings"
	settings.hide()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_panel.add_child(center)
	center.add_child(settings)
	var vbox := resume_button.get_parent()
	var sbtn := Button.new()
	sbtn.text = "Settings"
	sbtn.custom_minimum_size = resume_button.custom_minimum_size
	vbox.add_child(sbtn)
	vbox.move_child(sbtn, leave_button.get_index())
	sbtn.pressed.connect(func() -> void:
		vbox.get_parent().hide()
		settings.show())
	settings.closed.connect(func() -> void: vbox.get_parent().show())


## Kill feed line (fades out) and the big end-of-match banner.
func show_feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.position.y += 60 + 28 * get_tree().get_nodes_in_group("feed_lines").size()
	l.add_to_group("feed_lines")
	add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func show_banner(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 56)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position.y -= 120
	add_child(l)


func _exit_tree() -> void:
	GameConfig.gameplay_input_enabled = true
	GameConfig.inventory_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## _input (not unhandled) so Tab never reaches GUI focus navigation, and Esc closes
## the inventory before it can open the pause menu.
func _input(event: InputEvent) -> void:
	if pause_panel.visible:
		return
	if event.is_action_pressed("inventory") and not event.is_echo():
		set_inventory_open(not GameConfig.inventory_open)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and GameConfig.inventory_open:
		set_inventory_open(false)
		get_viewport().set_input_as_handled()


func set_inventory_open(on: bool) -> void:
	GameConfig.inventory_open = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	Audio.play("ui.select" if on else "ui.back")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if pause_panel.visible:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not pause_panel.visible \
			and not GameConfig.inventory_open \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # click back into the game


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not pause_panel.visible:
		_pause()


func _pause() -> void:
	GameConfig.inventory_open = false
	pause_panel.show()
	resume_button.grab_focus()
	GameConfig.gameplay_input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	pause_panel.hide()
	GameConfig.gameplay_input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
