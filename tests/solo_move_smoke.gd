extends Node
## Headless: host alone -> Start -> walk forward, sprint, jump. Prints PASS/FAIL.
##   godot --headless res://tests/solo_move_smoke.tscn

var _step := 0
var _t := 0.0
var _player: CharacterBody3D
var _start := Vector3.ZERO
var _peak_y := 0.0


func _ready() -> void:
	if get_tree().current_scene == self:
		var driver: Node = get_script().new()
		get_tree().root.add_child.call_deferred(driver)
		return
	Lobby.local_profile = { "name": "Solo", "color": 3 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	if NetworkManager.host() != OK:
		_done(false, "host failed")


func _physics_process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _t > 20.0:
		_done(false, "timeout at step %d" % _step)
		return
	match _step:
		0:  # wait for spawn + landing
			var scene := get_tree().current_scene
			if scene and scene.has_node("Players/1"):
				_player = scene.get_node("Players/1")
				if _player.is_on_floor():
					_start = _player.global_position
					Input.action_press("move_forward")
					Input.action_press("sprint")
					_t = 0.0
					_step = 1
		1:  # sprint forward for 1s
			if _t > 1.0:
				Input.action_release("move_forward")
				Input.action_release("sprint")
				var moved := _start.distance_to(_player.global_position)
				print("[solo] moved %.2fm in 1s (sprint)" % moved)
				if moved < 5.0:
					_done(false, "barely moved")
					return
				_start = _player.global_position
				_peak_y = _start.y
				Input.action_press("jump")
				_t = 0.0
				_step = 2
		2:  # hold jump, track apex
			_peak_y = maxf(_peak_y, _player.global_position.y)
			if _t > 0.8:
				Input.action_release("jump")
				var h := _peak_y - _start.y
				print("[solo] jump height %.2fm, grounded again: %s" % [h, _player.is_on_floor()])
				_done(h > 1.0, "solo host + movement OK" if h > 1.0 else "jump too low")


func _done(ok: bool, msg: String) -> void:
	print("[solo] %s %s" % ["PASS" if ok else "FAIL", msg])
	set_physics_process(false)
	get_tree().quit(0 if ok else 1)
