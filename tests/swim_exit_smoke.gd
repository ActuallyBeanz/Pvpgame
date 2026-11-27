extends Node
## Real island match: drop the player in the water facing a bank, hold forward, check they
## climb out (or don't, for a sheer cliff). Prints PASS/FAIL per case.
##   godot --headless res://tests/swim_exit_smoke.tscn

## [name, start xz (in the water), face toward xz, should get out]
var cases := [
	["west canyon ramp", Vector2(-179, -88), Vector2(-179, -104), true],
	["beach ramp", Vector2(-122, 188), Vector2(-125.5, 175.5), true],
	["new north trench", Vector2(-91, -96), Vector2(-91, -120), true],
	["steep low bank", Vector2(-142, 170), Vector2(-130, 170), true],
	["gorge cliff", Vector2(-105, -93), Vector2(-105, -80), false],
]
var _i := 0
var _t := 0.0
var _phase := 0
var _player: CharacterBody3D
var _fails := 0


func _ready() -> void:
	if get_tree().current_scene == self:
		var driver: Node = get_script().new()
		get_tree().root.add_child.call_deferred(driver)
		return
	Lobby.local_profile = { "name": "Solo", "color": 3 }
	Lobby.match_scene = "res://scenes/match/island.tscn"
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _physics_process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _player == null:
		var scene := get_tree().current_scene
		if scene and scene.has_node("Players/1") and _t > 3.0:
			_player = scene.get_node("Players/1")
			_t = 0.0
		elif _t > 40.0:
			print("[swim] FAIL no player")
			get_tree().quit(1)
		return
	if _i >= cases.size():
		print("[swim] DONE %d fail(s)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	var c: Array = cases[_i]
	var start: Vector2 = c[1]
	var face: Vector2 = c[2]
	match _phase:
		0:
			Input.action_release("move_forward")
			_player.global_position = Vector3(start.x, -1.2, start.y)
			_player.velocity = Vector3.ZERO
			var d := (face - start).normalized()
			_player.camera_rig._yaw = atan2(-d.x, -d.y)
			_t = 0.0
			_phase = 1
		1:
			if _t > 0.6:
				Input.action_press("move_forward")
				_t = 0.0
				_phase = 2
		2:
			var st: int = _player.motor.state
			var out: bool = st != 6 and st != 7 and _player.global_position.y > 0.4 and _player.is_on_floor()
			if out or _t > 9.0:
				var ok: bool = out == bool(c[3])
				if not ok:
					_fails += 1
				print("[swim] %s %s: out=%s at %s after %.1fs (state %d)" % ["PASS" if ok else "FAIL", c[0], out,
					_player.global_position.snapped(Vector3.ONE * 0.1), _t, st])
				Input.action_release("move_forward")
				_i += 1
				_phase = 0
