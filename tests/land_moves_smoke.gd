extends Node
## OoT land moves on the test course: hop up the 1/2/3 m steps, tall-climb the 3 m
## platform, back off its edge while focused (ledge grab) and pull up, jump into the
## platform wall (air grab) and drop, sidehop, backflip, sprint-start roll, and
## focus free-look (camera turns, body stays on its plane). Prints PASS/FAIL.
##   godot --headless res://tests/land_moves_smoke.tscn

const Motor := preload("res://scenes/player/movement_motor.gd")

var _step := 0
var _t := 0.0
var _player: CharacterBody3D
var _m: Motor
var _p0 := Vector3.ZERO
var _seen := {}
var _fails: PackedStringArray = []


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Lobby.local_profile = { "name": "Climber", "color": 4 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _physics_process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _t > 8.0:
		_fail("timeout at step %d (state %d, pos %s)" % [_step, _m.state if _m else -1, _player.global_position if _player else Vector3.ZERO])
		_finish()
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _m:
		_seen[_m.state] = true
	match _step:
		0:
			if scene.has_node("Players/1") and scene.get_node("Players/1").is_on_floor():
				_player = scene.get_node("Players/1")
				_m = _player.motor
				_player.focus.default_lock_range = 0.0  # movement test: free focus only
				_teleport(Vector3(12, 0.1, -5), 0.0)  # in front of the 1/2/3 m steps, facing -Z
				_next()
		1:  # walk up the staircase: three 1 m hop-ups
			Input.action_press("move_forward")
			if _player.global_position.y > 2.9 and _m.state == Motor.State.GROUND and _player.is_on_floor():
				Input.action_release("move_forward")
				print("[land] climbed the 1/2/3 m steps in %.2fs" % _t)
				_teleport(Vector3(5.5, 0.1, -22), PI * 0.5)  # east of the 3 m platform, facing -X
				_next()
		2:  # tall climb onto the 3 m platform
			Input.action_press("move_forward")
			if _player.global_position.y > 2.9 and _m.state == Motor.State.GROUND and _player.is_on_floor():
				Input.action_release("move_forward")
				print("[land] tall-climbed the 3 m platform in %.2fs (saw CLIMB=%s)" % [_t, _seen.has(Motor.State.CLIMB)])
				_next()
		3:  # focus and back off the east edge -> ledge grab
			Input.action_press("focus")
			if _t > 0.15:
				Input.action_press("move_back")
			if _m.state == Motor.State.HANG:
				Input.action_release("move_back")
				print("[land] back-off ledge grab: hanging, feet at y=%.2f" % _player.global_position.y)
				_next()
		4:  # pull up
			if _t > 0.35:
				Input.action_press("move_forward")
			if _t > 0.4 and _m.state == Motor.State.GROUND and _player.global_position.y > 2.9:
				Input.action_release("move_forward")
				Input.action_release("focus")
				print("[land] pulled up onto the ledge after %.2fs" % _t)
				_teleport(Vector3(9.0, 0.1, -22), PI * 0.5)
				_next()
		5:  # running jump into the platform wall -> air grab
			if _t > 0.15:
				Input.action_press("move_forward")
			if not _seen.has("jumped") and _player.global_position.x < 5.6:
				_seen["jumped"] = true
				Input.action_press("jump")  # held: full-height jump
			if _m.state == Motor.State.HANG:
				Input.action_release("move_forward")
				Input.action_release("jump")
				print("[land] jumped into the wall and grabbed the ledge (feet y=%.2f)" % _player.global_position.y)
				_next()
		6:  # drop
			if _t > 0.35:
				Input.action_press("move_back")
			if _t > 0.5 and _player.is_on_floor() and _m.state == Motor.State.GROUND:
				Input.action_release("move_back")
				print("[land] dropped from the ledge")
				_teleport(Vector3(-3, 0.1, 3), 0.0)
				_next()
		7:  # sidehop right = jump + right while focused
			Input.action_press("focus")
			if _t > 0.2 and _t < 0.25:
				_p0 = _player.global_position
				Input.action_press("move_right")
				Input.action_press("jump")
			if _t > 0.3:
				Input.action_release("jump")
				Input.action_release("move_right")
			if _t > 1.0:
				var d := _player.global_position - _p0
				print("[land] sidehop right: %.2fm sideways (x %+.2f), facing kept %s" % [Vector2(d.x, d.z).length(), d.x, absf(_m.facing) < 0.05])
				if d.x < 2.5 or _player.sync_action != 11:
					_fail("sidehop wrong")
				_next()
		8:  # backflip = jump + back while focused
			if _t > 0.1 and _t < 0.15:
				_p0 = _player.global_position
				Input.action_press("move_back")
				Input.action_press("jump")
			if _t > 0.2:
				Input.action_release("jump")
				Input.action_release("move_back")
			if _t > 1.1:
				var d := _player.global_position - _p0
				print("[land] backflip: %.2fm back (z %+.2f), action %d" % [Vector2(d.x, d.z).length(), d.z, _player.sync_action])
				if d.z < 2.5 or _player.sync_action != 12:
					_fail("backflip wrong")
				Input.action_release("focus")
				_next()
		9:  # focus turns you to face the camera's direction
			if _t < 0.05:
				_player.camera_rig._yaw = PI * 0.5  # camera looking toward -X
			if _t > 0.1:
				Input.action_press("focus")
			if _t > 0.7:
				print("[land] focus: camera yaw 90°, body turned to %.1f°" % rad_to_deg(_m.facing))
				if absf(angle_difference(_m.facing, PI * 0.5)) > 0.05:
					_fail("focus should turn the body toward the camera direction")
				_next()
		10:  # free look while focused: turn the camera, body keeps its plane
			if _t < 0.05:
				_player.camera_rig._note_look(100.0)
				_player.camera_rig._yaw += PI * 0.5
				_p0 = _player.global_position
			Input.action_press("move_forward")
			if _t > 0.6:
				Input.action_release("move_forward")
				var d := _player.global_position - _p0
				print("[land] free look: camera turned 90° more, moved (%.2f, %.2f), body yaw %.1f°" % [d.x, d.z, rad_to_deg(_m.facing)])
				if d.x > -0.5 or absf(d.z) > 0.3 or absf(angle_difference(_m.facing, PI * 0.5)) > 0.05:
					_fail("focus free-look should keep the body's plane")
				_next()
		11:  # roll while focused: roll left, come out facing left
			if _t < 0.05:
				_player.camera_rig._yaw = PI * 0.5  # camera back behind the body
			if _t > 0.1 and _t < 0.15:
				Input.action_press("move_left")
				Input.action_press("roll")
			if _t > 0.2:
				Input.action_release("roll")
			if _t > 0.25 and _t < 0.3 and _m.state != Motor.State.ROLL:
				_fail("no roll while focused")
			if _t > 1.2:
				Input.action_release("move_left")
				# focused facing -X (90°); "left" of that is +Z (180°)
				var ok := absf(angle_difference(_m.facing, PI)) < 0.1
				var lib_ok: bool = _player.model_root.get_child(0).anim.has_animation(&"oot/OoT_Roll")
				print("[land] focused roll: came out facing %.1f° (expected 180), roll anim loaded %s" % [rad_to_deg(_m.facing), lib_ok])
				if not ok or not lib_ok:
					_fail("focused roll facing / animation")
				Input.action_release("focus")
				_teleport(Vector3(-3, 0.1, 6), 0.0)
				_next()
		12:  # roll steers with the camera: roll forward, swivel the camera 90° mid-roll
			if _t > 0.1:
				Input.action_press("move_forward")
			if _t > 0.1 and _t < 0.15:
				Input.action_press("roll")
			if _t > 0.2:
				Input.action_release("roll")
			if _t > 0.3 and _t < 0.35:
				_player.camera_rig._yaw = PI * 0.5  # mouse swivel to the left mid-roll
			if _t > 0.75 and not _seen.has("steer"):
				_seen["steer"] = true
				print("[land] roll steer: heading %.1f° after a 90° camera swivel mid-roll (state %d)" % [rad_to_deg(_m.heading), _m.state])
				if _m.state != Motor.State.ROLL or rad_to_deg(_m.heading) < 60.0:
					_fail("roll didn't follow the camera")
			if _t > 1.3:
				Input.action_release("move_forward")
				_teleport(Vector3(-3, 0.1, 6), 0.0)
				_next()
		13:  # air control: standing jump, then push right mid-air
			if _t > 0.1 and _t < 0.15:
				_p0 = _player.global_position
				Input.action_press("jump")
			if _t > 0.25:
				Input.action_press("move_right")
			if _t > 0.1 and _player.is_on_floor() and _t > 0.5 and not _seen.has("air"):
				_seen["air"] = true
				Input.action_release("jump")
				Input.action_release("move_right")
				var d := _player.global_position - _p0
				print("[land] air control: standing jump + right mid-air drifted %.2fm sideways" % d.x)
				if d.x < 0.8:
					_fail("no air control")
				_teleport(Vector3(-3, 0.1, 6), 0.0)
				_next()
		14:  # sprint start rolls first
			if _t > 0.2:
				Input.action_press("move_forward")
				Input.action_press("sprint")
			if _t > 0.25 and _t < 0.3 and _m.state != Motor.State.ROLL:
				_fail("sprint start did not roll (state %d)" % _m.state)
			if _t > 1.4:
				print("[land] sprint start: rolled, then sprinting at %.2f m/s" % _m.speed)
				if _m.speed < 8.5:
					_fail("not sprinting after the roll")
				Input.action_release("move_forward")
				Input.action_release("sprint")
				_finish()


func _fail(msg: String) -> void:
	print("[land] problem: " + msg)
	_fails.append(msg)


func _finish() -> void:
	var ok := _fails.is_empty()
	print("[land] %s %s" % ["PASS" if ok else "FAIL", "all land moves OK" if ok else ", ".join(_fails)])
	for a in ["focus", "move_forward", "move_back", "move_left", "move_right", "roll", "jump", "sprint"]:
		Input.action_release(a)
	set_physics_process(false)
	get_tree().quit(0 if ok else 1)


func _teleport(pos: Vector3, yaw: float) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_m.reset(yaw)
	_player.camera_rig._yaw = yaw
	_player.camera_rig._pitch = deg_to_rad(-15)
	_player.reset_physics_interpolation()


func _next() -> void:
	_step += 1
	_t = 0.0
