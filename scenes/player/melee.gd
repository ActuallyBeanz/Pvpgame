extends Node
## Sword + shield combat, OoT-style. Lives under Equipment; the owner simulates it,
## other peers replay the animation + trail from rpc_swing (cosmetic only).
##   Sword drawn:  tap LMB = 3-hit combo · focus-locked (RMB) = thrust
##                 keep holding LMB after a swing = charge, release when it sparkles = spin attack
##                 LMB with the sword away = draw + slash in one (like OoT's B button)
##   Jump attack:  focus (RMB) + Space with no side/back direction = leaping slash (OoT jump
##                 attack, double damage); LMB while airborne = the same slash coming down
##   Greatsword (Biggoron): two-handed (no shield), slower, bigger hits and spin
##   Hammer (Megaton): two-handed, one heavy overhead slam + shockwave, no spin
##   Shield owned: hold RMB (focus) or F = shield up (blocks frontal arrows / boomerangs /
##                 sword hits). Focus + LMB still attacks; F + LMB = poke from behind the
##                 shield with a one-handed sword (OoT), shield bash otherwise
## Hits go through WorldRules (slash / pierce / blunt tags), so wood, ice, dummies and
## future enemies all react with no extra code.

const FX := preload("res://systems/components/element_fx.gd")
const BladeTrail := preload("res://systems/components/blade_trail.gd")
const Motor := preload("res://scenes/player/movement_motor.gd")

enum Kind { SLASH_1, SLASH_2, SLASH_3, STAB, SPIN, BASH, JUMP, POKE }

var swinging := false
var charging := false
var charged := false
var focus_guard := false          ## shield is up because focus (RMB) is held, not F

var _eq: Node
var _player: CharacterBody3D
var _kind := -1
var _t := 0.0
var _dur := 0.0
var _dmg := 0.0
var _reach := 2.0
var _arc := 150.0
var _action := "slash"
var _window := Vector2(0.2, 0.6)
var _hit_ids: Dictionary = {}
var _combo := 0
var _combo_left := 0.0
var _queued := false
var _held_from_press := false
var _charge_t := 0.0
var _charge_fx: Node3D
var _block_t := 0.0
var _bash_cd := 0.0
var _trail: MeshInstance3D
var _remote_trail_left := 0.0
var _shock_done := false


func setup(equipment: Node, player: CharacterBody3D) -> void:
	_eq = equipment
	_player = player


func _ready() -> void:
	_trail = BladeTrail.new()
	_trail.name = "BladeTrail"
	add_child(_trail)


func sword_stats() -> Resource:
	var w: Resource = _eq.weapon()
	return w.stats if w and w.action_tag == "slash" else null


func shield_stats() -> Resource:
	var sh: Resource = _eq.shield_item()
	return sh.stats if sh else null


func busy() -> bool:
	return swinging or charging


func move_mult() -> float:
	var s := sword_stats()
	if swinging and _kind != Kind.BASH and s:
		return s.swing_move_mult
	if charging and s:
		return s.charge_move_mult
	if _eq.sync_blocking and shield_stats():
		return shield_stats().focus_guard_move_mult if focus_guard else shield_stats().block_move_mult
	return 1.0


## Queue a slash for when the sword finishes being drawn (OoT: B draws and swings).
func queue_draw_slash() -> void:
	_queued = true
	_held_from_press = true


func cancel() -> void:
	swinging = false
	_queued = false
	_stop_charge()
	_trail.active = false
	_eq.sync_blocking = false


