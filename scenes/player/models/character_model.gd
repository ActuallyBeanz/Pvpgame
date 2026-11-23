extends Node3D
## Wraps a rigged character (.glb) as a player model and drives it with an
## AnimationTree built in code:
##   legs/body  : idle -> walk -> run blend by speed (+ jump/fall in the air)
##   upper body : aim pose / shoot / draw-holster actions, layered on top via a
##                bone filter so you can run while aiming.
## Reads speed / grounded state from the owning player (sync_speed, sync_on_floor).
## Equipment calls set_aiming / play_shoot / play_action / get_attach_point.

@export var character: PackedScene
@export var model_scale := 0.8            ## KayKit rigs are ~2.3 units; 0.8 ≈ 1.85m
@export var face_flip := true             ## glTF faces +Z, players face -Z
@export var show_hand_items := false      ## KayKit rigs ship holding their whole kit

@export_group("Animations")
@export var anim_idle := &"Idle"
@export var anim_walk := &"Walking_A"
@export var anim_run := &"Running_A"
@export var anim_air := &"Jump_Idle"
@export var anim_strafe_left := &"Running_Strafe_Left"
@export var anim_strafe_right := &"Running_Strafe_Right"
@export var anim_back := &"Walking_Backwards"
@export var anim_dodge: Array[StringName] = [&"Dodge_Forward", &"Dodge_Backward", &"Dodge_Left", &"Dodge_Right"]
@export var anim_bonk := &"Hit_B"
## Custom OoT moves authored in Blender on the KayKit rig (art_src/anims/make_oot_anims.py),
## loaded as animation library "oot" so they work on every adventurer.
@export var moves_library_path := "res://assets/animations/oot_moves.glb"
@export var anim_roll := &"oot/OoT_Roll"
@export var anim_backflip := &"oot/OoT_Backflip"
@export var anim_hop_up := &"oot/OoT_LedgeHopUp"
@export var anim_climb := &"oot/OoT_LedgeClimb"
@export var anim_hang := &"oot/OoT_LedgeHang"
@export var sidehop_anim_time := 0.35

@export_group("Tuning")
@export var walk_anim_speed := 2.5        ## m/s where walk plays at 1x
@export var run_anim_speed := 7.0         ## m/s where run plays at 1x
@export var air_blend_time := 0.15
@export var strafe_side_speed := 2.8      ## m/s where strafe anims play at 1x (OoT 0.4x run)
@export var strafe_back_speed := 2.1      ## m/s for the back-walk anim (OoT 0.3x run)
@export var dodge_duration := 0.8         ## matches the motor's roll_duration
@export var focus_blend_speed := 10.0
@export var upper_blend_speed := 12.0
@export var upper_body_bones: PackedStringArray = [
	"spine", "chest", "head",
	"upperarm.l", "lowerarm.l", "wrist.l", "hand.l", "handslot.l",
	"upperarm.r", "lowerarm.r", "wrist.r", "hand.r", "handslot.r",
	"elbowIK.l", "handIK.l", "elbowIK.r", "handIK.r",
]

var visual: Node3D
var anim: AnimationPlayer
var tree: AnimationTree
var _owner_body: Node
var _aim_node: AnimationNodeAnimation
var _shoot_node: AnimationNodeAnimation
var _action_node: AnimationNodeAnimation
var _full_node: AnimationNodeAnimation
var _aiming := false
var _upper := 0.0
var _action_left := 0.0
var _focus := 0.0
var _roll_seq := -1
static var _moves_lib: AnimationLibrary
var _move_state := 0

const LOOPING := ["anim_idle", "anim_walk", "anim_run", "anim_air", "anim_strafe_left", "anim_strafe_right", "anim_back"]


func _ready() -> void:
	if character == null:
		push_error("CharacterModel: no character scene set on %s" % name)
		return
	visual = character.instantiate() as Node3D
	visual.name = "Visual"
	visual.scale = Vector3.ONE * model_scale
	if face_flip:
		visual.rotation.y = PI
	add_child(visual)
	if not show_hand_items:
		for item in _builtin_hand_items():
			item.visible = false
	anim = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		_add_moves_library()
		for prop: String in LOOPING:
			var a := anim.get_animation(get(prop))
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
		_build_tree()
	var n := get_parent()
	while n and not ("sync_speed" in n):
		n = n.get_parent()
	_owner_body = n


# ---------------------------------------------------------------- public API
## Bone attachment by name: "handslot_r", "handslot_l", "chest", "head".
func get_attach_point(slot: String) -> Node3D:
	return visual.find_child(slot, true, false) as Node3D if visual else null


