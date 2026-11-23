extends Node
## Weapon lane test (host only):
##  1. boomerang: hold LMB, sweep the camera over torch -> 3 dummies (4 picks, red),
##     release: it lights in the torch and deals FIRE hits to all three dummies, comes back
##  2. bow: hold the drawn arrow in the torch flame -> nocked arrow lights -> shoot a dummy
##     with a fire arrow
##   godot --headless res://tests/weapon_lane_smoke.tscn
## Run with a window to also save screenshots to res://logs/.

var _step := 0
var _t := 0.0
var _player: CharacterBody3D
var _eq: Node
var _rig: Node
var _lane: Array[Node3D] = []
var _dmg0: Array[float] = []
var _sweep := 0
var _arrow_dmg0 := 0.0
var _shots := DisplayServer.get_name() != "headless"


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Lobby.local_profile = { "name": "Lane", "color": 3 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _look_at(p: Vector3) -> void:
	var from: Vector3 = _rig.camera.global_position if _rig.camera else _player.global_position + Vector3.UP * 1.6
	var d := p - from
	_rig._yaw = atan2(-d.x, -d.z)
	_rig._pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(-60), deg_to_rad(40))


func _teleport(pos: Vector3) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _t > 15.0:
		_done(false, "timeout at step %d" % _step)
	var scene := get_tree().current_scene
	if scene == null:
		return
	match _step:
		0:
			if scene.has_node("Players/1") and scene.get_node("Players/1").is_on_floor() and scene.has_node("Props/Lane_3"):
				_player = scene.get_node("Players/1")
				_eq = _player.get_node("Equipment")
				_rig = _player.camera_rig
				for i in 4:
					_lane.append(scene.get_node("Props/Lane_%d" % i))
				_eq.receive_item("boomerang_basic", 0)
				_teleport(Vector3(0, 0.2, 5.0))
				_look_at(_lane[0].get_lock_point())
				_next()
		1:
			if _t > 0.8 and _eq.sync_drawn:
				for i in [1, 2, 3]:
					_dmg0.append(_lane[i].total_damage)
				Input.action_press("attack")
				_next()
		2:  # sweep: torch, then the dummies left to right (crosshair held on each a moment)
			_look_at(_lane[_sweep].get_lock_point())
			if _t > (0.5 if _sweep == 0 else 0.25):
				_t = 0.0
				_sweep += 1
				if _sweep == 2:
					_shot("01_boomerang_picks")
				if _sweep > 3:
					_next()
		3:
			if _t > 0.25:
				var picked: Array = _eq.boomerang_selection()
				print("[lane] picked: %s" % ", ".join(picked.map(func(n: Node) -> String: return n.name)))
				if picked.size() != 4 or picked[0] != _lane[0]:
					_done(false, "expected torch + 3 dummies picked, got %d" % picked.size())
					return
				Input.action_release("attack")
				_next()
		4:
			if _t > 0.3 and _t < 0.4:
				_shot("02_boomerang_flight")
			if not _eq.sync_thrown and _t > 0.5:
				var dmg := []
				for i in [1, 2, 3]:
					dmg.append(_lane[i].total_damage - _dmg0[i - 1])
				print("[lane] boomerang back. dummy damage: %s" % str(dmg))
				for d in dmg:
					if d < 6.0:  # 3 base + 4 fire bonus = 7 per fire hit
						_done(false, "a dummy didn't take a fire hit (%s)" % str(dmg))
						return
				_next()
		5:  # bow: stand at the torch, hold the arrow in the flame
			_eq.receive_item("bow_basic", 0)
			_eq._equip("bow_basic")
			_teleport(_lane[0].global_position + Vector3(0, 0.2, -1.0))
			_look_at(_lane[0].global_position + Vector3(0, 1.05, 0))
			_next()
		6:
			if _t > 0.8 and _eq.sync_weapon_id == "bow_basic" and _eq.sync_drawn:
				Input.action_press("attack")
				_next()
		7:
			_look_at(_lane[0].global_position + Vector3(0, 1.05, 0))  # keep the crosshair on the flame
			if _eq.sync_arrow_element == "fire":
				print("[lane] nocked arrow lit in the torch (%.2fs)" % _t)
				_shot("03_arrow_lit")
				_arrow_dmg0 = _lane[1].total_damage
				_teleport(Vector3(-0.5, 0.2, 7.0))  # step out from behind the torch, keep drawing
				_look_at(_lane[1].get_lock_point())
				_next()
			elif _t > 2.5:
				var z: Node3D = _lane[0].find_child("FireZone", true, false)
				print("[lane] dbg tip=%s zone=%s hand=%s aiming=%s nock=%s" % [_eq._nock_vis.global_position if _eq._nock_vis else "none", z.global_position, _eq._hand_origin(), _eq.sync_aiming, _eq._nock_vis != null])
				_done(false, "nocked arrow didn't light (tip near flame?)")
		8:
			_look_at(_lane[1].get_lock_point())
			if _t > 1.2:
				Input.action_release("attack")
				_next()
		9:
			var got: float = _lane[1].total_damage - _arrow_dmg0
			if got > 0.0:
				var fire_arrows := 0
				for a in get_tree().current_scene.get_node("Projectiles").get_children():
					if "element" in a and a.element == "fire":
						fire_arrows += 1
				print("[lane] fire arrow hit dummy for %.0f (fire arrows in world: %d)" % [got, fire_arrows])
				if fire_arrows < 1:
					_done(false, "arrow wasn't on fire")
					return
				_done(true, "boomerang multi-target + torch fire + lit arrow OK")
			elif _t > 3.0:
				_done(false, "fire arrow missed the dummy")


func _next() -> void:
	_step += 1
	_t = 0.0


func _shot(tag: String) -> void:
	if not _shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	img.save_png("res://logs/lane_%s.png" % tag)


func _done(ok: bool, msg: String) -> void:
	Input.action_release("attack")
	print("[lane] %s %s" % ["PASS" if ok else "FAIL", msg])
	get_tree().quit(0 if ok else 1)
	set_process(false)
