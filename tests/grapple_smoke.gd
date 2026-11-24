extends Node
## Grapple + inventory test (host only):
##  1. take the Grappleclaw: aim at a training dummy, release -> latch + reeled in
##  2. Grappleclaw at a tree trunk -> latch + reeled in
##  3. fire at bare ground -> knocked back, no pull
##  4. Skytether (long) reaches a tree the Grappleclaw can't, then grapples a torch
##  5. Tab inventory: still walks, LMB doesn't fire, move items hotbar <-> bag
##     (equipped tool moved to the bag gets unequipped), Esc closes it (no pause menu)
##   godot --headless res://tests/grapple_smoke.tscn
## Run with a window to also save screenshots to res://logs/.

var _step := 0
var _t := 0.0
var _total := 0.0
var _player: CharacterBody3D
var _eq: Node
var _rig: Node
var _hud: Node
var _target: Node3D
var _start := Vector3.ZERO
var _fired := false
var _shot_taken := false
var _latched := ""
var aim_hold := 1.4
var _shots := DisplayServer.get_name() != "headless"


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Lobby.local_profile = { "name": "Hook", "color": 1 }
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
	_player.motor.reset(_player.motor.facing)
	_player.reset_physics_interpolation()


func _stand(item_id: String) -> Node3D:
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.item_id == item_id:
			return p
	return null


## A tree with a clear line from a spot `dist` metres out toward the arena centre.
func _tree_spot(dist: float) -> Array:
	var space := _player.get_world_3d().direct_space_state
	for t in get_tree().current_scene.get_node("Props").get_children():
		if not t.name.begins_with("Tree_"):
			continue
		var tp: Vector3 = (t as Node3D).global_position
		var out := Vector3(-tp.x, 0, -tp.z).normalized()
		var spot := tp + out * dist
		var side := out.cross(Vector3.UP)
		var clear := true
		for lat in [-0.9, 0.0, 0.9]:          # a fat corridor: camera, hand and claw all get through
			for h in [0.5, 1.0, 1.5, 2.0]:
				var q := PhysicsRayQueryParameters3D.create(spot + side * lat + Vector3.UP * h, tp + side * lat * 0.2 + Vector3.UP * h, 3)
				q.exclude = [_player.get_rid()]
				var hit := space.intersect_ray(q)
				clear = clear and not hit.is_empty() and hit.collider == t
		for o in get_tree().current_scene.get_node("Props").get_children():   # nothing near the line
			if o == t or not (o is Node3D):
				continue
			var op: Vector3 = (o as Node3D).global_position
			var c := Geometry3D.get_closest_point_to_segment(Vector3(op.x, 0, op.z), Vector3(spot.x, 0, spot.z), Vector3(tp.x, 0, tp.z))
			clear = clear and c.distance_to(Vector3(op.x, 0, op.z)) > 1.8
		var down := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 3.0, spot + Vector3.DOWN, 1)
		var ground := space.intersect_ray(down)
		if clear and not ground.is_empty() and ground.collider.name == "Ground":
			return [t, spot + Vector3.UP * 0.2]
	return []


## One "fire" cycle: hold LMB to aim at `p`, release, then wait for the hook to settle.
func _aim_fire(p: Vector3) -> int:   # 0 = still going, 1 = done
	_look_at(p)
	if not _fired:
		if _t > 0.15 and not Input.is_action_pressed("attack"):
			Input.action_press("attack")
		if _t > aim_hold:
			if _eq.sync_aiming:
				_angle_report()
				_shot("aim_%d" % _step)
			Input.action_release("attack")
			_eq.hook.last_latched = ""
			_fired = true
			_t = 0.0
		return 0
	if _eq.hook.busy() and not _shot_taken:
		_shot_taken = true
		_shot("chain_%d" % _step)
	if _eq.hook.pulling() and _latched == "":
		_shot("pull_%d" % _step)
	_latched = _eq.hook.last_latched
	if _t > 0.2 and not _eq.hook.busy():
		_fired = false
		_shot_taken = false
		return 1
	return 0


func _angle_report() -> void:
	var head: Node3D = _eq.hook._claw_head()
	if head:
		var barrel := -head.global_basis.z.normalized()
		var cam := -(_rig.camera as Camera3D).global_basis.z
		print("[hook] barrel vs aim: %.0f deg (barrel %s)" % [rad_to_deg(barrel.angle_to(cam)), barrel.snappedf(0.01)])
		# hand rotation that would point the barrel down the aim line, top up
		var slot: Node3D = head.get_parent().get_parent()
		var want := Basis.looking_at(cam, Vector3.UP)
		var local := (slot.global_basis.orthonormalized().inverse() * want).get_euler()
		print("[hook] ideal hand_rotation_deg ~ %s" % (local * (180.0 / PI)).snappedf(1.0))


func _press_e() -> void:
	Input.action_press("interact")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("interact")