func set_aiming(on: bool, aim_anim: StringName = &"", shoot_anim: StringName = &"") -> void:
	_aiming = on
	if on and aim_anim != &"" and _aim_node and _aim_node.animation != aim_anim:
		_aim_node.animation = aim_anim
		var a := anim.get_animation(aim_anim)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
	if shoot_anim != &"" and _shoot_node:
		_shoot_node.animation = shoot_anim


func play_shoot() -> void:
	if tree:
		tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Upper-body one-off (draw/holster, pick up, use item...).
func play_action(anim_name: StringName) -> void:
	if tree == null or not anim.has_animation(anim_name):
		return
	_action_node.animation = anim_name
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_action_left = anim.get_animation(anim_name).length * 0.8


## Full-body one-shot (dodge roll, bonk), scaled to last `duration` seconds.
func play_full(anim_name: StringName, duration: float = 0.0) -> void:
	if tree == null or not anim.has_animation(anim_name):
		return
	_full_node.animation = anim_name
	var length := anim.get_animation(anim_name).length
	tree.set("parameters/full_speed/scale", length / duration if duration > 0.0 else 1.0)
	tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Move actions synced by the player (see player.gd ACTION_*).
func _play_move_action(code: int, t: float) -> void:
	if code < 4:
		play_full(anim_roll, t if t > 0.0 else dodge_duration)       # rolls
	elif code == 10 or code == 11:
		play_full(anim_dodge[2 if code == 10 else 3], sidehop_anim_time)  # sidehops
	elif code == 12:
		play_full(anim_backflip, t)                                  # backflip
	elif code == 21:
		play_full(anim_hop_up, t)                                    # ledge hop-up
	elif code >= 22:
		play_full(anim_climb, t)                                     # climb / tall / pull-up


## Adds the "oot" move library (shared, loaded once) to this character's AnimationPlayer.
func _add_moves_library() -> void:
	if _moves_lib == null and ResourceLoader.exists(moves_library_path):
		var src := (load(moves_library_path) as PackedScene).instantiate()
		var ap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			_moves_lib = AnimationLibrary.new()
			for n in ap.get_animation_list():
				var a := ap.get_animation(n).duplicate() as Animation
				a.loop_mode = Animation.LOOP_LINEAR if n == "OoT_LedgeHang" else Animation.LOOP_NONE
				_moves_lib.add_animation(n, a)
		src.free()
	if _moves_lib and not anim.has_animation_library(&"oot"):
		anim.add_animation_library(&"oot", _moves_lib)


# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if tree == null or _owner_body == null:
		return
	var speed: float = _owner_body.sync_speed
	var on_floor: bool = _owner_body.sync_on_floor
	tree.set("parameters/loco/blend_position", speed)
	var ref := walk_anim_speed if speed < (walk_anim_speed + run_anim_speed) * 0.5 else run_anim_speed
	tree.set("parameters/loco_speed/scale", 1.0 if speed < 0.4 else clampf(speed / ref, 0.7, 1.4))
	var hanging: bool = "sync_move_state" in _owner_body and _owner_body.sync_move_state == 5  # Motor.State.HANG
	tree.set("parameters/ground_air/transition_request", "hang" if hanging else ("ground" if on_floor else "air"))
	if "sync_focus" in _owner_body:
		_focus = lerpf(_focus, 1.0 if _owner_body.sync_focus else 0.0, 1.0 - exp(-focus_blend_speed * delta))
		tree.set("parameters/focus_mix/blend_amount", _focus)
		tree.set("parameters/strafe/blend_position", _owner_body.sync_strafe)
		if _roll_seq < 0:
			_roll_seq = _owner_body.sync_action_seq  # don't replay an old move on join
		elif _owner_body.sync_action_seq != _roll_seq:
			_roll_seq = _owner_body.sync_action_seq
			_play_move_action(int(_owner_body.sync_action), float(_owner_body.sync_action_time))
		if _owner_body.sync_move_state != _move_state:
			_move_state = _owner_body.sync_move_state
			if _move_state == 3:  # Motor.State.BONK
				play_full(anim_bonk, 0.6)
	_action_left = maxf(0.0, _action_left - delta)
	var goal := 1.0 if (_aiming or _action_left > 0.0) else 0.0
	_upper = lerpf(_upper, goal, 1.0 - exp(-upper_blend_speed * delta))
	tree.set("parameters/upper/blend_amount", _upper)


