extends CharacterBody3D
## Networked 3rd-person player.
## Movement: OoT-style motor (scenes/player/movement_motor.gd, tuned in
## data/config/default_movement.tres). Each peer simulates its OWN player (owner
## authority, prototype choice for responsive feel); everyone else sees a smoothed copy
## driven by $Sync. Combat hits, pickups and world changes stay host-authoritative.
## Controls: WASD move · Shift sprint (starts with a roll) · Space jump · Ctrl roll (any
## direction, also focused / aiming) · hold RMB focus: turn to face the camera's direction,
## then strafe; Space + side/back = sidehop / backflip (also while aiming the bow; a roll
## cancels the draw — release and press LMB again) · push into ledges to climb · fall
## into a ledge to grab it (forward = pull up, back = drop).

const CameraRig := preload("res://scenes/player/camera_rig.gd")
const Motor := preload("res://scenes/player/movement_motor.gd")
const FocusTargeting := preload("res://scenes/player/focus_targeting.gd")
const MovementProfile := preload("res://data/config/movement_profile.gd")
const PlayerAudio := preload("res://scenes/player/player_audio.gd")
const FX := preload("res://systems/components/element_fx.gd")

@export var movement: MovementProfile = preload("res://data/config/default_movement.tres")

@export_group("Network")
@export var remote_smoothing := 18.0
@export var remote_snap_distance := 8.0
@export var kill_height := -40.0

@export_group("Model")
@export var model_id := "player.adventurer.knight"

# Set by the spawner before _ready (same data on every peer).
var display_name := "Player"
var color_index := 0
var spawn_point := Vector3.ZERO

# Replicated owner -> everyone via $Sync (see player.tscn replication config).
var sync_position := Vector3.ZERO
var sync_yaw := 0.0
var sync_speed := 0.0               ## horizontal speed, drives locomotion anims
var sync_on_floor := true
var sync_move_state := 0            ## Motor.State
var sync_action := 0                ## ACTION_* of the latest move (roll, hop, climb...)
var sync_action_time := 0.0         ## its duration, for scaling anims
var sync_action_seq := 0            ## +1 per move (lets remotes replay the anim)
var sync_strafe := Vector2.ZERO     ## local velocity (x right, y forward) for strafe anims
var sync_focus := false

## Move action codes (sync_action). Rolls use Motor.RollDir (0-3).
const ACTION_SIDEHOP_LEFT := 10
const ACTION_SIDEHOP_RIGHT := 11
const ACTION_BACKFLIP := 12
const ACTION_CLIMB_BASE := 20      ## + Motor.Climb

var motor: Motor

@onready var model_root: Node3D = $Model
@onready var camera_rig: CameraRig = $CameraRig
@onready var equipment: Node = $Equipment
@onready var focus: FocusTargeting = $Focus


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	sync_position = global_position
	motor = Motor.new(movement)
	motor.reset(rotation.y)
	motor.rolled.connect(_on_rolled)
	motor.hopped.connect(_on_hopped)
	motor.climbed.connect(func(kind: int, dur: float) -> void: _action(ACTION_CLIMB_BASE + kind, dur))
	_build_model()
	var sfx := PlayerAudio.new()
	sfx.name = "Audio"
	add_child(sfx)
	if is_local():
		camera_rig.view_changed.connect(_on_view_changed)
		camera_rig.activate(self)
	else:
		camera_rig.queue_free()
		camera_rig = null


func is_local() -> bool:
	return is_multiplayer_authority()


func _physics_process(delta: float) -> void:
	if is_local():
		_simulate(delta)
	else:
		_follow_remote(delta)