func _process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	_total += delta
	if _total > (40.0 if not _shots else 150.0):
		_done(false, "timeout at step %d" % _step)
	var scene := get_tree().current_scene
	if scene == null:
		return
	match _step:
		0:
			if scene.has_node("Players/1") and scene.get_node("Players/1").is_on_floor() and scene.has_node("Props/Dummy_0"):
				_player = scene.get_node("Players/1")
				_eq = _player.get_node("Equipment")
				_rig = _player.camera_rig
				_hud = scene.get_node("MatchHud")
				var st := _stand("grappleclaw")
				if st == null:
					_done(false, "no Grappleclaw stand")
					return
				_teleport(st.global_position + Vector3(0, 0.2, -1.0))
				_next()
		1:
			if _t > 0.4:
				_press_e()
				_next()
		2:
			if _eq.sync_weapon_id == "grappleclaw" and _eq.sync_drawn and _t > 0.8:
				print("[hook] picked up Grappleclaw, hotbar %s" % [_eq.inventory.slice(0, 9)])
				_target = scene.get_node("Props/Dummy_0")
				var tp := _target.global_position
				var away := Vector3(tp.x, 0, tp.z + 9.0)   # 9 m south of the dummy, clear ground
				_teleport(away + Vector3.UP * 0.2)
				_start = away
				_next()
			elif _t > 3.0:
				_done(false, "Grappleclaw not equipped (weapon=%s)" % _eq.sync_weapon_id)
		3:  # dummy
			if _t < 0.3:
				return
			if _aim_fire((_target as Node3D).get_lock_point()) == 1:
				var d := Vector2(_player.global_position.x - _target.global_position.x,
					_player.global_position.z - _target.global_position.z).length()
				print("[hook] dummy: latched=%s, now %.2fm from it (started 9m)" % [_latched, d])
				if _latched != _target.name or d > 2.0:
					_done(false, "should latch onto the dummy and get pulled to it")
					return
				_shot("01_dummy")
				var ts := _tree_spot(10.0)
				if ts.is_empty():
					_done(false, "no clear tree for the test")
					return
				_target = ts[0]
				_teleport(ts[1])
				_latched = ""
				_next()
		4:  # tree
			if _t < 0.4:
				return
			if _aim_fire(_target.global_position + Vector3.UP * 1.6) == 1:
				var d := Vector2(_player.global_position.x - _target.global_position.x,
					_player.global_position.z - _target.global_position.z).length()
				print("[hook] tree: latched=%s, now %.2fm from trunk (started 10m)" % [_latched, d])
				if _latched != _target.name or d > 2.2:
					_done(false, "should latch onto the tree and get pulled to it")
					return
				# miss: bare ground 6 m ahead
				_teleport(_start + Vector3.UP * 0.2)
				_latched = ""
				_next()
		5:  # ground: deflects, no pull
			if _t < 0.4:
				return
			var before := _player.global_position
			if _aim_fire(_start + Vector3(0, 0, 6.0)) == 1:
				var moved := _player.global_position.distance_to(_start)
				print("[hook] ground shot: latched=%s, moved %.2fm" % [_latched, moved])
				if _latched != "" or moved > 1.0:
					_done(false, "ground isn't hookable: claw should bounce back, no pull")
					return
				# long tree: a 22 m shot
				var ts := _tree_spot(22.0)
				if ts.is_empty():
					_done(false, "no clear 22 m tree line")
					return
				_target = ts[0]
				_start = ts[1]
				_teleport(_start)
				_next()
			elif before.distance_to(_player.global_position) > 3.0:
				_done(false, "got pulled by the ground")
		6:  # Grappleclaw at 22 m: out of range
			if _t < 0.4:
				return
			if _aim_fire(_target.global_position + Vector3.UP * 1.6) == 1:
				var moved := _player.global_position.distance_to(_start)
				print("[hook] Grappleclaw at 22m: latched=%s moved %.2fm" % [_latched, moved])
				if _latched != "":
					_done(false, "Grappleclaw (14m) shouldn't reach 22m")
					return
				_teleport(_stand("skytether").global_position + Vector3(0, 0.2, -1.0))
				_next()
		7:
			if _t > 0.4:
				_press_e()
				_next()
		8:
			if _eq.inventory.has("skytether") and _t > 0.6:
				var slot: int = _eq.hotbar_index("skytether")
				print("[hook] got Skytether in hotbar slot %d" % (slot + 1))
				Input.action_press("weapon_%d" % (slot + 1))
				_step = 80
				_t = 0.0
			elif _t > 3.0:
				_done(false, "Skytether not picked up")
		80:
			if _t > 0.1:
				for i in 9:
					Input.action_release("weapon_%d" % (i + 1))
				_teleport(_start)
				_latched = ""
				_step = 9
				_t = 0.0
		9:
			if _t < 0.5:
				return
			if _eq.sync_weapon_id != "skytether":
				_done(false, "Skytether not equipped (%s)" % _eq.sync_weapon_id)
				return
			if _aim_fire(_target.global_position + Vector3.UP * 1.6) == 1:
				var d := Vector2(_player.global_position.x - _target.global_position.x,
					_player.global_position.z - _target.global_position.z).length()
				print("[hook] Skytether at 22m: latched=%s, now %.2fm from trunk" % [_latched, d])
				if _latched != _target.name or d > 2.2:
					_done(false, "Skytether should reach the 22m tree")
					return
				_target = scene.get_node("Props/Lane_0")   # the lane torch
				_teleport(_target.global_position + Vector3(0, 0.2, 7.0))
				_latched = ""
				_step = 95
				_t = 0.0
		95:  # torch
			if _t < 0.4:
				return
			if _aim_fire(_target.global_position + Vector3.UP * 0.8) == 1:
				var d := Vector2(_player.global_position.x - _target.global_position.x,
					_player.global_position.z - _target.global_position.z).length()
				print("[hook] torch: latched=%s, now %.2fm from it" % [_latched, d])
				if _latched != _target.name or d > 2.0:
					_done(false, "torches should be grapple targets")
					return
				_teleport(Vector3(0, 0.2, -2))
				_step = 10
				_t = 0.0
		10:  # inventory open: walk, no attacks
			if _t < 0.3:
				return
			_hud.set_inventory_open(true)
			_start = _player.global_position
			Input.action_press("move_forward")
			Input.action_press("attack")
			_next()
		11:
			if _t > 0.8:
				Input.action_release("move_forward")
				Input.action_release("attack")
				var walked := _player.global_position.distance_to(_start)
				print("[hook] inventory open: walked %.2fm, aiming=%s hook busy=%s mouse=%d" % [walked, _eq.sync_aiming, _eq.hook.busy(), Input.mouse_mode])
				if walked < 1.5 or _eq.sync_aiming or _eq.hook.busy():
					_done(false, "with the inventory open you should walk but not aim/fire")
					return
				var inv: Node = _hud.get_node("WeaponHud/Inventory") if _hud.has_node("WeaponHud/Inventory") else null
				print("[hook] inventory panel visible=%s bag slots=%d" % [inv.visible if inv else false, inv.slots.size() if inv else 0])
				if inv == null or not inv.visible or inv.slots.size() != _eq.bag_size:
					_done(false, "inventory panel should be open with %d bag slots" % _eq.bag_size)
					return
				_shot("03_inventory")
				var sky: int = _eq.hotbar_index("skytether")
				var claw: int = _eq.hotbar_index("grappleclaw")
				# Skytether (equipped) -> bag slot 1: unequipped
				if not _eq.move_item(sky, _eq.inventory_size) or _eq.sync_weapon_id != "":
					_done(false, "moving the equipped tool to the bag should unequip it")
					return
				# swap Grappleclaw with the Skytether in the bag
				if not _eq.move_item(_eq.inventory_size, claw) or _eq.inventory[claw] != "skytether" \
						or _eq.inventory[_eq.inventory_size] != "grappleclaw":
					_done(false, "drag onto a filled slot should swap")
					return
				print("[hook] after moves: hotbar %s bag %s" % [_eq.inventory.slice(0, 9), _eq.inventory.slice(9, 12)])
				# hover a bag item + press 7: goes to hotbar slot 7
				_eq.ui_hover_slot = _eq.inventory_size
				Input.action_press("weapon_7")
				_next()
		12:
			if _t > 0.1:
				Input.action_release("weapon_7")
				if _eq.inventory[6] != "grappleclaw":
					_done(false, "hover + 7 should put the item on hotbar slot 7 (%s)" % [_eq.inventory.slice(0, 9)])
					return
				var esc := InputEventAction.new()
				esc.action = "pause"
				esc.pressed = true
				Input.parse_input_event(esc)
				_next()
		13:
			if _t > 0.2:
				var paused: bool = _hud.pause_panel.visible
				print("[hook] after Esc: inventory_open=%s paused=%s" % [GameConfig.inventory_open, paused])
				if GameConfig.inventory_open or paused:
					_done(false, "Esc should close the inventory (and not pause)")
					return
				_done(true, "grapple latches dummy + tree + torch, misses bounce, long reach, inventory drag/hotkeys/Esc OK")


func _next() -> void:
	_step += 1
	_t = 0.0


func _shot(tag: String) -> void:
	if not _shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	img.save_png("res://logs/hook_%s.png" % tag)


func _done(ok: bool, msg: String) -> void:
	Input.action_release("attack")
	Input.action_release("move_forward")
	print("[hook] %s %s" % ["PASS" if ok else "FAIL", msg])
	get_tree().quit(0 if ok else 1)
	set_process(false)
