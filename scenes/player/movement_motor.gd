extends RefCounted
## OoT-style movement for a CharacterBody3D (behaviour studied from the zeldaret/oot
## decomp; numbers live in data/config/movement_profile.gd).
##
## OoT keeps a scalar SPEED and a travel HEADING. The stick sets a target speed and
## heading; the heading turns at a fixed rate, and flipping the stick backwards brakes
## to a stop and snaps around instead of curving.
##
## Land moves: run / skid-turn / roll / bonk / ledge auto-hop / sprint-start roll, plus
## while focused (Z-target): side-step & back-walk, jump + side = sidehop, jump + back =
## backflip, roll in any direction. Ledges: step up, hop up, climb, tall climb, ledge
## grab + hang + pull up / drop, back-off ledge grab.
##
## Usage (owner peer only, once per physics tick):
##   motor.step(body, wish_dir_world, delta, intent)   # moves the body

const MovementProfile := preload("res://data/config/movement_profile.gd")

signal state_changed(new_state: int)
signal rolled(dir: int)                    ## RollDir, relative to facing
signal hopped(kind: int)                   ## Hop
signal climbed(kind: int, duration: float) ## Climb
signal grabbed_ledge
signal bonked
signal jumped(auto: bool)
signal landed

enum State { GROUND, AIR, ROLL, BONK, CLIMB, HANG }
enum RollDir { FORWARD, BACK, LEFT, RIGHT }
enum Hop { NONE = -1, SIDE_LEFT, SIDE_RIGHT, BACKFLIP, UP }
enum Climb { STEP, HOP_UP, CLIMB, TALL, PULL_UP }

## Input for one physics tick. Built by player.gd.
class Intent:
	var jump_pressed := false
	var jump_held := false
	var roll_pressed := false
	var sprint := false
	var speed_mult := 1.0
	var focus := false             ## face focus_yaw and strafe
	var focus_yaw := 0.0
	var oot_strafe_speeds := true  ## false = bow aim / first person (full-speed strafe)
	var allow_hops := false        ## jump + side/back = sidehop / backflip (focus, bow aim)
	var camera_yaw := 0.0          ## rolls steer toward the camera when there's no stick input
	var instant_facing := false    ## first person: body = camera yaw

var profile: MovementProfile
var state := State.GROUND
var speed := 0.0        ## m/s along heading (negative while bonked)
var heading := 0.0      ## travel yaw in radians (0 = -Z)
var facing := 0.0       ## model yaw in radians
var invulnerable := false
var hop := Hop.NONE     ## current airborne focus hop

var _timer := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _jumped := false
var _feet_offset := -1.0          ## body origin height above the floor, measured once
var _wish := Vector3.ZERO         ## this tick's horizontal input direction (unit or zero)
var _intent: Intent
var _land_lag := 0.0
var _push_timer := 0.0
var _last_floor_y := 0.0
var _was_sprinting := false
var _regrab_block := 0.0
var _air_cap := 0.0                ## max horizontal speed this airtime (momentum or drift cap)
# climb / hang
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _climb_t := 0.0
var _climb_dur := 1.0
var _hang_n := Vector3.ZERO
var _hang_top := 0.0
var _hang_t := 0.0


func _init(p: MovementProfile) -> void:
	profile = p


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func dir_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Horizontal velocity in the body's frame: x = right, y = forward (m/s). Drives anims.
func local_velocity() -> Vector2:
	var rel := angle_difference(facing, heading)
	return Vector2(-sin(rel), cos(rel)) * speed


## Stick tilt (0..1) -> target ground speed (m/s), using OoT's curved response.
func stick_to_speed(tilt: float) -> float:
	var p := profile
	if tilt <= p.stick_deadzone:
		return 0.0
	var t := (tilt - p.stick_deadzone) / (1.0 - p.stick_deadzone)
	if not p.use_oot_stick_curve:
		return t * p.run_speed
	# OoT: ((1 - cos(t * 98.9°))^2 * 30 + 7) * 0.14 u/f, capped at 6 u/f.
	var c := 1.0 - cos(t * deg_to_rad(98.9))
	var units := (c * c * 30.0 + 7.0) * 0.14
	return minf(units / 6.0, 1.0) * p.run_speed


func reset(yaw: float) -> void:
	speed = 0.0
	heading = yaw
	facing = yaw
	invulnerable = false
	hop = Hop.NONE
	_set_state(State.AIR)


