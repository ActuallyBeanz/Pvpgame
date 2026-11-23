extends CanvasLayer
## In-match HUD: pause menu (Esc) + mouse capture handling.
## Owns GameConfig.gameplay_input_enabled so gameplay stops reading input while paused.

@onready var pause_panel: Control = %PausePanel
@onready var resume_button: Button = %ResumeButton
@onready var leave_button: Button = %LeaveButton


const WeaponHud := preload("res://ui/weapon_hud.tscn")


func _ready() -> void:
	add_child(WeaponHud.instantiate())
	move_child(get_child(-1), 0)  # under the pause menu
	pause_panel.hide()
	GameConfig.gameplay_input_enabled = true
	resume_button.pressed.connect(_resume)
	leave_button.pressed.connect(func() -> void: NetworkManager.leave("You left the match."))


func _exit_tree() -> void:
	GameConfig.gameplay_input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if pause_panel.visible:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not pause_panel.visible \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # click back into the game


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not pause_panel.visible:
		_pause()


func _pause() -> void:
	pause_panel.show()
	resume_button.grab_focus()
	GameConfig.gameplay_input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	pause_panel.hide()
	GameConfig.gameplay_input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