# ---------------------------------------------------------------- setup
func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = maxf(run_anim_speed, 1.0)
	loco.add_blend_point(_clip(anim_idle), 0.0, -1, &"idle")
	loco.add_blend_point(_clip(anim_walk), walk_anim_speed, -1, &"walk")
	loco.add_blend_point(_clip(anim_run), run_anim_speed, -1, &"run")
	bt.add_node("loco", loco)
	bt.add_node("loco_speed", AnimationNodeTimeScale.new())
	bt.add_node("air", _clip(anim_air))
	var strafe := AnimationNodeBlendSpace2D.new()
	strafe.min_space = Vector2(-4.0, -4.0)
	strafe.max_space = Vector2(4.0, maxf(run_anim_speed, 4.0))
	strafe.add_blend_point(_clip(anim_idle), Vector2.ZERO, -1, &"idle")
	strafe.add_blend_point(_clip(anim_walk), Vector2(0.0, walk_anim_speed), -1, &"walk")
	strafe.add_blend_point(_clip(anim_run), Vector2(0.0, run_anim_speed), -1, &"run")
	strafe.add_blend_point(_clip(anim_strafe_left), Vector2(-strafe_side_speed, 0.0), -1, &"left")
	strafe.add_blend_point(_clip(anim_strafe_right), Vector2(strafe_side_speed, 0.0), -1, &"right")
	strafe.add_blend_point(_clip(anim_back), Vector2(0.0, -strafe_back_speed), -1, &"back")
	bt.add_node("strafe", strafe)
	bt.add_node("focus_mix", AnimationNodeBlend2.new())
	var ground_air := AnimationNodeTransition.new()
	ground_air.add_input("ground")
	ground_air.add_input("air")
	ground_air.add_input("hang")
	ground_air.xfade_time = air_blend_time
	bt.add_node("ground_air", ground_air)

	_aim_node = _clip(&"1H_Ranged_Aiming")
	_shoot_node = _clip(&"1H_Ranged_Shoot")
	_action_node = _clip(&"Use_Item")
	bt.add_node("aim_pose", _aim_node)
	bt.add_node("shoot_anim", _shoot_node)
	bt.add_node("action_anim", _action_node)
	var shoot := AnimationNodeOneShot.new()
	shoot.fadein_time = 0.05
	shoot.fadeout_time = 0.15
	bt.add_node("shoot", shoot)
	var action := AnimationNodeOneShot.new()
	action.fadein_time = 0.1
	action.fadeout_time = 0.2
	bt.add_node("action", action)

	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	var skel := visual.find_child("Skeleton3D", true, false)
	var skel_path := String(visual.get_path_to(skel))
	for b in upper_body_bones:
		upper.set_filter_path(NodePath("%s:%s" % [skel_path, b]), true)
	bt.add_node("upper", upper)

	bt.connect_node("loco_speed", 0, "loco")
	bt.connect_node("focus_mix", 0, "loco_speed")
	bt.connect_node("focus_mix", 1, "strafe")
	bt.connect_node("ground_air", 0, "focus_mix")
	bt.connect_node("ground_air", 1, "air")
	bt.add_node("hang_anim", _clip(anim_hang))
	bt.connect_node("ground_air", 2, "hang_anim")
	bt.connect_node("shoot", 0, "aim_pose")
	bt.connect_node("shoot", 1, "shoot_anim")
	bt.connect_node("action", 0, "shoot")
	bt.connect_node("action", 1, "action_anim")
	bt.connect_node("upper", 0, "ground_air")
	bt.connect_node("upper", 1, "action")
	_full_node = _clip(anim_dodge[0])
	bt.add_node("full_anim", _full_node)
	bt.add_node("full_speed", AnimationNodeTimeScale.new())
	var full := AnimationNodeOneShot.new()
	full.fadein_time = 0.06
	full.fadeout_time = 0.15
	bt.add_node("full", full)
	bt.connect_node("full_speed", 0, "full_anim")
	bt.connect_node("full", 0, "upper")
	bt.connect_node("full", 1, "full_speed")
	bt.connect_node("output", 0, "full")

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = bt
	visual.add_child(tree)
	tree.root_node = tree.get_path_to(visual)
	tree.anim_player = tree.get_path_to(anim)
	tree.active = true


func _clip(anim_name: StringName) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = anim_name
	return n


func _builtin_hand_items() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for slot in visual.find_children("handslot_*", "BoneAttachment3D", true, false):
		for c in slot.get_children():
			if c is Node3D:
				out.append(c)
	return out