func is_busy() -> bool:
	return state == State.CLIMB or state == State.HANG


## Mid-move (roll, backflip, sidehop, bonk, climb/hang): no shooting, throwing or
## grappling until it's over. No animation cancelling.
func action_locked() -> bool:
	return state == State.ROLL or state == State.BONK or is_busy() or hop != Hop.NONE


func step(body: CharacterBody3D, wish: Vector3, delta: float, intent: Intent) -> void:
	var p := profile
	_intent = intent
	var was_on_floor := body.is_on_floor()
	if was_on_floor:
		_last_floor_y = body.global_position.y
	var tilt := minf(Vector2(wish.x, wish.z).length(), 1.0)
	var has_input := tilt > p.stick_deadzone
	_wish = Vector3(wish.x, 0.0, wish.z).normalized() if has_input else Vector3.ZERO
	var sprinting := intent.sprint and not intent.focus
	var target_speed := stick_to_speed(tilt) * intent.speed_mult * (p.sprint_multiplier if sprinting else 1.0)
	var target_yaw := yaw_of(wish) if has_input else heading
	_regrab_block = maxf(0.0, _regrab_block - delta)

	# Climbing / hanging drive the body directly (no physics move this tick).
	if state == State.CLIMB:
		_tick_climb(body, delta)
		return
	if state == State.HANG:
		_tick_hang(body, intent, delta)
		return

	_coyote = p.coyote_time if was_on_floor else _coyote - delta
	_jump_buffer = p.jump_buffer_time if intent.jump_pressed else _jump_buffer - delta
	var sprint_start := sprinting and has_input and not _was_sprinting
	_was_sprinting = sprinting and has_input

	match state:
		State.ROLL:
			_tick_roll(body, tilt, delta, has_input, target_yaw, intent)
		State.BONK:
			_tick_bonk(delta)
		_:
			if was_on_floor:
				target_speed = maxf(0.0, target_speed - _slope_penalty(body))
				if intent.focus:
					_tick_focus_ground(intent, target_speed, target_yaw, has_input, delta)
				else:
					_tick_ground(target_speed, target_yaw, has_input, delta)
				if intent.roll_pressed and (has_input or speed > 0.5 or intent.focus):
					_start_roll(target_yaw if has_input else facing)
				elif sprint_start and p.sprint_starts_with_roll and state == State.GROUND:
					_start_roll(target_yaw)  # sprint kicks off with a roll
			else:
				_tick_air(target_speed, target_yaw, has_input, delta)

	# Jump while Z-targeting (or aiming the bow) with a side/back direction = sidehop / backflip.
	if intent.focus and intent.allow_hops and has_input and _jump_buffer > 0.0 \
			and was_on_floor and state == State.GROUND:
		var rel := angle_difference(intent.focus_yaw, target_yaw)
		if absf(rel) > deg_to_rad(45.0):
			_jump_buffer = 0.0
			_focus_hop(body, rel, intent.focus_yaw)

	# Jump (battle-royale addition; kept in focus too).
	if p.allow_manual_jump and _jump_buffer > 0.0 and _coyote > 0.0 \
			and (state == State.GROUND or state == State.AIR) and hop == Hop.NONE:
		body.velocity.y = p.jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		_jumped = true
		_set_state(State.AIR)
		jumped.emit(false)
	if _jumped and not intent.jump_held and body.velocity.y > 0.0:
		body.velocity.y *= p.jump_cut
		_jumped = false

	if not was_on_floor:
		body.velocity.y = maxf(body.velocity.y - p.gravity * delta, -p.max_fall_speed)

	var horiz := dir_of(heading) * speed
	body.velocity.x = horiz.x
	body.velocity.z = horiz.z
	body.move_and_slide()
	_after_move(body, was_on_floor, has_input, delta)
	_update_facing(intent, delta)
	heading = wrapf(heading, -PI, PI)
	facing = wrapf(facing, -PI, PI)


func _update_facing(intent: Intent, delta: float) -> void:
	var p := profile
	if state == State.BONK or state == State.CLIMB or state == State.HANG or state == State.ROLL:
		return
	if intent.focus:
		if intent.instant_facing:
			facing = intent.focus_yaw
		else:
			facing = rotate_toward(facing, intent.focus_yaw, deg_to_rad(p.focus_facing_rate_deg) * delta)
	else:
		facing = rotate_toward(facing, heading, deg_to_rad(p.facing_turn_rate_deg) * delta)


