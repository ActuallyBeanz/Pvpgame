extends Node
## Blastgourd Bombs, OoT-style (ItemDef.action_tag "bomb"; the item is its own ammo, 5 per pickup).
##   LMB            = pull out a lit bomb and hold it overhead (fuse starts NOW)
##   LMB again      = throw it (toward your focus target if locked on)
##   Q / roll       = set it down at your feet
##   fuse runs out while held = it blows up in your hands
## Owner simulates; the bomb itself is spawned on every peer (cosmetic copies elsewhere).

const BombScript := preload("res://scenes/weapons/bomb_projectile.gd")
const Motor := preload("res://scenes/player/movement_motor.gd")

var holding := false
var fuse_left := 0.0
var _eq: Node
var _player: CharacterBody3D
var _sparks: CPUParticles3D


func setup(equipment: Node, player: CharacterBody3D) -> void:
	_eq = equipment
	_player = player


func stats() -> Resource:
	var s: Resource = _eq.stats()
	return s if s and "fuse_time" in s else null


## Weapon swapped / inventory opened / swimming down: a held bomb is set down, not lost.
func cancel() -> void:
	if holding:
		_release(0.0, 0.0)


func update(delta: float) -> void:
	var s := stats()
	if s == null:
		cancel()
		return
	var pressed := Input.is_action_just_pressed("attack")
	var ready: bool = _eq.sync_drawn and _eq._swap_timer < 0.0 and not _player.motor.action_locked()
	if holding:
		fuse_left -= delta
		_eq.sync_aiming = true                          # hold pose
		if fuse_left <= 0.0:
			_spawn(_hand(), Vector3.ZERO, 0.0)          # it went off in your hands
			_stop_holding()
		elif Input.is_action_just_pressed("toggle_weapon") or _player.motor.state == Motor.State.ROLL:
			_release(s.drop_speed, 0.0)
		elif pressed:
			_release(s.throw_speed, s.throw_up)
		return
	_eq.sync_aiming = false
	if pressed and ready and _eq.ammo_count() > 0:
		var w: Resource = _eq.weapon()
		_eq.ammo[w.ammo_item_id] = _eq.ammo_count() - 1
		_eq.changed.emit()
		holding = true
		fuse_left = s.fuse_time
		_sparks = BombScript.fuse_sparks()
		var vis: Node3D = _eq._weapon_vis
		if vis:
			vis.add_child(_sparks)
			_sparks.position = Vector3(0, 0.22, 0)
		Audio.play_at("fire.ignite", _hand(), -4.0, 1.6)
		if _eq._model:
			_eq._model.play_action(&"Use_Item", 0.3)


func busy() -> bool:
	return holding


func _hand() -> Vector3:
	return _eq._hand_origin() + Vector3.UP * 0.15


func _release(speed: float, up: float) -> void:
	var fwd := -_player.model_root.global_basis.z
	var target: Node3D = _player.focus.target if _player.focus.active else null
	if target and is_instance_valid(target) and speed > 2.0:
		var to: Vector3 = target.get_lock_point() - _hand()
		fwd = Vector3(to.x, 0, to.z).normalized()
	elif _player.camera_rig and speed > 2.0:
		fwd = -_player.camera_rig.yaw_basis().z
	var carry := Vector3(_player.velocity.x, 0, _player.velocity.z) * 0.5
	_spawn(_hand() + fwd * 0.35, fwd * speed + Vector3.UP * up + carry, fuse_left)
	if speed > 2.0 and _eq._model:
		_eq._model.play_action(&"Throw", 0.4)
		Audio.play_at("boomerang.throw", _hand(), 0.0, 0.8)
	_stop_holding()


func _stop_holding() -> void:
	holding = false
	_eq.sync_aiming = false
	if is_instance_valid(_sparks):
		_sparks.queue_free()
	_sparks = null


func _spawn(origin: Vector3, vel: Vector3, fuse: float) -> void:
	_make_bomb(origin, vel, fuse, false)
	rpc_bomb.rpc(origin, vel, fuse)


@rpc("authority", "call_remote", "reliable")
func rpc_bomb(origin: Vector3, vel: Vector3, fuse: float) -> void:
	_make_bomb(origin, vel, fuse, true)


func _make_bomb(origin: Vector3, vel: Vector3, fuse: float, cosmetic: bool) -> void:
	var b := BombScript.new()
	b.name = "Bomb"
	b.velocity = vel
	b.fuse = fuse
	b.stats = ItemDB.get_item("bomb_blastgourd").stats
	b.cosmetic = cosmetic
	b.shooter_rid = _player.get_rid()
	_eq._projectiles_root().add_child(b, true)
	b.global_position = origin
