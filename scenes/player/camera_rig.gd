extends Node3D
## Camera for the local player. Third person by default; "toggle_camera" (V / right
## stick click) switches to first person. Yaw on this node, pitch on $Pivot,
## SpringArm3D keeps the camera out of walls. Tune on player.tscn > CameraRig.
## Runs top-level and follows the player's *interpolated* position every rendered
## frame, so movement stays smooth on high-refresh monitors.

signal view_changed(first_person: bool)

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var stick_sensitivity := 3.0
@export var invert_y := false
@export_range(-89.0, 0.0) var min_pitch_deg := -70.0
@export_range(0.0, 89.0) var max_pitch_deg := 50.0

@export_group("Third Person")
@export var start_first_person := false
@export var height := 1.6               ## pivot height above the player's feet
@export var distance := 5.0
@export var min_distance := 2.0
@export var max_distance := 9.0
@export var zoom_step := 0.6
@export var zoom_smoothing := 12.0
@export var shoulder_offset := 0.6      ## sideways offset (over-the-shoulder)

@export_group("First Person")
@export var eye_height := 1.5
@export var fp_fov := 80.0
@export_range(-89.0, 0.0) var fp_min_pitch_deg := -85.0
@export_range(0.0, 89.0) var fp_max_pitch_deg := 85.0
@export var view_blend_speed := 14.0    ## how fast the camera slides between views

var active := false
var first_person := false
var _target: Node3D
var _yaw := 0.0
var _pitch := deg_to_rad(-20.0)
var _target_distance := 5.0
var _fp := 0.0                          # 0 = third person, 1 = first person
var _tp_fov := 70.0
var _arm_len := 5.0
var _aim := 0.0                         # 0..1 aim blend
var _aim_on := false
var _aim_fov := 52.0
var _aim_distance := 2.4
var _aim_shoulder := 0.85
@export var aim_blend_speed := 12.0

@export_group("Focus (hold RMB)")
@export var focus_turn_speed := 10.0          ## how fast the camera swings behind you
@export var focus_lock_pitch_bias_deg := -8.0 ## look slightly down at a locked target
@export var focus_auto_swing := true          ## swing behind you on focus (and onto a new lock) until you look around
@export var focus_look_cancel_px := 6.0       ## mouse movement that hands the camera back to you
@export var focus_shoulder := 0.0             ## centre the camera while focused, like OoT
var _focus_on := false
var _focus_yaw := 0.0
var _focus_point: Variant = null
var _focus := 0.0
var _focus_manual := false
var _look_accum := 0.0

@onready var pivot: Node3D = $Pivot
@onready var arm: SpringArm3D = $Pivot/SpringArm3D
@onready var camera: Camera3D = $Pivot/SpringArm3D/Camera3D


## Spectating: follow another body (or your own again).
func follow(body: CollisionObject3D) -> void:
	if body == null or body == _target:
		return
	if is_instance_valid(_target):
		arm.remove_excluded_object(_target.get_rid())
	_target = body
	arm.add_excluded_object(body.get_rid())


func activate(owner_body: CollisionObject3D) -> void:
	active = true
	_target = owner_body
	_target_distance = distance
	_arm_len = distance
	_tp_fov = camera.fov
	_yaw = owner_body.global_rotation.y
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arm.add_excluded_object(owner_body.get_rid())
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_first_person(start_first_person)
	_fp = 1.0 if first_person else 0.0


func set_first_person(on: bool) -> void:
	first_person = on
	view_changed.emit(on)


## Horizontal camera rotation: the player uses it for camera-relative movement.
func yaw_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


## Called every frame by Equipment. stats: BowStats-like resource (aim_fov, aim_distance, aim_shoulder).
func set_aim(on: bool, stats: Resource = null) -> void:
	_aim_on = on
	if stats:
		_aim_fov = stats.aim_fov
		_aim_distance = stats.aim_distance
		_aim_shoulder = stats.aim_shoulder


func get_yaw() -> float:
	return _yaw