# ---------------------------------------------------------------- ground
func _tick_ground(target_speed: float, target_yaw: float, has_input: bool, delta: float) -> void:
	var p := profile
	_set_state(State.GROUND)
	if _land_lag > 0.0:
		_land_lag -= delta
		speed = move_toward(speed, 0.0, p.brake_decel * delta)
		return
	if has_input and speed < 0.05:
		heading = target_yaw  # from standstill OoT turns instantly and starts running
	if has_input and absf(angle_difference(heading, target_yaw)) > deg_to_rad(p.reverse_angle_deg):
		speed = move_toward(speed, 0.0, p.brake_decel * delta)  # stick flipped: brake, then snap
		if speed == 0.0:
			heading = target_yaw
		return
	var rate := p.accel if target_speed > speed else p.decel
	speed = move_toward(speed, target_speed, rate * delta)
	if has_input:
		heading = rotate_toward(heading, target_yaw, deg_to_rad(p.turn_rate_deg) * delta)


## Z-target walking: speed depends on direction relative to the focus.
func _tick_focus_ground(intent: Intent, target_speed: float, wish_yaw: float, has_input: bool, delta: float) -> void:
	var p := profile
	_set_state(State.GROUND)
	if _land_lag > 0.0:
		_land_lag -= delta
		speed = move_toward(speed, 0.0, p.brake_decel * delta)
		return
	if has_input:
		if intent.oot_strafe_speeds:
			var fwd := cos(angle_difference(intent.focus_yaw, wish_yaw))
			var mult := lerpf(p.focus_side_mult, p.focus_forward_mult, fwd) if fwd >= 0.0 \
				else lerpf(p.focus_side_mult, p.focus_back_mult, -fwd)
			target_speed *= mult
		if speed < 0.05:
			heading = wish_yaw
		elif absf(angle_difference(heading, wish_yaw)) > deg_to_rad(p.focus_reverse_angle_deg):
			speed = move_toward(speed, 0.0, p.decel * delta)
			if speed == 0.0:
				heading = wish_yaw
			return
		elif intent.oot_strafe_speeds:
			heading = lerp_angle(heading, wish_yaw, 1.0 - exp(-p.focus_heading_lerp * delta))
		else:
			heading = rotate_toward(heading, wish_yaw, deg_to_rad(p.turn_rate_deg * 2.0) * delta)
	var rate := p.accel if target_speed > speed else p.decel
	speed = move_toward(speed, target_speed, rate * delta)


## OoT's A while Z-targeting (here: jump + direction): sidehop or backflip.
func _focus_hop(body: CharacterBody3D, rel: float, focus_yaw: float) -> void:
	var p := profile
	if absf(rel) >= deg_to_rad(135.0):
		_start_hop(body, Hop.BACKFLIP, focus_yaw + PI, p.backflip_speed, p.backflip_up)
	elif rel > 0.0:
		_start_hop(body, Hop.SIDE_LEFT, focus_yaw + PI * 0.5, p.sidehop_speed, p.sidehop_up)
	else:
		_start_hop(body, Hop.SIDE_RIGHT, focus_yaw - PI * 0.5, p.sidehop_speed, p.sidehop_up)


func _start_hop(body: CharacterBody3D, kind: Hop, yaw: float, spd: float, up: float) -> void:
	hop = kind
	heading = yaw
	speed = spd
	body.velocity.y = up
	_coyote = 0.0
	_jump_buffer = 0.0
	_jumped = false
	_set_state(State.AIR)
	hopped.emit(kind)


# ---------------------------------------------------------------- air
## Air: momentum as a vector, nudged by WASD (capped at take-off speed or the drift cap).
func _tick_air(_target_speed: float, _target_yaw: float, has_input: bool, delta: float) -> void:
	var p := profile
	_set_state(State.AIR)
	if hop != Hop.NONE:
		return  # committed: OoT gives no steering during sidehops / backflips
	var v := dir_of(heading) * speed
	if has_input:
		v += _wish * p.air_accel * delta
		if v.length() > _air_cap:
			v = v.normalized() * _air_cap
	else:
		v = v.move_toward(Vector3.ZERO, p.air_decel * delta)
	speed = v.length()
	if speed > 0.01:
		heading = yaw_of(v)
	_air_cap = minf(_air_cap, maxf(speed, p.air_drift_max_speed))  # slowing down lowers the cap


