extends Node
## Real match: host alone -> test arena -> press `, type, Enter; checks the game keeps running.
var _step := 0
var _t := 0.0
var _frames := 0


func _ready() -> void:
	if get_tree().current_scene == self:
		var driver: Node = get_script().new()
		get_tree().root.add_child.call_deferred(driver)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	Lobby.local_profile = { "name": "Solo", "color": 3 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _key(code: Key, uni := 0) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni if pressed else 0
		e.pressed = pressed
		Input.parse_input_event(e)


func _process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	_frames += 1
	if _t > 40.0:
		print("[m] TIMEOUT step %d" % _step)
		get_tree().quit()
	match _step:
		0:
			var scene := get_tree().current_scene
			if scene and scene.has_node("Players/1") and _t > 4.0:
				print("[m] in match: ", scene.name, " paused=", get_tree().paused)
				_key(KEY_QUOTELEFT, 96)
				_t = 0.0
				_step = 1
		1:
			if _t > 0.5:
				print("[m] after backtick: open=", BugReporter._open, " paused=", get_tree().paused, " frames ok")
				for ch in "test":
					_key(OS.find_keycode_from_string(ch.to_upper()), ch.unicode_at(0))
				_t = 0.0
				_step = 2
		2:
			if _t > 0.5:
				print("[m] typed: '", BugReporter._note, "'")
				_key(KEY_ENTER)
				_t = 0.0
				_step = 3
		3:
			if _t > 3.0:
				print("[m] after Enter: open=", BugReporter._open, " input=", GameConfig.gameplay_input_enabled, " frames=", _frames)
				get_tree().quit()