func _simulate(delta: float) -> void:
	var can_act := GameConfig.gameplay_input_enabled
	# Raw stick (no action deadzone): the motor applies OoT's own stick curve.
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.05) \
		if can_act else Vector2.ZERO
	focus.update(can_act, equipment.lock_on_range())
	var aiming: bool = equipment.is_aiming()
	var roll_pressed := can_act and Input.is_action_just_pressed("roll")
	var rolling := roll_pressed or motor.state == Motor.State.ROLL
	# Focused: input is relative to the way you're locked facing, so you can look
	# around freely and still strafe on the same plane. Otherwise camera-relative.
	# Rolls always use the camera so you can steer them by swivelling the mouse.
	var move_basis := camera_rig.yaw_basis()
	if focus.active and not aiming and not camera_rig.first_person and not rolling:
		move_basis = Basis(Vector3.UP, focus.focus_yaw())
	var wish := move_basis * Vector3(stick.x, 0.0, stick.y)

	var it := Motor.Intent.new()
	it.jump_pressed = can_act and Input.is_action_just_pressed("jump")
	it.jump_held = can_act and Input.is_action_pressed("jump")
	it.roll_pressed = roll_pressed
	it.camera_yaw = camera_rig.get_yaw()
	it.sprint = can_act and Input.is_action_pressed("sprint") and not aiming
	it.speed_mult = equipment.move_speed_mult()
	if camera_rig.first_person or aiming:
		# Bow aim / first person: face the crosshair and strafe at full speed.
		it.focus = true
		it.focus_yaw = camera_rig.get_yaw()
		it.oot_strafe_speeds = false
		it.instant_facing = camera_rig.first_person
		it.allow_hops = aiming  # sidehop / backflip with the bow drawn
		if focus.active and focus.target == null:
			focus.free_yaw = camera_rig.get_yaw()  # keep the new plane after you stop aiming
	elif focus.active:
		it.focus = true
		it.focus_yaw = focus.focus_yaw()
		it.allow_hops = true
	elif equipment.wants_face_camera():
		# Sword swing / charge / shield up: turn to where the camera looks.
		it.focus = true
		it.focus_yaw = camera_rig.get_yaw()
		it.oot_strafe_speeds = false
	camera_rig.set_focus(focus.active, focus.focus_yaw(), focus.lock_point())

	motor.step(self, wish, delta, it)
	model_root.rotation.y = motor.facing
	if focus.active and focus.target == null and motor.state == Motor.State.ROLL:
		focus.free_yaw = motor.heading  # come out of the roll facing the way you rolled

	if global_position.y < kill_height:
		global_position = spawn_point
		velocity = Vector3.ZERO
		motor.reset(motor.facing)
		reset_physics_interpolation()  # teleport: don't smooth across the jump

	sync_position = global_position
	sync_yaw = motor.facing
	sync_speed = absf(motor.speed)
	sync_on_floor = is_on_floor()
	sync_move_state = motor.state
	sync_strafe = motor.local_velocity()
	sync_focus = it.focus and not camera_rig.first_person


func _on_rolled(dir: int) -> void:
	_action(dir, movement.roll_duration)


func _on_hopped(kind: int) -> void:
	var p := movement
	match kind:
		Motor.Hop.SIDE_LEFT:
			_action(ACTION_SIDEHOP_LEFT, 2.0 * p.sidehop_up / p.gravity)
		Motor.Hop.SIDE_RIGHT:
			_action(ACTION_SIDEHOP_RIGHT, 2.0 * p.sidehop_up / p.gravity)
		Motor.Hop.BACKFLIP:
			_action(ACTION_BACKFLIP, 2.0 * p.backflip_up / p.gravity)


func _action(code: int, duration: float) -> void:
	sync_action = code
	sync_action_time = duration
	sync_action_seq += 1


func _follow_remote(delta: float) -> void:
	var t := 1.0 - exp(-remote_smoothing * delta)
	if global_position.distance_to(sync_position) > remote_snap_distance:
		global_position = sync_position
		reset_physics_interpolation()
	else:
		global_position = global_position.lerp(sync_position, t)
	model_root.rotation.y = lerp_angle(model_root.rotation.y, sync_yaw, t)


## Shield: does a hit travelling in `dir` land on the raised shield (frontal cone)?
func blocks_hit(dir: Vector3) -> bool:
	if not equipment.sync_blocking:
		return false
	var sh: Resource = equipment.shield_item()
	if sh == null:
		return false
	var fwd := -model_root.global_basis.z
	var back := -Vector3(dir.x, 0.0, dir.z)
	if back.length() < 0.01:
		return true
	return rad_to_deg(fwd.angle_to(back.normalized())) <= sh.stats.block_arc_deg * 0.5


## Feedback when the shield stops something (runs on whichever peer saw the hit).
func on_blocked(point: Vector3) -> void:
	Audio.play_at("shield.block", point)
	FX.burst(point, get_tree().current_scene, Color(1.0, 0.9, 0.5), 10, 0.05, 4.0)
	var sh: Resource = equipment.shield_item()
	var model: Node = model_root.get_child(0) if model_root.get_child_count() > 0 else null
	if model and sh and model.has_method("play_action"):
		model.play_action(sh.stats.block_hit_anim, 0.3)


## Roll i-frames. Future damage code should skip hits while this is true.
func is_invulnerable() -> bool:
	return motor != null and motor.invulnerable


## First person: keep our own model's shadow but don't draw it in front of the camera.
func _on_view_changed(first_person: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if first_person \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for n in model_root.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = mode


func _build_model() -> void:
	var model := AssetRegistry.instantiate(model_id)
	model_root.add_child(model)
	var body := model.get_node_or_null("Body") as MeshInstance3D
	if body:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GameConfig.color_for(color_index)
		body.material_override = mat
	var tag := model.get_node_or_null("NameTag") as Label3D
	if tag:
		tag.text = display_name
		tag.visible = not is_local()  # don't show your own name over your head
		tag.reparent(self, false)     # keep the tag from spinning with the model