# ---------------------------------------------------------------- owner update
func update(delta: float) -> void:
	_bash_cd = maxf(0.0, _bash_cd - delta)
	_combo_left = maxf(0.0, _combo_left - delta)
	if swinging:
		_tick_swing(delta)
	_update_block(delta)
	var s := sword_stats()
	var can_use: bool = s != null and _eq.sync_drawn and _eq._swap_timer < 0.0 \
		and (not _eq.sync_blocking or focus_guard)
	var rolling: bool = _player.motor.state == Motor.State.ROLL
	if not can_use or rolling:
		_stop_charge()
		if s == null or not _eq.sync_drawn:
			_queued = _queued and s != null  # keep a draw-slash queued while drawing
		return
	var pressed := Input.is_action_just_pressed("attack")
	var held := Input.is_action_pressed("attack")
	# OoT jump attack: focus + jump straight ahead, or attack while airborne
	if not swinging and not charging:
		var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var leap: bool = Input.is_action_just_pressed("jump") and _player.focus.active and _player.is_on_floor() \
			and absf(stick.x) < 0.5 and stick.y < 0.4 and _player.motor.water_depth < 0.5
		var air: bool = _player.motor.state == Motor.State.AIR and _player.motor.hop == Motor.Hop.NONE
		if leap or (pressed and air):
			_jump_attack(s, leap)
			return
	if _eq.sync_blocking and s.can_poke and not s.two_handed:
		# shield is up (F or focus): attacks are pokes from behind it (_update_block), never a
		# swing / charge that would drop the shield
		_queued = false
		_held_from_press = false
		_stop_charge()
		return
	if pressed:
		_held_from_press = true
		if swinging:
			_queued = _kind <= Kind.SLASH_2
		elif not charging:
			_queued = true
	if not held:
		if charging:
			if charged:
				_spin(s)
			_stop_charge()
		_held_from_press = false
	if not swinging and _queued:
		_queued = false
		_next_attack(s)
		return
	# Still holding LMB after a swing ended: charge the spin attack.
	if held and _held_from_press and not swinging and s.can_spin:
		if not charging:
			charging = true
			_charge_t = 0.0
			_eq.sync_aiming = true   # remotes show the charge pose (item aim_anim)
			Audio.play_at("sword.charge", _player.global_position)
		_charge_t += delta
		if not charged and _charge_t >= s.spin_charge_time:
			charged = true
			Audio.play_at("sword.charged", _player.global_position)
		_update_charge_fx()


func _next_attack(s: Resource) -> void:
	var fwd_push: bool = Input.get_vector("move_left", "move_right", "move_forward", "move_back").y < -0.5
	var focused: bool = _player.focus.active
	if _player.focus.target != null or (focused and s.style == "greatsword") or (focused and fwd_push and s.style == "sword"):
		_start(Kind.STAB, s.stab_anim, s.stab_duration, s.stab_damage, s.stab_reach, s.stab_arc_deg,
			s.stab_action, s.hit_window, false)
		return
	if _combo_left <= 0.0:
		_combo = 0
	var i: int = _combo % s.combo_anims.size()
	_start(Kind.SLASH_1 + i, s.combo_anims[i], s.combo_duration[i], s.combo_damage[i], s.reach, s.arc_deg,
		s.slash_action, s.hit_window, false)
	_combo = (i + 1) % s.combo_anims.size()


func _jump_attack(s: Resource, leap: bool) -> void:
	if leap:
		var m = _player.motor
		m.heading = m.facing
		m.speed = s.jump_forward_speed
		_player.velocity.y = s.jump_up
	var action: String = "blunt" if s.style == "hammer" else s.slash_action
	_start(Kind.JUMP, s.jump_anim, s.jump_duration, s.jump_damage, s.jump_reach, 120.0, action, Vector2(0.45, 0.95), true)
	_queued = false
	_combo = 0


func _spin(s: Resource) -> void:
	_start(Kind.SPIN, s.spin_anim, s.spin_duration, s.spin_damage, s.spin_radius, 360.0,
		s.slash_action, Vector2(0.1, 0.9), true)
	_combo = 0


func _start(kind: int, anim_name: StringName, dur: float, dmg: float, reach: float, arc: float,
		action: String, window: Vector2, full_body: bool) -> void:
	swinging = true
	_shock_done = false
	if kind != Kind.BASH and kind != Kind.POKE:
		_eq.sync_blocking = false   # the shield drops for the swing, comes back after
		_block_t = 0.0
	_kind = kind
	_t = 0.0
	_dur = dur
	_dmg = dmg
	_reach = reach
	_arc = arc
	_action = action
	_window = window
	_hit_ids.clear()
	_play(kind, anim_name, dur, full_body)
	rpc_swing.rpc(kind, anim_name, dur, full_body)
	print("[sword] %s dmg %.0f" % [Kind.keys()[kind], dmg])


