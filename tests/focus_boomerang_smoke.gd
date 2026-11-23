extends Node
## Focus + boomerang test: free focus strafes without turning -> pick up the Gyrewing
## -> hold focus near a training dummy (locks on) -> throw -> it hits the dummy and
## comes back -> sidehop while focused. Prints PASS/FAIL.
##   godot --headless res://tests/focus_boomerang_smoke.tscn

var _step := 0
var _t := 0.0
var _player: CharacterBody3D
var _eq: Node
var _dummy: Node3D
var _hits0 := 0
var _yaw0 := 0.0
var _pos0 := Vector3.ZERO
var _saw_return := false
var _rolled := false


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Lobby.local_profile = { "name": "Thrower", "color": 2 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _physics_process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _t > 15.0:
		_done(false, "timeout at step %d" % _step)
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	match _step:
		0:  # spawned & grounded -> stand in open ground facing -Z, start free focus
			if scene.has_node("Players/1") and scene.get_node("Players/1").is_on_floor():
				_player = scene.get_node("Players/1")
				_eq = _player.get_node("Equipment")
				_player.focus.default_lock_range = 0.0  # free-focus part: nothing in range
				_teleport(Vector3(-3, 0.1, 3), 0.0)
				_next()
		1:
			if _t > 0.4:
				Input.action_press("focus")
				_next()
		2:
			if _t > 0.2:
				_yaw0 = _player.motor.facing
				_pos0 = _player.global_position
				Input.action_press("move_right")
				_next()
		3:
			if _t > 0.8:
				Input.action_release("move_right")
				var moved := _player.global_position - _pos0
				var turned := absf(angle_difference(_yaw0, _player.motor.facing))
				print("[focus] free focus: target=%s, strafed %.2fm sideways at %.2f m/s, body turned %.1f°" % [
					_player.focus.target, moved.x, _player.motor.speed, rad_to_deg(turned)])
				if _player.focus.target != null or moved.x < 1.0 or turned > 0.05:
					_done(false, "free focus should strafe without turning or locking")
					return
				Input.action_release("focus")
				_next()
		4:  # grab a Gyrewing
			var pick: Node3D = null
			for p in get_tree().get_nodes_in_group("pickups"):
				if p.item_id == "boomerang_basic":
					pick = p
					break
			if pick == null:
				_done(false, "no boomerang pickup")
				return
			_teleport(pick.global_position + Vector3(1.0, 0.1, 0), 0.0)
			_next()
		5:
			if _t > 0.3:
				Input.action_press("interact")
				_next()
		6:
			Input.action_release("interact")
			if _eq.sync_weapon_id == "boomerang_basic" and _t > 0.5:
				print("[focus] picked up %s, drawn=%s" % [_eq.weapon().display_name, _eq.sync_drawn])
				# 9m in front of Dummy_1 (7,0,5), looking at it
				_dummy = scene.get_node("Props/Dummy_1")
				var stand := _dummy.global_position + Vector3(-9.0, 0.1, 0.0)
				_teleport(stand, atan2(-1.0, 0.0))
				_next()
			elif _t > 3.0:
				_done(false, "boomerang pickup not granted")
		7:
			if _t > 0.5:
				Input.action_press("focus")
				_next()
		8:
			if _t > 0.3:
				print("[focus] lock target: %s (lock range %.0fm)" % [_player.focus.target.name if _player.focus.target else "none", _eq.lock_on_range()])
				if _player.focus.target != _dummy:
					_done(false, "did not lock on to Dummy_1")
					return
				_hits0 = _dummy.hits
				Input.action_press("attack")
				_next()
		9:
			Input.action_release("attack")
			if _dummy.hits > _hits0 and not _saw_return:
				_saw_return = true
				print("[focus] dummy hit after %.2fs (hits=%d), boomerang returning" % [_t, _dummy.hits])
			if _saw_return and not _eq.sync_thrown:
				print("[focus] caught after %.2fs" % _t)
				_next()
			elif _t > 4.0:
				_done(false, "boomerang never hit/returned (hits %d, thrown %s)" % [_dummy.hits, _eq.sync_thrown])
		10:  # still focused: jump + left = sidehop (OoT A while Z-targeting)
			_pos0 = _player.global_position
			Input.action_press("move_left")
			Input.action_press("jump")
			_next()
		11:
			Input.action_release("jump")
			if _player.motor.hop == 0:
				_rolled = true
			if _t > 0.9:
				Input.action_release("move_left")
				Input.action_release("focus")
				var side := _player.global_position - _pos0
				var still_facing := absf(angle_difference(_player.motor.facing, _player.focus.focus_yaw())) < 0.3
				print("[focus] sidehop: hopped=%s action=%d moved %.2fm facing kept=%s" % [_rolled, _player.sync_action, Vector2(side.x, side.z).length(), still_facing])
				_done(_rolled and _player.sync_action == 10, "focus + lock-on + boomerang + sidehop OK")


func _teleport(pos: Vector3, yaw: float) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.motor.reset(yaw)
	_player.camera_rig._yaw = yaw
	_player.camera_rig._pitch = deg_to_rad(-10)
	_player.reset_physics_interpolation()


func _next() -> void:
	_step += 1
	_t = 0.0


func _done(ok: bool, msg: String) -> void:
	print("[focus] %s %s" % ["PASS" if ok else "FAIL", msg])
	for a in ["focus", "attack", "move_left", "move_right", "roll", "jump"]:
		Input.action_release(a)
	set_physics_process(false)
	get_tree().quit(0 if ok else 1)