# ---------------------------------------------------------------- roll / bonk
## Rolls always turn you into the roll; you come out facing that way.
func _start_roll(yaw: float) -> void:
	heading = yaw
	facing = yaw
	_timer = 0.0
	_set_state(State.ROLL)
	var rel := angle_difference(facing, yaw)
	var dir := RollDir.FORWARD
	if absf(rel) > deg_to_rad(135.0):
		dir = RollDir.BACK
	elif rel > deg_to_rad(45.0):
		dir = RollDir.LEFT
	elif rel < deg_to_rad(-45.0):
		dir = RollDir.RIGHT
	rolled.emit(dir)


func _tick_roll(body: CharacterBody3D, tilt: float, delta: float, has_input: bool,
		target_yaw: float, intent: Intent) -> void:
	var p := profile
	_timer += delta
	if p.roll_follows_camera:
		var goal := target_yaw
		if not has_input:
			goal = intent.camera_yaw
			if absf(angle_difference(heading, goal)) > deg_to_rad(100.0):
				goal = heading  # don't U-turn a back-roll just because the stick was let go
		heading = rotate_toward(heading, goal, deg_to_rad(p.roll_steer_rate_deg) * delta)
		facing = heading
	invulnerable = _timer >= p.roll_iframe_start and _timer < p.roll_iframe_end
	var target := maxf(stick_to_speed(tilt) * p.roll_speed_multiplier, p.roll_min_speed)
	var rate := p.accel if target > speed else p.decel
	speed = move_toward(speed, target, rate * delta)
	if not body.is_on_floor():
		invulnerable = false
		_set_state(State.AIR)
	elif _timer >= p.roll_duration:
		invulnerable = false
		_set_state(State.GROUND)


func _tick_bonk(delta: float) -> void:
	_timer += delta
	speed = move_toward(speed, 0.0, profile.bonk_decel * delta)
	if _timer >= profile.bonk_duration:
		_set_state(State.GROUND)


# ---------------------------------------------------------------- after physics
func _after_move(body: CharacterBody3D, was_on_floor: bool, has_input: bool, delta: float) -> void:
	var p := profile
	var on_floor := body.is_on_floor()
	_measure_feet(body)

	if on_floor and not was_on_floor:
		_jumped = false
		if hop != Hop.NONE:
			hop = Hop.NONE
			_land_lag = p.hop_land_lag
		landed.emit()

	# Bonk: rolling fast straight into a wall.
	if state == State.ROLL and speed >= p.bonk_min_speed:
		var fwd := dir_of(heading)
		for i in body.get_slide_collision_count():
			var n := body.get_slide_collision(i).get_normal()
			if absf(n.y) < 0.7 and fwd.dot(-n) > cos(deg_to_rad(p.bonk_max_angle_deg)):
				speed = -speed * 0.5
				_timer = 0.0
				invulnerable = false
				_set_state(State.BONK)
				bonked.emit()
				return

	# Ledges: push into a ledge to get up it.
	if on_floor and state == State.GROUND and has_input:
		if _try_climb(body, delta):
			return
	else:
		_push_timer = 0.0

	# Falling into a wall: grab its ledge.
	if state == State.AIR and hop == Hop.NONE and body.velocity.y < 0.0 and _regrab_block <= 0.0:
		if _try_air_grab(body):
			return

	# Left the floor without jumping.
	if was_on_floor and not on_floor and not _jumped and hop == Hop.NONE \
			and body.velocity.y <= 0.01 and state != State.BONK:
		var drop := _drop_below(body)
		var backing := _intent.focus and absf(angle_difference(facing, heading)) > deg_to_rad(120.0)
		if backing and drop > p.walkoff_grab_min_drop and _try_edge_grab(body):
			return
		if p.auto_ledge_jump and speed > 0.5 and not backing and drop > p.ledge_min_drop:
			# OoT ledge hop: running off a real drop (not a step) launches you forward.
			if speed > p.ledge_full_hop_speed:
				body.velocity.y = p.ledge_full_hop_velocity
			else:
				body.velocity.y = p.ledge_small_hop_base + p.ledge_small_hop_per_speed * speed
			_coyote = 0.0
			jumped.emit(true)