func _play(kind: int, anim_name: StringName, dur: float, full_body: bool) -> void:
	var model: Node = _eq._model
	if model:
		if kind == Kind.POKE and model.has_method("play_arm_action"):
			model.play_arm_action(anim_name, dur)
		elif full_body:
			model.play_full(anim_name, dur)
		else:
			model.play_action(anim_name, dur)
	var pos := _player.global_position + Vector3.UP
	match kind:
		Kind.SPIN:
			Audio.play_at("sword.spin", pos)
		Kind.BASH:
			Audio.play_at("shield.bash", pos)
		_:
			Audio.play_at("sword.swing", pos, 0.0, 1.0 + 0.06 * kind)
	var s := sword_stats()
	if s and kind != Kind.BASH:
		_trail.color = s.trail_color
		_trail.tip_local = Vector3(0, s.blade_length, 0)
		_trail.follow = _eq._weapon_vis


@rpc("authority", "call_remote", "reliable")
func rpc_swing(kind: int, anim_name: StringName, dur: float, full_body: bool) -> void:
	_play(kind, anim_name, dur, full_body)
	if kind != Kind.BASH:
		_remote_trail_left = dur


func _process(delta: float) -> void:
	if _eq == null or _eq.is_local():
		return
	_remote_trail_left = maxf(0.0, _remote_trail_left - delta)  # remotes: trail for the whole swing
	_trail.follow = _eq._weapon_vis
	var s := sword_stats()
	if s:
		_trail.tip_local = Vector3(0, s.blade_length, 0)
	_trail.active = _remote_trail_left > 0.0


func _tick_swing(delta: float) -> void:
	_t += delta
	var f := _t / _dur
	var in_window := f >= _window.x and f <= _window.y
	_trail.active = in_window and _kind != Kind.BASH
	if in_window:
		_do_hits()
		var s := sword_stats()
		if not _shock_done and s and s.shockwave_radius > 0.0 and _kind != Kind.POKE and _kind != Kind.BASH:
			_shock_done = true
			_shockwave(s)
	if _t >= _dur:
		swinging = false
		_trail.active = false
		_combo_left = sword_stats().combo_window if sword_stats() else 0.0
		if _kind == Kind.SLASH_3 or _kind == Kind.SPIN or _kind == Kind.STAB:
			_combo = 0


func _forward() -> Vector3:
	var f: float = _player.motor.facing
	return Vector3(-sin(f), 0.0, -cos(f))


func _do_hits() -> void:
	var centre := _player.global_position + Vector3.UP * 0.9
	var fwd := _forward()
	var shape := SphereShape3D.new()
	shape.radius = _reach
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), centre)
	q.collision_mask = 3
	q.exclude = [_player.get_rid()]
	for r in _player.get_world_3d().direct_space_state.intersect_shape(q, 32):
		var col: Object = r.collider
		if col == null or _hit_ids.has(col.get_instance_id()) or not _reacts(col):
			continue
		var to: Vector3 = (col as Node3D).global_position - centre
		to.y = 0.0
		if _arc < 359.0 and to.length() > 0.35 and rad_to_deg(fwd.angle_to(to.normalized())) > _arc * 0.5:
			continue
		_hit_ids[col.get_instance_id()] = true
		var dir := to.normalized() if to.length() > 0.05 else fwd
		if col.has_method("blocks_hit") and col.blocks_hit(dir):
			col.on_blocked(centre + dir * 0.8)
			_recoil()
			return
		var action := "blunt" if _kind == Kind.BASH else _action
		var hit_info := WorldRules.make_hit(_dmg, action, "", dir)
		var ss := sword_stats()
		if ss and ss.style == "hammer" and _kind != Kind.BASH:
			hit_info["smash"] = true                 # Megaton-style: smashes cracked walls
		WorldRules.deliver_hit(col, hit_info, false)
		_eq.harvest_tree(col, (col as Node3D).global_position + Vector3.UP, 1)   # chopping a tree drops wood
		Audio.play_at("sword.hit", (col as Node3D).global_position + Vector3.UP, -2.0, randf_range(0.9, 1.1))
		print("[sword] hit %s for %.0f" % [(col as Node).name, hit_info.damage])


## Hammer slam: everything around the impact point takes a blunt hit (OoT Megaton Hammer).
func _shockwave(s: Resource) -> void:
	var at := _player.global_position + _forward() * 1.6 + Vector3.UP * 0.3
	var shape := SphereShape3D.new()
	shape.radius = s.shockwave_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 3
	q.exclude = [_player.get_rid()]
	for r in _player.get_world_3d().direct_space_state.intersect_shape(q, 32):
		var col: Object = r.collider
		if col == null or _hit_ids.has(col.get_instance_id()) or not _reacts(col):
			continue
		_hit_ids[col.get_instance_id()] = true
		var dir: Vector3 = ((col as Node3D).global_position - at)
		dir.y = 0.0
		var sh := WorldRules.make_hit(s.shockwave_damage, "blunt", "", dir.normalized() if dir.length() > 0.05 else _forward())
		sh["smash"] = true
		WorldRules.deliver_hit(col, sh, false)
		_eq.harvest_tree(col, (col as Node3D).global_position + Vector3.UP, 1)
	_shock_fx(at)
	rpc_shock.rpc(at)


