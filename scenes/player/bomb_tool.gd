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
	_update_arc()


func update(delta: float) -> void:
	var s := stats()
	if s == null:
		cancel()
		_update_arc()
		return
	var pressed := Input.is_action_just_pressed("attack")
	var can_use: bool = _eq.sync_drawn and _eq._swap_timer < 0.0 and not _player.motor.action_locked()
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
		_update_arc()
		return
	_eq.sync_aiming = false
	_update_arc()
	if pressed and can_use and _eq.ammo_count() > 0:
		var w: Resource = _eq.weapon()
		_eq.consume(w.ammo_item_id, 1)
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


## Throw velocity: camera pitch + lift sets the arc (look up to lob onto high places),
## locked-on = toward the target; your own velocity is added on top (momentum: throw while
## running for distance, at the start of a jump for height).
func launch_velocity(speed: float, up: float) -> Vector3:
	var s := stats()
	var aim: Vector3 = -_player.model_root.global_basis.z
	if _player.camera_rig:
		aim = -_player.camera_rig.camera.global_basis.z
	var target: Node3D = _player.focus.target if _player.focus.active else null
	var flat := Vector3(aim.x, 0.0, aim.z)
	if target and is_instance_valid(target):
		var to: Vector3 = target.get_lock_point() - _hand()
		flat = Vector3(to.x, 0.0, to.z)
	flat = flat.normalized() if flat.length() > 0.01 else -_player.model_root.global_basis.z
	var pitch := asin(clampf(aim.y, -1.0, 1.0)) + deg_to_rad(s.throw_lift_deg if s else 28.0)
	pitch = clampf(pitch, deg_to_rad(-20.0), deg_to_rad(s.max_throw_pitch_deg if s else 75.0))
	var dir := flat * cos(pitch) + Vector3.UP * sin(pitch)
	var carry: float = s.momentum_carry if s else 1.0
	return dir * speed + Vector3.UP * up + _player.velocity * carry


func _release(speed: float, up: float) -> void:
	var vel: Vector3 = launch_velocity(speed, up) if speed > 2.0 else (-_player.model_root.global_basis.z * speed + _player.velocity * 0.5)
	var flat := Vector3(vel.x, 0.0, vel.z).normalized()
	_spawn(_hand() + flat * 0.35, vel, fuse_left)
	if speed > 2.0 and _eq._model:
		_eq._model.play_action(&"Throw", 0.4)
		Audio.play_at("boomerang.throw", _hand(), 0.0, 0.8)
	_stop_holding()


# ---------------------------------------------------------------- arc preview (owner only)
const ARC_DOTS := 48
var _arc: MultiMeshInstance3D
var _ring: MeshInstance3D


func _update_arc() -> void:
	var s := stats()
	var show := holding and s != null and s.arc_preview and _eq.is_local()
	if not show:
		if _arc:
			_arc.visible = false
			_ring.visible = false
		return
	if _arc == null:
		_build_arc()
	var vel := launch_velocity(s.throw_speed, s.throw_up)
	var pos := _hand() + Vector3(vel.x, 0.0, vel.z).normalized() * 0.35
	var space := _player.get_world_3d().direct_space_state
	var dt := 1.0 / 30.0
	var mm := _arc.multimesh
	var n := 0
	var landed := false
	var hit_n := Vector3.UP
	for step in 120:
		var nxt := pos + vel * dt
		vel.y -= s.gravity * dt
		var q := PhysicsRayQueryParameters3D.create(pos, nxt, 1)
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			pos = hit.position
			hit_n = hit.normal
			landed = true
			break
		pos = nxt
		if step % 2 == 0 and n < ARC_DOTS:
			mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3.ONE * lerpf(1.0, 0.6, float(n) / ARC_DOTS)), pos))
			n += 1
	mm.visible_instance_count = n
	_arc.visible = true
	_ring.visible = landed
	if landed:
		var up := hit_n.normalized()
		var side := up.cross(Vector3.FORWARD) if absf(up.dot(Vector3.FORWARD)) < 0.9 else up.cross(Vector3.RIGHT)
		_ring.global_transform = Transform3D(Basis(side.normalized(), up, side.normalized().cross(up)), pos + up * 0.05)


func _build_arc() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.7, 0.3, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	dot.radial_segments = 6
	dot.rings = 3
	dot.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = ARC_DOTS
	mm.visible_instance_count = 0
	_arc = MultiMeshInstance3D.new()
	_arc.name = "BombArc"
	_arc.top_level = true
	_arc.multimesh = mm
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc.extra_cull_margin = 200.0
	add_child(_arc)
	_ring = MeshInstance3D.new()
	_ring.name = "BombLanding"
	_ring.top_level = true
	var t := TorusMesh.new()
	t.inner_radius = 0.55
	t.outer_radius = 0.7
	t.rings = 20
	t.ring_segments = 4
	var rm := mat.duplicate() as StandardMaterial3D
	rm.albedo_color = Color(1.0, 0.45, 0.2, 0.8)
	t.material = rm
	_ring.mesh = t
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


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
