extends Node
## Sword + shield test (host only):
##  1. take both from the stands, sword drawn, shield in the off hand
##  2. 3-hit combo on a lane dummy (12 + 12 + 20)
##  3. hold LMB -> charge -> release -> spin attack hits BOTH nearby dummies
##  4. shield up (F): an arrow fired at you from the front bounces off
##   godot --headless res://tests/sword_shield_smoke.tscn
## Run with a window to also save screenshots to res://logs/.

const ArrowScene := preload("res://scenes/weapons/arrow_projectile.tscn")
const BowStats := preload("res://data/items/bow_basic_stats.tres")

var _step := 0
var _t := 0.0
var _player: CharacterBody3D
var _eq: Node
var _rig: Node
var _d1: Node3D
var _d2: Node3D
var _base1 := 0.0
var _base2 := 0.0
var _taps := 0
var _arrow: Node3D
var _shots := DisplayServer.get_name() != "headless"


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Lobby.local_profile = { "name": "Blade", "color": 0 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _look_at(p: Vector3) -> void:
	var from: Vector3 = _rig.camera.global_position
	var d := p - from
	_rig._yaw = atan2(-d.x, -d.z)
	_rig._pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(-60), deg_to_rad(40))


func _teleport(pos: Vector3) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _take(item_id: String) -> void:
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.item_id == item_id:
			_teleport(p.global_position + Vector3(0, 0.2, -1.0))
			return


func _process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _t > 12.0:
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
				_d1 = scene.get_node("Props/Lane_1")
				_d2 = scene.get_node("Props/Lane_2")
				_take("sword_dawnsteel")
				_next()
		1, 2:  # press E on one frame, release + move on a later frame
			if _t > 0.4 and not Input.is_action_pressed("interact"):
				Input.action_press("interact")
				_t = 0.0
				_step += 10   # 11 / 12: wait a frame
		11, 12:
			if _t > 0.15:
				Input.action_release("interact")
				_step -= 10
				if _step == 1:
					_take("shield_gildcrest")
				_next()
		3:
			if _eq.sync_weapon_id == "sword_dawnsteel" and _eq.sync_shield_id == "shield_gildcrest" and _t > 0.8:
				print("[blade] picked up sword + shield (drawn=%s) hotbar=%s" % [_eq.sync_drawn, _eq.inventory])
				if _eq.inventory[0] != "sword_dawnsteel" or _eq.inventory[1] != "shield_gildcrest" or _eq.inventory_size != 9:
					_done(false, "hotbar should hold sword, shield in slots 1-2 of 9")
					return
				_shot("01_sword_shield")
				# stand 1.4m in front of dummy 1
				var front: Vector3 = _d1.global_position + (Vector3(0, 0, 3.5) - _d1.global_position).normalized() * 1.4
				_teleport(Vector3(front.x, 0.2, front.z))
				_base1 = _d1.total_damage
				_next()
			elif _t > 3.0:
				_done(false, "sword/shield not picked up (weapon=%s shield=%s)" % [_eq.sync_weapon_id, _eq.sync_shield_id])
		4:  # three taps, spaced to chain the combo
			_look_at(_d1.get_lock_point())
			if _t > 0.35 and _taps < 3 and not Input.is_action_pressed("attack"):
				Input.action_press("attack")
				_taps += 1
				_t = 0.0
			elif Input.is_action_pressed("attack") and _t > 0.08:
				Input.action_release("attack")
				if _taps == 2:
					_shot("02_combo")
			if _taps >= 3 and _t > 0.9:
				var got: float = _d1.total_damage - _base1
				print("[blade] combo damage on dummy: %.0f" % got)
				if got < 44.0:
					_done(false, "combo should deal 12+12+20 (got %.0f)" % got)
					return
				# between dummy 1 and 2 for the spin
				var mid: Vector3 = (_d1.global_position + _d2.global_position) * 0.5
				_teleport(Vector3(mid.x, 0.2, mid.z - 0.3))
				_base1 = _d1.total_damage
				_base2 = _d2.total_damage
				_next()
		5:  # tap-and-hold: one slash, keep holding -> charge
			if _t > 0.4 and not Input.is_action_pressed("attack"):
				Input.action_press("attack")
			if _eq.melee.charged:
				print("[blade] spin charged after %.2fs" % _t)
				_shot("03_charged")
				Input.action_release("attack")
				_next()
			elif _t > 4.0:
				_done(false, "spin never charged")
		6:
			if _t > 0.35 and _t < 0.45:
				_shot("04_spin")
			if _t > 1.0:
				var g1: float = _d1.total_damage - _base1
				var g2: float = _d2.total_damage - _base2
				print("[blade] after slash + spin: dummy1 +%.0f, dummy2 +%.0f" % [g1, g2])
				if g1 < 28.0 or g2 < 28.0:
					_done(false, "spin attack should hit both dummies for 28")
					return
				_next()
		7:  # raise the shield, get shot from the front
			_teleport(Vector3(0, 0.2, 7.0))
			_look_at(Vector3(0, 1.0, 14.0))
			Input.action_press("block")
			_next()
		8:
			_look_at(Vector3(0, 1.0, 14.0))
			if _t > 0.5 and _arrow == null:
				if not _eq.sync_blocking:
					_done(false, "shield not raised")
					return
				_shot("05_block")
				_arrow = ArrowScene.instantiate()
				scene.add_child(_arrow)
				var from := _player.global_position + Vector3(0, 0.9, 8.0)
				_arrow.launch(from, (_player.global_position + Vector3(0, 0.9, 0) - from).normalized() * 40.0, BowStats, 20.0, RID())
			elif _arrow and _t > 1.2:
				Input.action_release("block")
				if _arrow.get("_stuck") or (is_instance_valid(_arrow) and _arrow.get_parent() == _player):
					_done(false, "arrow stuck in the player instead of bouncing off the shield")
					return
				_next()
		9:  # focus (RMB) raises the shield on its own
			if _t > 0.2 and not Input.is_action_pressed("focus"):
				Input.action_press("focus")
			if _t > 0.6:
				if not (_eq.sync_blocking and _eq.melee.focus_guard):
					_done(false, "holding focus should raise the shield")
					return
				print("[blade] focus raised the shield")
				_shot("06_focus_guard")
				Input.action_press("attack")
				_next()
		10:  # ...and LMB still attacks from behind it, then the shield comes back up
			if _t > 0.08:
				Input.action_release("attack")
			if _t > 0.12 and _t < 0.3 and _eq.melee.swinging and _eq.sync_blocking:
				_done(false, "shield should drop while swinging")
				return
			if _t > 1.0:
				Input.action_release("focus")
				if not _eq.sync_blocking:
					_done(false, "shield didn't come back up after the swing")
					return
				print("[blade] swung from behind the focus shield, shield back up")
				_done(true, "sword combo + spin + shield block + focus shield + hotbar OK")


func _next() -> void:
	_step += 1
	_t = 0.0


func _shot(tag: String) -> void:
	if not _shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	img.save_png("res://logs/blade_%s.png" % tag)


func _done(ok: bool, msg: String) -> void:
	Input.action_release("focus")
	Input.action_release("attack")
	Input.action_release("block")
	print("[blade] %s %s" % ["PASS" if ok else "FAIL", msg])
	get_tree().quit(0 if ok else 1)
	set_process(false)