# ---------------------------------------------------------------- ledges
## Wall you're pushing into: returns {normal, point} or {}.
func _wall_ahead(body: CharacterBody3D, dir: Vector3) -> Dictionary:
	if dir == Vector3.ZERO:
		return {}
	var min_dot := cos(deg_to_rad(profile.climb_wall_angle_deg))
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) > 0.3:
			continue
		var col := c.get_collider()
		if col is Node and (col as Node).is_in_group("no_climb"):
			continue
		var flat := Vector3(n.x, 0.0, n.z).normalized()
		if dir.dot(-flat) > min_dot:
			return { "normal": flat, "point": c.get_position() }
	return {}


## Top of the ledge on the other side of a wall contact. Returns top y or NAN.
func _ledge_top(body: CharacterBody3D, wall: Dictionary, feet_y: float, reach: float) -> float:
	var n: Vector3 = wall.normal
	var pt: Vector3 = wall.point
	var from := Vector3(pt.x, feet_y + reach + 0.15, pt.z) - n * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, feet_y - 0.05, from.z), 1)
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.8:
		return NAN
	if hit.collider is Node and (hit.collider as Node).is_in_group("no_climb"):
		return NAN
	return (hit.position as Vector3).y


func _try_climb(body: CharacterBody3D, delta: float) -> bool:
	var p := profile
	var wall := _wall_ahead(body, _wish)
	if wall.is_empty():
		_push_timer = 0.0
		return false
	var feet := body.global_position.y
	var top := _ledge_top(body, wall, feet, p.climb_reach)
	var h := top - feet
	if is_nan(top) or h < p.ledge_min_height or h > p.climb_reach:
		_push_timer = 0.0
		return false
	var kind := Climb.TALL
	var dur := p.tall_climb_duration
	if h <= p.step_max:
		kind = Climb.STEP
		dur = p.step_duration
	elif h <= p.hop_up_max:
		kind = Climb.HOP_UP
		dur = p.hop_up_duration
	elif h <= p.climb_max:
		kind = Climb.CLIMB
		dur = p.climb_duration
	if kind != Climb.STEP:
		_push_timer += delta
		if _push_timer < p.climb_push_time:
			return false
	var n: Vector3 = wall.normal
	var pt: Vector3 = wall.point
	var dest := Vector3(pt.x, top + 0.03, pt.z) - n * (_radius(body) + 0.12)
	if not _space_free(body, dest):
		return false
	_start_climb(body, dest, kind, dur, n)
	return true


func _start_climb(body: CharacterBody3D, dest: Vector3, kind: Climb, dur: float, n: Vector3) -> void:
	_climb_from = body.global_position
	_climb_to = dest
	_climb_t = 0.0
	_climb_dur = maxf(dur, 0.01)
	_push_timer = 0.0
	speed = 0.0
	body.velocity = Vector3.ZERO
	heading = yaw_of(-n)
	facing = heading
	hop = Hop.NONE
	invulnerable = false
	_set_state(State.CLIMB)
	climbed.emit(kind, _climb_dur)


func _tick_climb(body: CharacterBody3D, delta: float) -> void:
	_climb_t += delta
	var t := clampf(_climb_t / _climb_dur, 0.0, 1.0)
	var up := smoothstep(0.0, 0.65, t)        # rise first...
	var fw := smoothstep(0.45, 1.0, t)        # ...then over the lip
	var pos := Vector3(lerpf(_climb_from.x, _climb_to.x, fw), lerpf(_climb_from.y, _climb_to.y, up),
		lerpf(_climb_from.z, _climb_to.z, fw))
	body.global_position = pos
	body.velocity = Vector3.ZERO
	if t >= 1.0:
		body.global_position = _climb_to
		body.velocity = Vector3(0.0, -1.0, 0.0)
		body.move_and_slide()  # settle onto the ledge so is_on_floor() is fresh
		_last_floor_y = body.global_position.y
		_set_state(State.GROUND)


func _try_air_grab(body: CharacterBody3D) -> bool:
	var p := profile
	var dir := _wish if _wish != Vector3.ZERO else (dir_of(heading) if speed > 0.1 else Vector3.ZERO)
	var wall := _wall_ahead(body, dir)
	if wall.is_empty():
		return false
	var feet := body.global_position.y
	var top := _ledge_top(body, wall, feet, p.grab_max)
	if is_nan(top):
		return false
	var h := top - feet
	if h < p.grab_min or h > p.grab_max:
		return false
	var n: Vector3 = wall.normal
	var pt: Vector3 = wall.point
	return _start_hang(body, Vector3(pt.x, top, pt.z), n, top)


