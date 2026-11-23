extends Node
## Player equipment: owned weapons (slots), the current weapon + ammo, draw/holster,
## and per-weapon-type use:
##   action_tag "shoot" (bow):  hold LMB to draw & aim, release to fire
##   action_tag "throw" (boomerang): LMB throws; homes in on your focus lock target
## Owner-authoritative for its own state (synced via the player's $Sync);
## pickups are granted by the host (see scenes/items/pickup.gd).
## Controls: 1/2/3 pick weapon · Q draw/holster · LMB use · E pick up

signal changed

const ArrowScene := preload("res://scenes/weapons/arrow_projectile.tscn")
const BoomerangScene := preload("res://scenes/weapons/boomerang_projectile.tscn")
const Motor := preload("res://scenes/player/movement_motor.gd")

@export var pickup_radius := 2.2
@export var holster_swap_delay := 0.25     ## when the model moves hand <-> back during the anim
@export var max_weapon_slots := 3

# Synced to everyone through player.tscn > Sync.
var sync_weapon_id := ""
var sync_drawn := false
var sync_aiming := false
var sync_thrown := false                   ## boomerang is out of your hand

var weapons: Array[String] = []            ## owned weapon ids, slot order (owner only)
var ammo: Dictionary = {}                  ## ammo item id -> count (owner only)
var charge := 0.0                          ## 0..1 bow draw progress
var nearest_pickup: Node3D

var _player: CharacterBody3D
var _model: Node3D
var _weapon_vis: Node3D
var _worn_vis: Node3D
var _applied := ""                         ## last visual state applied
var _cooldown := 0.0
var _swap_timer := -1.0
var _drawing := false
var _boomerang: Node3D
var _need_redraw := false                  ## a roll cancelled the bow draw: release LMB first


func _ready() -> void:
	_player = get_parent()


func is_local() -> bool:
	return is_multiplayer_authority()


func weapon() -> Resource:
	return ItemDB.get_item(sync_weapon_id) if sync_weapon_id != "" else null


func stats() -> Resource:
	var w := weapon()
	return w.stats if w else null


func weapon_type() -> String:
	var w := weapon()
	return w.action_tag if w else ""


func ammo_count() -> int:
	var w := weapon()
	return int(ammo.get(w.ammo_item_id, 0)) if w and w.ammo_item_id != "" else 0


func is_aiming() -> bool:
	return sync_aiming


func move_speed_mult() -> float:
	var s := stats()
	return s.aim_move_speed_mult if sync_aiming and s and "aim_move_speed_mult" in s else 1.0


## Weapon-specific lock-on range (0 = use the focus default). Every weapon can lock on;
## only weapons whose stats say homes_on_lock fly to the target by themselves.
func lock_on_range() -> float:
	var s := stats()
	return float(s.lock_on_range) if s and "lock_on_range" in s else 0.0


# ---------------------------------------------------------------- items
## Called on the owner when the host grants a pickup.
func receive_item(item_id: String, amount: int) -> void:
	var it := ItemDB.get_item(item_id)
	if it == null:
		return
	if it.kind == "weapon":
		if not weapons.has(item_id):
			if weapons.size() < max_weapon_slots:
				weapons.append(item_id)
			_add_ammo(it.ammo_item_id, it.starting_ammo)
			if sync_weapon_id == "":
				_equip(item_id)
		else:
			_add_ammo(it.ammo_item_id, it.starting_ammo)  # duplicate weapon -> its ammo
	elif it.kind == "ammo":
		_add_ammo(item_id, amount)
	print("[equipment] got %s x%d | weapons %s | ammo %s" % [item_id, amount, weapons, ammo])
	changed.emit()


func _add_ammo(ammo_id: String, n: int) -> void:
	if ammo_id == "" or n <= 0:
		return
	var it := ItemDB.get_item(ammo_id)
	var cap: int = it.max_carry if it else 99
	ammo[ammo_id] = mini(int(ammo.get(ammo_id, 0)) + n, cap)


## Switch to a weapon you own and draw it.
func _equip(item_id: String) -> void:
	if item_id == sync_weapon_id:
		_set_drawn(not sync_drawn)
		return
	_release(false)
	sync_weapon_id = item_id
	sync_drawn = false
	_applied = ""
	_set_drawn(true)
	changed.emit()


# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if _model == null:
		_find_model()
	if is_local():
		_local_update(delta)
	if _swap_timer >= 0.0:
		_swap_timer -= delta
		if _swap_timer < 0.0:
			_applied = ""  # force visual refresh now
	_refresh_visuals()
	if _model:
		var w := weapon()
		_model.set_aiming(sync_aiming and sync_drawn, w.aim_anim if w else &"", w.shoot_anim if w else &"")


