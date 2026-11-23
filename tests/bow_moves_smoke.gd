extends Node
## Bow + moves: with the bow drawn and aiming, Space + left = sidehop and Space + back =
## backflip without losing the draw; a roll cancels the draw, holding LMB through the roll
## doesn't redraw, and pressing LMB again does. Prints PASS/FAIL.
##   godot --headless res://tests/bow_moves_smoke.tscn

const Motor := preload("res://scenes/player/movement_motor.gd")

var _step := 0
var _t := 0.0
var _player: CharacterBody3D
var _eq: Node
var _fails: PackedStringArray = []
var _fired_mid_roll := false
var _dummy: Node3D


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Lobby.local_profile = { "name": "Archer", "color": 1 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _physics_process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _t > 10.0:
		_fail("timeout at step %d" % _step)
		_finish()
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	match _step:
		0:
			if scene.has_node("Players/1") and scene.get_node("Players/1").is_on_floor():
				_player = scene.get_node("Players/1")
				_eq = _player.get_node("Equipment")
				_eq.receive_item("bow_basic", 1)
				_player.global_position = Vector3(-3, 0.1, 3)
				_player.motor.reset(0.0)
				_player.camera_rig._yaw = 0.0
				_player.reset_physics_interpolation()
				_next()
		1:  # draw and hold
			if _t > 0.4:
				Input.action_press("attack")
			if _t > 0.9:
				print("[bowmove] aiming %s charge %.2f" % [_eq.sync_aiming, _eq.charge])
				if not _eq.sync_aiming:
					_fail("not aiming")
				Input.action_press("move_left")
				Input.action_press("jump")
				_next()
		2:  # sidehop while aiming
			if _t > 0.1:
				Input.action_release("jump")
				Input.action_release("move_left")
			if _t > 0.6:
				print("[bowmove] sidehop with bow: action %d, still aiming %s, charge %.2f" % [_player.sync_action, _eq.sync_aiming, _eq.charge])
				if _player.sync_action != 10 or not _eq.sync_aiming:
					_fail("sidehop with bow drawn")
				Input.action_press("move_back")
				Input.action_press("jump")
				_next()
		3:  # backflip while aiming
			if _t > 0.1:
				Input.action_release("jump")
				Input.action_release("move_back")
			if _t > 0.9:
				print("[bowmove] backflip with bow: action %d, still aiming %s, charge %.2f" % [_player.sync_action, _eq.sync_aiming, _eq.charge])
				if _player.sync_action != 12 or not _eq.sync_aiming:
					_fail("backflip with bow drawn")
				Input.action_press("move_forward")
				Input.action_press("roll")
				_next()
		4:  # roll: draw cancelled, can't shoot, holding LMB doesn't redraw
			if _t > 0.1:
				Input.action_release("roll")
			if _player.motor.state == Motor.State.ROLL and (_eq.sync_aiming or _eq.charge > 0.0):
				_fail("still drawing mid-roll")
			if _t > 1.1:
				Input.action_release("move_forward")
				print("[bowmove] after roll, still holding LMB: aiming %s charge %.2f (expect false / 0)" % [_eq.sync_aiming, _eq.charge])
				if _eq.sync_aiming or _eq.charge > 0.0:
					_fail("should need to redraw after a roll")
				Input.action_release("attack")
				_next()
		5:
			if _t > 0.1 and _t < 0.15:
				Input.action_press("attack")
			if _t > 0.6:
				print("[bowmove] pressed LMB again: aiming %s charge %.2f, arrows %d (none fired mid-roll: %s)" % [_eq.sync_aiming, _eq.charge, _eq.ammo_count(), _eq.ammo_count() == 8])
				if not _eq.sync_aiming or _eq.charge <= 0.0 or _eq.ammo_count() != 8:
					_fail("redraw after roll")
				Input.action_release("attack")
				# stand 9 m from Dummy_1 looking away from it, then focus: bow locks on too
				_dummy = get_tree().current_scene.get_node("Props/Dummy_1")
				_player.global_position = _dummy.global_position + Vector3(-9.0, 0.1, 0.0)
				_player.motor.reset(PI * 0.5)
				_player.camera_rig._yaw = atan2(-1.0, 0.0) + 0.6  # roughly toward it, off by ~35°
				_player.reset_physics_interpolation()
				_next()
		6:
			if _t > 0.3:
				Input.action_press("focus")
			if _t > 1.0:
				var to := _dummy.global_position - _player.global_position
				var want := atan2(-to.x, -to.z)
				var face_err := rad_to_deg(absf(angle_difference(_player.motor.facing, want)))
				var cam_err := rad_to_deg(absf(angle_difference(_player.camera_rig.get_yaw(), want)))
				print("[bowmove] bow lock-on: target %s, body off by %.1f°, camera off by %.1f°" % [
					_player.focus.target.name if _player.focus.target else "none", face_err, cam_err])
				if _player.focus.target != _dummy or face_err > 3.0 or cam_err > 5.0:
					_fail("bow should lock on and face the dummy")
				Input.action_press("attack")
				_next()
		7:  # aiming while locked: arrow goes where the crosshair points (no homing)
			if _t > 1.0:
				Input.action_release("attack")
				_next()
		8:
			var proj := get_tree().current_scene.get_node_or_null("Projectiles")
			if proj and proj.get_child_count() > 0 and _t > 0.05:
				var arrow: Node3D = proj.get_child(proj.get_child_count() - 1)
				var v: Vector3 = arrow.velocity
				var cam: Camera3D = _player.camera_rig.camera
				var aim_dir := -cam.global_basis.z
				print("[bowmove] arrow fired while locked: flight dir vs crosshair %.1f° (homing would bend it)" % rad_to_deg(Vector2(v.x, v.z).angle_to(Vector2(aim_dir.x, aim_dir.z))))
				_finish()
			elif _t > 1.0:
				_fail("no arrow fired while locked")
				_finish()


func _fail(msg: String) -> void:
	print("[bowmove] problem: " + msg)
	_fails.append(msg)


func _finish() -> void:
	var ok := _fails.is_empty()
	print("[bowmove] %s %s" % ["PASS" if ok else "FAIL", "bow hops / roll cancel OK" if ok else ", ".join(_fails)])
	for a in ["attack", "move_left", "move_back", "move_forward", "roll", "jump", "focus"]:
		Input.action_release(a)
	set_physics_process(false)
	get_tree().quit(0 if ok else 1)


func _next() -> void:
	_step += 1
	_t = 0.0