@rpc("authority", "call_remote", "reliable")
func rpc_shock(at: Vector3) -> void:
	_shock_fx(at)


func _shock_fx(at: Vector3) -> void:
	FX.burst(at, get_tree().current_scene, Color(0.75, 0.65, 0.5), 22, 0.14, 5.0)
	FX.smoke_puff(at, get_tree().current_scene, 1.2)
	Audio.play_at("ice.shatter", at, 2.0, 0.55)


## Something we can damage / that reacts (not the ground or plain walls).
func _reacts(col: Object) -> bool:
	return col.has_method("react_to_hit_info") or col.has_method("react_to_hit") \
		or col.has_method("blocks_hit") or WorldRules.reactive_of(col) != null


## OoT: the blade bounces off a raised shield.
func _recoil() -> void:
	swinging = false
	_trail.active = false
	_queued = false
	if _eq._model:
		_eq._model.play_action(&"Hit_A", 0.35)


# ---------------------------------------------------------------- shield
func _update_block(delta: float) -> void:
	var sh := shield_stats()
	var w: Resource = _eq.weapon()
	var can: bool = sh != null and (not swinging or _kind == Kind.POKE) and not charging \
		and (w == null or w.action_tag == "slash" or not _eq.sync_drawn) \
		and _player.motor.state != Motor.State.ROLL and not _eq.two_handed_drawn()
	var by_key: bool = can and Input.is_action_pressed("block")
	var by_focus: bool = can and sh.raise_on_focus and _player.focus.active
	if by_key or by_focus:
		_block_t += delta
	else:
		_block_t = 0.0
	focus_guard = by_focus and not by_key
	var was: bool = _eq.sync_blocking
	_eq.sync_blocking = sh != null and _block_t >= sh.raise_time
	if _eq.sync_blocking and not was:
		_eq._applied = ""   # shield moves to the hand
	var ss := sword_stats()
	if _eq.sync_blocking and Input.is_action_just_pressed("attack") and not swinging and ss and _eq.sync_drawn \
			and ss.can_poke and not ss.two_handed:
		# OoT: shield up + B = quick stab from behind the shield (shield stays up)
		_start(Kind.POKE, ss.poke_anim, ss.poke_duration, ss.poke_damage, ss.poke_reach, 50.0,
			"pierce", Vector2(0.25, 0.7), false)
		return
	if _eq.sync_blocking and not focus_guard and Input.is_action_just_pressed("attack") and _bash_cd <= 0.0:
		_bash_cd = sh.bash_cooldown
		_eq.sync_blocking = false
		_block_t = -sh.bash_duration   # stay lowered for the bash
		_start(Kind.BASH, sh.bash_anim, sh.bash_duration, sh.bash_damage, sh.bash_reach, sh.bash_arc_deg,
			"blunt", Vector2(0.2, 0.6), false)


# ---------------------------------------------------------------- charge visuals
func _update_charge_fx() -> void:
	var tip_parent: Node3D = _eq._weapon_vis
	if tip_parent == null:
		return
	if _charge_fx == null:
		_charge_fx = _sparkles()
		tip_parent.add_child(_charge_fx)
		var s := sword_stats()
		_charge_fx.position = Vector3(0, s.blade_length * 0.7 if s else 1.1, 0)
	var p := _charge_fx as CPUParticles3D
	p.amount = 24 if charged else 8
	p.scale_amount_max = 1.6 if charged else 0.8


func _stop_charge() -> void:
	if charging:
		_eq.sync_aiming = false
	charging = false
	charged = false
	_charge_t = 0.0
	if is_instance_valid(_charge_fx):
		_charge_fx.queue_free()
	_charge_fx = null


func _sparkles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 8
	p.lifetime = 0.35
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.8
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.6, 0.95, 1.0)
	q.material = mat
	p.mesh = q
	return p
