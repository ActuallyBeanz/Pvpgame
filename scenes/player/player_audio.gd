extends Node3D
## Player sounds, driven only by state every peer already has (the player's sync_*
## vars and Equipment's sync_*), so local and remote players sound the same and
## nothing extra goes over the network. Added by player.gd.
##   footsteps  : one per stride while grounded; surface from the collider's
##                metadata/material ("wood", "stone", "straw"; default grass)
##   moves      : jump, land (heavier after a long fall), roll, sidehop, backflip,
##                ledge grab, climb, bonk
##   equipment  : draw / holster, bow draw, boomerang throw / catch

@export var walk_stride := 1.15             ## metres per step at walking speed
@export var run_stride := 1.9               ## metres per step at full run
@export var run_speed := 6.0                ## m/s treated as "full run"
@export var min_step_speed := 0.6
@export var default_surface := "grass"
@export var jump_up_speed := 2.0            ## upward m/s that counts as a jump
@export var land_min_air_time := 0.18
@export var heavy_land_speed := 11.0        ## falling m/s for the heavy landing
@export var foot_height := 0.1

const MotorState := { "BONK": 3, "HANG": 5 }

var _body: CharacterBody3D
var _equip: Node
var _stride_left := 0.0
var _was_floor := true
var _air_time := 0.0
var _max_fall := 0.0
var _last_pos := Vector3.ZERO
var _vy := 0.0
var _seq := -1
var _state := 0
var _drawn := false
var _aiming := false
var _thrown := false
var _ready_done := false


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_equip = _body.get_node_or_null("Equipment")
	_last_pos = _body.global_position
	_was_floor = _body.sync_on_floor


func _physics_process(delta: float) -> void:
	if _body == null or delta <= 0.0:
		return
	var pos := _body.global_position
	_vy = lerpf(_vy, (pos.y - _last_pos.y) / delta, 0.5)
	_last_pos = pos
	if not _ready_done:  # first frame: take current state as the baseline
		_ready_done = true
		_seq = _body.sync_action_seq
		_state = _body.sync_move_state
		if _equip:
			_drawn = _equip.sync_drawn
			_aiming = _equip.sync_aiming
			_thrown = _equip.sync_thrown
		return
	var acted := _check_action()
	_check_state()
	_check_air(delta, acted)
	_check_steps(delta)
	_check_equipment()


func _feet() -> Vector3:
	return _body.global_position + Vector3.UP * foot_height


# ---------------------------------------------------------------- moves
func _check_action() -> bool:
	if _body.sync_action_seq == _seq:
		return false
	_seq = _body.sync_action_seq
	var code := int(_body.sync_action)
	var id := ""
	if code < 4:
		id = "player.roll"
	elif code == 10 or code == 11:
		id = "player.sidehop"
	elif code == 12:
		id = "player.backflip"
	elif code >= 20:
		id = "player.climb"
	if id != "":
		Audio.play_at(id, _feet() + Vector3.UP * 0.5)
	_stride_left = 0.0
	return true


func _check_state() -> void:
	var s := int(_body.sync_move_state)
	if s == _state:
		return
	_state = s
	if s == MotorState.HANG:
		Audio.play_at("player.ledge_grab", _feet() + Vector3.UP * 1.6)
	elif s == MotorState.BONK:
		Audio.play_at("player.bonk", _feet() + Vector3.UP * 1.2)


func _check_air(delta: float, acted: bool) -> void:
	var on_floor: bool = _body.sync_on_floor
	if not on_floor:
		_air_time += delta
		_max_fall = maxf(_max_fall, -_vy)
	if _was_floor and not on_floor and not acted and _vy > jump_up_speed \
			and _state != MotorState.HANG:
		Audio.play_at("player.jump", _feet())
	elif not _was_floor and on_floor:
		if _air_time >= land_min_air_time:
			if _max_fall >= heavy_land_speed:
				Audio.play_at("player.land_heavy", _feet())
			else:
				var loud := remap(clampf(_max_fall, 2.0, heavy_land_speed), 2.0, heavy_land_speed, -8.0, 0.0)
				Audio.play_at("player.land", _feet(), loud)
			_stride_left = run_stride * 0.5   # next step lands half a stride later
		_air_time = 0.0
		_max_fall = 0.0
	_was_floor = on_floor


func _check_steps(delta: float) -> void:
	var speed: float = _body.sync_speed
	if not _body.sync_on_floor or speed < min_step_speed or _state == MotorState.HANG:
		_stride_left = minf(_stride_left, 0.15)  # first step comes quickly when you start
		return
	if _body.sync_action_seq != _seq:
		return
	var k := clampf((speed - 1.5) / (run_speed - 1.5), 0.0, 1.0)
	_stride_left -= speed * delta
	if _stride_left <= 0.0:
		_stride_left += lerpf(walk_stride, run_stride, k)
		var vol := lerpf(-9.0, 0.0, k)
		Audio.play_at("player.footstep." + _surface(), _feet(), vol, lerpf(0.95, 1.05, k))


## Material under the feet: collider (or an ancestor) metadata "material".
func _surface() -> String:
	var space := _body.get_world_3d().direct_space_state
	var from := _body.global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.8, 1)
	q.exclude = [_body.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return default_surface
	var n := hit.collider as Node
	while n and n != get_tree().current_scene:
		if n.has_meta(&"material"):
			var m := str(n.get_meta(&"material"))
			return m if Audio.has_sound("player.footstep." + m) else default_surface
		n = n.get_parent()
	return default_surface


# ---------------------------------------------------------------- equipment
func _check_equipment() -> void:
	if _equip == null:
		return
	var hand := _body.global_position + Vector3.UP * 1.3
	if _equip.sync_drawn != _drawn:
		_drawn = _equip.sync_drawn
		Audio.play_at("weapon.draw" if _drawn else "weapon.holster", hand)
	if _equip.sync_aiming != _aiming:
		_aiming = _equip.sync_aiming
		if _aiming and _equip.weapon_type() == "shoot":
			Audio.play_at("bow.draw", hand)
	if _equip.sync_thrown != _thrown:
		_thrown = _equip.sync_thrown
		Audio.play_at("boomerang.throw" if _thrown else "boomerang.catch", hand)
