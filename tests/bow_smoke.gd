extends Node
## Bow loop test: pick up a bow -> aim at the 20m target -> full draw -> release ->
## arrow flies with drop and sticks -> holster. Prints PASS/FAIL.
##   godot --headless res://tests/bow_smoke.tscn
## Run with a window (no --headless) to also save screenshots to res://logs/.

var _step := 0
var _t := 0.0
var _player: CharacterBody3D
var _eq: Node
var _arrow: Node3D
var _peak := -INF
var _launch := Vector3.ZERO
var _flight_shot := false
var _shots := DisplayServer.get_name() != "headless"


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Lobby.local_profile = { "name": "Archer", "color": 1 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _t > 25.0:
		_done(false, "timeout at step %d" % _step)
	var scene := get_tree().current_scene
	if scene == null:
		return
	match _step:
		0:
			if scene.has_node("Players/1") and scene.get_node("Players/1").is_on_floor():
				_player = scene.get_node("Players/1")
				_eq = _player.get_node("Equipment")
				var bow: Node3D = null
				for p in get_tree().get_nodes_in_group("pickups"):
					if p.item_id == "bow_basic":
						bow = p
						break
				if bow == null:
					_done(false, "no bow pickup spawned")
					return
				_player.global_position = bow.global_position + Vector3(0, 0.2, -1.0)
				_player.reset_physics_interpolation()
				_next()
		1:
			if _t > 0.6:
				_shot("01_near_bow")
				print("[bow] prompt: %s" % ("[E] " + _eq.nearest_pickup.display_name() if _eq.nearest_pickup else "none"))
				Input.action_press("interact")
				_next()
		2:
			Input.action_release("interact")
			if _eq.sync_weapon_id == "bow_basic" and _t > 0.8:
				print("[bow] picked up, drawn=%s ammo=%d" % [_eq.sync_drawn, _eq.ammo_count()])
				_shot("02_bow_in_hand")
				# stand 20m in front of the target at (20,0,-2) and face it
				_player.global_position = Vector3(0, 0.2, -2)
				_player.reset_physics_interpolation()
				var rig = _player.camera_rig
				rig._yaw = atan2(-1.0, 0.0)   # face +X
				rig._pitch = 0.0
				_next()
			elif _t > 3.0:
				_done(false, "pickup not granted")
		3:
			if _t > 0.5:
				Input.action_press("attack")
				_next()
		4:
			if _t > 1.1:  # full draw
				_shot("03_full_draw")
				print("[bow] charge %.2f aiming %s" % [_eq.charge, _eq.sync_aiming])
				Input.action_release("attack")
				_next()
		5:
			var proj := scene.get_node_or_null("Projectiles")
			if proj and proj.get_child_count() > 0:
				_arrow = proj.get_child(0)
				_launch = _arrow.global_position
				_next()
			elif _t > 1.0:
				_done(false, "no arrow spawned")
		6:
			if is_instance_valid(_arrow):
				_peak = maxf(_peak, _arrow.global_position.y)
				if _step == 6 and not _flight_shot and _t > 0.12:
					_flight_shot = true
					_shot("04_arrow_flight")
				if _arrow._stuck:
					var p := _arrow.global_position
					print("[bow] launched from y=%.2f, peak y=%.2f, stuck at (%.1f, %.2f, %.1f) after %.2fs — dropped %.2fm below launch height" % [
						_launch.y, _peak, p.x, p.y, p.z, _t, _launch.y - p.y])
					_next()
			if _t > 4.0:
				_done(false, "arrow never landed")
		7:
			if _t > 0.6:
				_shot("05_arrow_in_target")
				Input.action_press("toggle_weapon")
				_next()
		8:
			Input.action_release("toggle_weapon")
			if _t > 0.9:
				var rig = _player.camera_rig
				rig._yaw = atan2(-1.0, 0.0)  # camera behind him -> see his back
				rig._pitch = deg_to_rad(-25)
				_next()
		9:
			if _t > 0.6:
				_shot("06_holstered_back")
				_done(not _eq.sync_drawn and _eq.ammo_count() == 7, "bow loop OK (holstered, 7 arrows left)")


func _next() -> void:
	_step += 1
	_t = 0.0


func _shot(name: String) -> void:
	if _shots:
		get_viewport().get_texture().get_image().save_png("res://logs/bow_%s.png" % name)


func _done(ok: bool, msg: String) -> void:
	print("[bow] %s %s" % ["PASS" if ok else "FAIL", msg])
	set_process(false)
	get_tree().quit(0 if ok else 1)