## Called every physics tick by the player. point = locked target's lock point or null.
func set_focus(on: bool, yaw: float, point: Variant) -> void:
	if on and not _focus_on:
		_focus_manual = not focus_auto_swing
		_look_accum = 0.0
	if point != null and _focus_point == null and focus_auto_swing:
		_focus_manual = false  # new lock: swing onto it
		_look_accum = 0.0
	_focus_on = on
	_focus_yaw = yaw
	_focus_point = point


func is_focusing() -> bool:
	return _focus_on


func _unhandled_input(event: InputEvent) -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("toggle_camera"):
		set_first_person(not first_person)
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		_note_look(absf(m.relative.x) + absf(m.relative.y))
		var sens := mouse_sensitivity * UserSettings.mouse_mult
		var inv := invert_y != UserSettings.invert_y
		_yaw -= m.relative.x * sens
		_pitch -= m.relative.y * sens * (-1.0 if inv else 1.0)
	elif event is InputEventMouseButton and event.pressed and not first_person:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance -= zoom_step
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance += zoom_step
	_target_distance = clampf(_target_distance, min_distance, max_distance)


func _process(delta: float) -> void:
	if not active or not is_instance_valid(_target):
		return
	if GameConfig.gameplay_input_enabled:
		var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if stick.length() > 0.3:
			_note_look(focus_look_cancel_px)
		_yaw -= stick.x * stick_sensitivity * delta
		_pitch -= stick.y * stick_sensitivity * delta * (-1.0 if invert_y != UserSettings.invert_y else 1.0)

	_update_focus(delta)
	var goal := 1.0 if first_person else 0.0
	_fp = lerpf(_fp, goal, 1.0 - exp(-view_blend_speed * delta))
	if absf(_fp - goal) < 0.01:
		_fp = goal
	var lo := lerpf(min_pitch_deg, fp_min_pitch_deg, _fp)
	var hi := lerpf(max_pitch_deg, fp_max_pitch_deg, _fp)
	_pitch = clampf(_pitch, deg_to_rad(lo), deg_to_rad(hi))

	var feet := _target.get_global_transform_interpolated().origin
	global_position = feet + Vector3(0.0, lerpf(height, eye_height, _fp), 0.0)
	rotation = Vector3(0.0, _yaw, 0.0)
	pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	_aim = lerpf(_aim, 1.0 if _aim_on else 0.0, 1.0 - exp(-aim_blend_speed * delta))
	arm.position.x = lerpf(lerpf(shoulder_offset, focus_shoulder, _focus), _aim_shoulder, _aim) * (1.0 - _fp)
	_arm_len = lerpf(_arm_len, _target_distance, 1.0 - exp(-zoom_smoothing * delta))
	arm.spring_length = lerpf(_arm_len, minf(_aim_distance, _arm_len), _aim) * (1.0 - _fp)
	var base_fov := lerpf(_tp_fov, fp_fov, _fp)
	camera.fov = lerpf(base_fov, minf(_aim_fov, base_fov), _aim)


func _update_focus(delta: float) -> void:
	_focus = lerpf(_focus, 1.0 if _focus_on else 0.0, 1.0 - exp(-focus_turn_speed * delta))
	if not _focus_on:
		return
	if _focus_manual:
		return  # you're looking around: the body stays on its plane, the camera is yours
	var k := 1.0 - exp(-focus_turn_speed * delta)
	_yaw = lerp_angle(_yaw, _focus_yaw, k)
	if _focus_point != null:
		var to: Vector3 = (_focus_point as Vector3) - global_position
		var bias := 0.0 if _aim_on else deg_to_rad(focus_lock_pitch_bias_deg)  # aiming: centre it
		var goal_pitch := atan2(to.y, Vector2(to.x, to.z).length()) + bias
		_pitch = lerpf(_pitch, goal_pitch, k)


func _note_look(amount: float) -> void:
	if not _focus_on or _focus_manual:
		return
	_look_accum += amount
	if _look_accum >= focus_look_cancel_px:
		_focus_manual = true