func _local_update(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var can_act := GameConfig.gameplay_input_enabled
	_update_nearest_pickup()
	if not can_act:
		_release(false)
		sync_aiming = false
		_player.camera_rig.set_aim(false)
		return
	if Input.is_action_just_pressed("interact") and nearest_pickup:
		nearest_pickup.request_take()
	for i in max_weapon_slots:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)) and i < weapons.size():
			_equip(weapons[i])
	if Input.is_action_just_pressed("cycle_weapon") and weapons.size() > 1:
		_equip(weapons[(weapons.find(sync_weapon_id) + 1) % weapons.size()])
	var w := weapon()
	if w == null:
		return
	if Input.is_action_just_pressed("toggle_weapon"):
		_release(false)
		_set_drawn(not sync_drawn)
	if Input.is_action_just_pressed("attack") and not sync_drawn:
		_set_drawn(true)
		return
	match w.action_tag:
		"shoot":
			_update_bow(delta)
		"throw":
			sync_aiming = false
			_player.camera_rig.set_aim(false)
			if Input.is_action_just_pressed("attack") and sync_drawn and not sync_thrown \
					and _cooldown <= 0.0 and _swap_timer < 0.0:
				_throw()


func _update_bow(delta: float) -> void:
	var s := stats()
	var holding := Input.is_action_pressed("attack")
	# Rolling drops the arrow: no shooting mid-roll, and you have to redraw afterwards.
	if _player.motor.state == Motor.State.ROLL:
		if _drawing or charge > 0.0:
			_release(false)
		_need_redraw = _need_redraw or holding
		sync_aiming = false
		_player.camera_rig.set_aim(false, s)
		return
	if _need_redraw:
		if holding and not Input.is_action_just_pressed("attack"):
			sync_aiming = false
			_player.camera_rig.set_aim(false, s)
			return
		_need_redraw = false
	var wants_aim := sync_drawn and _swap_timer < 0.0 and holding
	sync_aiming = wants_aim
	if wants_aim and ammo_count() > 0 and _cooldown <= 0.0:
		_drawing = true
		charge = minf(1.0, charge + delta / s.draw_time)
	if _drawing and not holding:
		_release(charge >= s.min_charge_to_fire)
	_player.camera_rig.set_aim(sync_aiming, s)


func _release(fire: bool) -> void:
	if fire:
		_fire()
	_drawing = false
	charge = 0.0


func _set_drawn(on: bool) -> void:
	if on == sync_drawn:
		return
	sync_drawn = on
	sync_aiming = false
	_swap_timer = holster_swap_delay
	var w := weapon()
	if _model and w:
		_model.play_action(w.draw_anim)
	changed.emit()


# ---------------------------------------------------------------- aiming helpers
## Where the crosshair points (camera ray), limited to max_dist from `origin`.
func _crosshair_point(origin: Vector3, max_dist: float) -> Vector3:
	var cam: Camera3D = _player.camera_rig.camera
	var space := _player.get_world_3d().direct_space_state
	var cam_from := cam.global_position
	var cam_dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(cam_from, cam_from + cam_dir * 500.0, 3)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	var p: Vector3 = hit.position if not hit.is_empty() else cam_from + cam_dir * 500.0
	if origin.distance_to(p) > max_dist:
		p = origin + (p - origin).normalized() * max_dist
	return p


func _hand_origin() -> Vector3:
	if _weapon_vis and sync_drawn:
		return _weapon_vis.global_position + Vector3.UP * 0.05
	return _player.global_position + Vector3.UP * 1.4


func _projectiles_root() -> Node:
	var scene := get_tree().current_scene
	var parent := scene.get_node_or_null("Projectiles")
	if parent == null:
		parent = Node3D.new()
		parent.name = "Projectiles"
		scene.add_child(parent)
	return parent


# ---------------------------------------------------------------- bow
func _fire() -> void:
	var w := weapon()
	var s := stats()
	if w == null or ammo_count() <= 0:
		return
	var origin := _hand_origin()
	var dir := (_crosshair_point(origin, 1000.0) - origin).normalized()
	dir = _apply_spread(dir, float(s.spread_deg(charge)))
	var vel: Vector3 = dir * s.launch_speed(charge)
	var dmg: float = s.damage(charge)
	ammo[w.ammo_item_id] = ammo_count() - 1
	_cooldown = s.fire_cooldown
	_spawn_arrow(origin, vel, dmg, false)
	Audio.play_at("bow.fire", origin)
	if _model:
		_model.play_shoot()
	rpc_fire.rpc(origin, vel)
	print("[bow] fired charge %.2f speed %.1f m/s dmg %.0f ammo left %d" % [charge, vel.length(), dmg, ammo_count()])
	changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_fire(origin: Vector3, vel: Vector3) -> void:
	_spawn_arrow(origin, vel, 0.0, true)
	Audio.play_at("bow.fire", origin)
	if _model:
		_model.play_shoot()