## Backed off an edge: grab the lip you just left.
func _try_edge_grab(body: CharacterBody3D) -> bool:
	var back := -dir_of(heading)
	var from := body.global_position + Vector3.DOWN * 0.2
	var q := PhysicsRayQueryParameters3D.create(from, from + back * 1.2, 1)
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var n := Vector3((hit.normal as Vector3).x, 0.0, (hit.normal as Vector3).z).normalized()
	if n == Vector3.ZERO:
		return false
	var pt: Vector3 = hit.position
	var top := _ledge_top(body, { "normal": n, "point": pt }, _last_floor_y - 1.0, 1.5)
	if is_nan(top):
		return false
	return _start_hang(body, Vector3(pt.x, top, pt.z), n, top)


func _start_hang(body: CharacterBody3D, wall_point: Vector3, n: Vector3, top: float) -> bool:
	var p := profile
	var pos := Vector3(wall_point.x, top - p.hang_offset, wall_point.z) + n * (_radius(body) + 0.03)
	if not _space_free(body, pos):
		return false
	body.global_position = pos
	body.velocity = Vector3.ZERO
	speed = 0.0
	heading = yaw_of(-n)
	facing = heading
	hop = Hop.NONE
	_hang_n = n
	_hang_top = top
	_hang_t = 0.0
	_jumped = false
	_set_state(State.HANG)
	grabbed_ledge.emit()
	return true


func _tick_hang(body: CharacterBody3D, intent: Intent, delta: float) -> void:
	var p := profile
	_hang_t += delta
	body.velocity = Vector3.ZERO
	if _hang_t < p.hang_grab_delay:
		return
	var into := _wish.dot(-_hang_n)
	if into > 0.5 or intent.jump_pressed or intent.roll_pressed:
		var dest := body.global_position - _hang_n * (_radius(body) * 2.0 + 0.2)
		dest.y = _hang_top + 0.05
		if _space_free(body, dest):
			_start_climb(body, dest, Climb.PULL_UP, p.pull_up_duration, _hang_n)
	elif into < -0.5:
		body.global_position += _hang_n * 0.12  # let go
		_regrab_block = p.drop_regrab_delay
		_coyote = 0.0
		_set_state(State.AIR)


# ---------------------------------------------------------------- helpers
func _collision_shape(body: CharacterBody3D) -> CollisionShape3D:
	for c in body.get_children():
		if c is CollisionShape3D:
			return c
	return null


func _radius(body: CharacterBody3D) -> float:
	var cs := _collision_shape(body)
	if cs and cs.shape is CapsuleShape3D:
		return (cs.shape as CapsuleShape3D).radius
	return 0.4


## Would the body fit with its feet at `feet_pos`?
func _space_free(body: CharacterBody3D, feet_pos: Vector3) -> bool:
	var cs := _collision_shape(body)
	if cs == null:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cs.shape
	q.transform = Transform3D(Basis(), feet_pos + cs.position + Vector3.UP * 0.02)
	q.collision_mask = 1
	q.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## How far the ground is below the feet, probed a little ahead of the body.
func _drop_below(body: CharacterBody3D) -> float:
	if _feet_offset < 0.0:
		return 0.0
	var from := body.global_position + Vector3.UP * 0.5 + dir_of(heading) * 0.3
	var depth := _ray_depth(body, from, _feet_offset + 0.5 + profile.ledge_min_drop + 2.0)
	return depth - (_feet_offset + 0.5)


func _measure_feet(body: CharacterBody3D) -> void:
	if _feet_offset < 0.0 and body.is_on_floor():
		var d := _ray_depth(body, body.global_position + Vector3.UP * 0.5, 4.0)
		if d < INF:
			_feet_offset = maxf(0.0, d - 0.5)


func _ray_depth(body: CharacterBody3D, from: Vector3, length: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length)
	query.exclude = [body.get_rid()]
	query.collision_mask = 1  # world only
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return INF
	return from.y - (hit.position as Vector3).y


func _slope_penalty(body: CharacterBody3D) -> float:
	var n := body.get_floor_normal()
	var uphill := clampf(-dir_of(heading).dot(n), 0.0, 0.6)
	return profile.slope_slowdown * uphill * uphill


func _set_state(s: State) -> void:
	if s == State.AIR and state != State.AIR:
		_air_cap = maxf(absf(speed), profile.air_drift_max_speed)
	if s != state:
		state = s
		state_changed.emit(s)