func _spawn_arrow(origin: Vector3, vel: Vector3, dmg: float, cosmetic: bool) -> void:
	var arrow := ArrowScene.instantiate()
	arrow.cosmetic = cosmetic
	_projectiles_root().add_child(arrow)
	arrow.launch(origin, vel, stats(), dmg, _player.get_rid())


func _apply_spread(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return dir
	var side := dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var a := randf() * TAU
	var r := deg_to_rad(deg) * sqrt(randf())
	return (dir + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


# ---------------------------------------------------------------- boomerang
func _throw() -> void:
	var w := weapon()
	var s := stats()
	var origin := _hand_origin()
	var homing: bool = "homes_on_lock" in s and s.homes_on_lock
	var target: Node3D = _player.focus.target if _player.focus.active and homing else null
	var aim: Vector3
	if target:
		aim = target.get_lock_point()
	else:
		aim = _crosshair_point(origin, s.speed * s.out_time)
	sync_thrown = true
	_cooldown = s.cooldown
	_applied = ""
	_spawn_boomerang(origin, aim, target, false)
	if _model:
		_model.play_action(w.shoot_anim)
	var path := get_tree().current_scene.get_path_to(target) if target else NodePath()
	rpc_throw.rpc(origin, aim, path)
	print("[boomerang] thrown %s" % ("-> locked on %s" % target.name if target else "free aim (%.1fm)" % origin.distance_to(aim)))


@rpc("authority", "call_remote", "reliable")
func rpc_throw(origin: Vector3, aim: Vector3, target_path: NodePath) -> void:
	var target: Node3D = null
	if not target_path.is_empty():
		target = get_tree().current_scene.get_node_or_null(target_path) as Node3D
	_spawn_boomerang(origin, aim, target, true)
	var w := weapon()
	if _model and w:
		_model.play_action(w.shoot_anim)


func _spawn_boomerang(origin: Vector3, aim: Vector3, target: Node3D, cosmetic: bool) -> void:
	var b := BoomerangScene.instantiate()
	b.cosmetic = cosmetic
	_projectiles_root().add_child(b)
	b.launch(origin, aim, target, stats(), _player)
	if not cosmetic:
		_boomerang = b
		b.caught.connect(_on_boomerang_caught)


func _on_boomerang_caught() -> void:
	sync_thrown = false
	_applied = ""
	_boomerang = null
	changed.emit()


# ---------------------------------------------------------------- pickups
func _update_nearest_pickup() -> void:
	nearest_pickup = null
	var best := pickup_radius
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.taken:
			continue
		var d: float = (p as Node3D).global_position.distance_to(_player.global_position)
		if d < best:
			best = d
			nearest_pickup = p


# ---------------------------------------------------------------- visuals
func _find_model() -> void:
	var root: Node3D = _player.get("model_root")
	if root and root.get_child_count() > 0 and root.get_child(0).has_method("get_attach_point"):
		_model = root.get_child(0)


func _refresh_visuals() -> void:
	if _model == null:
		return
	var state := "%s|%s|%s" % [sync_weapon_id, sync_drawn, sync_thrown]
	if state == _applied or _swap_timer >= 0.0:
		return
	_applied = state
	for v in [_weapon_vis, _worn_vis]:
		if is_instance_valid(v):
			v.queue_free()
	_weapon_vis = null
	_worn_vis = null
	var w := weapon()
	if w == null:
		return
	if sync_thrown:
		pass  # it's flying: nothing in hand or on the back
	elif sync_drawn:
		_weapon_vis = _attach(w.model_id, w.hand_slot, w.hand_position, w.hand_rotation_deg)
	else:
		_weapon_vis = _attach(w.model_id, "chest", w.back_position, w.back_rotation_deg)
	if w.worn_model_id != "":
		_worn_vis = _attach(w.worn_model_id, "chest", w.worn_position, w.worn_rotation_deg)
	if _player.camera_rig and _player.camera_rig.first_person:
		_player.call("_on_view_changed", true)  # keep FP shadow-only look


func _attach(model_id: String, slot: String, pos: Vector3, rot_deg: Vector3) -> Node3D:
	var point: Node3D = _model.get_attach_point(slot)
	if point == null:
		return null
	var vis := AssetRegistry.instantiate(model_id)
	vis.position = pos
	vis.rotation_degrees = rot_deg
	point.add_child(vis)
	return vis
