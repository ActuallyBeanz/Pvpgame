extends Node
## Grapple tools (ItemDef.action_tag "hook"): Grappleclaw (short) / Skytether (long).
## OoT hookshot / longshot feel:
##   hold LMB  = aim (zoomed camera + aim dot: red = something hookable in range)
##   release   = fire the claw at the crosshair
##   tap LMB while focus-locked (RMB) = fire straight at the lock target
## The claw flies straight out; hookable things (group "hook_targets": trees, training
## dummies, the grapple pillar) catch it and reel you in, anything else knocks it back.
## Owner simulates the claw and the pull; everyone else draws it from the synced
## Equipment.sync_hook_phase / sync_hook_tip. Tuning: data/items/hook_stats.gd.

const FX := preload("res://systems/components/element_fx.gd")
const Motor := preload("res://scenes/player/movement_motor.gd")

enum Phase { IDLE, OUT, BACK, PULL }

const HOOK_GROUP := "hook_targets"
const MAX_LINKS := 320

var phase := Phase.IDLE
var latch_point := Vector3.ZERO
var latch_normal := Vector3.BACK
var latched_to: Node3D
var aiming := false
var last_latched := ""                     ## name of the last thing the claw bit (debug / tests)

var _eq: Node
var _player: CharacterBody3D
var _tip := Vector3.ZERO
var _dir := Vector3.FORWARD
var _travelled := 0.0
var _cooldown := 0.0
var _pull_t := 0.0
var _stuck_t := 0.0
var _aim_hookable := false

# visuals (every peer)
var _tip_vis: Node3D
var _tip_model := ""
var _chain: MultiMeshInstance3D
var _dot: MeshInstance3D
var _dot_mat: StandardMaterial3D


func setup(equipment: Node, player: CharacterBody3D) -> void:
	_eq = equipment
	_player = player


func busy() -> bool:
	return phase != Phase.IDLE


func pulling() -> bool:
	return phase == Phase.PULL


func stats() -> Resource:
	var s: Resource = _eq.stats()
	return s if s and "pull_speed" in s else null


func stop_aim() -> void:
	aiming = false
	if _dot:
		_dot.visible = false


## Drop everything (weapon swapped / unequipped / died).
func cancel() -> void:
	stop_aim()
	_set_phase(Phase.IDLE)
	latched_to = null


# ---------------------------------------------------------------- owner: input + claw
## Called by Equipment every frame on the owner while a hook tool is the weapon.
func update(delta: float) -> void:
	var s := stats()
	if s == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var holding := Input.is_action_pressed("attack")
	var pressed := Input.is_action_just_pressed("attack")
	var rolling: bool = _player.motor.state == Motor.State.ROLL
	var ready: bool = _eq.sync_drawn and phase == Phase.IDLE and _cooldown <= 0.0 \
		and _eq._swap_timer < 0.0 and not rolling
	var lock: Node3D = _player.focus.target if _player.focus.active and s.homes_on_lock else null
	if ready and pressed and lock and is_instance_valid(lock):
		stop_aim()
		_fire(lock.get_lock_point(), s)
	elif ready and holding:
		aiming = true
	elif aiming and not holding:
		stop_aim()
		if ready:
			_fire(_aim_query(s).point, s)
	elif not ready:
		stop_aim()
	_eq.sync_aiming = aiming
	_player.camera_rig.set_aim(aiming, s)
	_update_dot(s)
	match phase:
		Phase.OUT:
			_tick_out(s, delta)
		Phase.BACK:
			_tick_back(s, delta)
		Phase.PULL:
			if latched_to != null and not is_instance_valid(latched_to):
				_let_go(s)  # what we were holding burned away
	_eq.sync_hook_tip = _tip


## Camera ray from the crosshair: where the claw would go, and whether it would stick.
func _aim_query(s: Resource) -> Dictionary:
	var cam: Camera3D = _player.camera_rig.camera
	var origin: Vector3 = muzzle_position()
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (s.max_range + 12.0), 3)
	q.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	var point: Vector3 = hit.position if not hit.is_empty() else from + dir * (s.max_range + 12.0)
	var in_range: bool = origin.distance_to(point) <= s.max_range
	if not in_range:
		point = origin + (point - origin).normalized() * s.max_range
	return { "point": point, "hit": not hit.is_empty() and in_range,
		"hookable": not hit.is_empty() and in_range and is_hookable(hit.collider) }


func _fire(at: Vector3, s: Resource) -> void:
	var origin := muzzle_position()
	_dir = (at - origin).normalized()
	if _dir.length_squared() < 0.5:
		_dir = -_player.model_root.global_basis.z
	_tip = origin
	_travelled = 0.0
	_set_phase(Phase.OUT)
	Audio.play_at("hook.fire", origin)
	var model: Node = _eq._model
	if model:
		model.play_shoot()
	print("[hook] fired %s (range %.0fm)" % [_eq.sync_weapon_id, s.max_range])


func _tick_out(s: Resource, delta: float) -> void:
	var step := minf(s.fire_speed * delta, s.max_range - _travelled)
	var to := _tip + _dir * step
	var q := PhysicsRayQueryParameters3D.create(_tip, to + _dir * s.tip_radius, 3)
	q.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_tip = hit.position
		if is_hookable(hit.collider):
			_latch(hit, s)
		else:
			Audio.play_at("hook.deflect", _tip)
			FX.burst(_tip, get_tree().current_scene, Color(1.0, 0.85, 0.5), 6, 0.04, 3.0)
			print("[hook] deflected off %s" % (hit.collider as Node).name)
			_set_phase(Phase.BACK)
		return
	_tip = to
	_travelled += step
	if _travelled >= s.max_range - 0.001:
		_set_phase(Phase.BACK)


func _tick_back(s: Resource, delta: float) -> void:
	var home := muzzle_position()
	var d := home - _tip
	var step: float = s.retract_speed * delta
	if d.length() <= step:
		_tip = home
		_cooldown = s.cooldown
		_set_phase(Phase.IDLE)
		return
	_tip += d.normalized() * step


func _latch(hit: Dictionary, s: Resource) -> void:
	latch_point = hit.position
	latch_normal = hit.normal if (hit.normal as Vector3).length_squared() > 0.5 else -_dir
	latched_to = hit.collider as Node3D
	last_latched = latched_to.name
	_pull_t = 0.0
	_stuck_t = 0.0
	_set_phase(Phase.PULL)
	Audio.play_at("hook.latch", latch_point)
	FX.burst(latch_point, get_tree().current_scene, Color(1.0, 0.9, 0.6), 8, 0.04, 3.5)
	if latched_to.has_method("react_to_hit"):
		latched_to.react_to_hit(s.damage, _dir, false)   # dummies wobble from the bite
	print("[hook] latched onto %s at %.1fm" % [latched_to.name, _travelled])


static func is_hookable(n: Object) -> bool:
	var node := n as Node
	while node:
		if node.is_in_group(HOOK_GROUP):
			return true
		if node is PhysicsBody3D:
			return false
		node = node.get_parent()
	return false


# ---------------------------------------------------------------- owner: reel in
## Called by player.gd instead of the movement motor while latched. Moves the body to
## the latch point. Returns true on the tick it lets go (arrived / blocked / timeout);
## the body's velocity is then the little hop off the surface.
func pull_body(body: CharacterBody3D, delta: float) -> bool:
	var s := stats()
	if s == null or phase != Phase.PULL:
		return true
	var goal := pull_goal(s)
	var d := goal - body.global_position
	_pull_t += delta
	if d.length() < 0.15 or _pull_t > s.max_pull_time:
		_arrive(body, s)
		return true
	var speed := minf(s.pull_speed, d.length() / delta)
	body.velocity = d.normalized() * speed
	var before := body.global_position
	body.move_and_slide()
	var moved := body.global_position.distance_to(before)
	_stuck_t = _stuck_t + delta if moved < speed * delta * 0.3 else 0.0
	if _stuck_t > 0.12:
		_arrive(body, s)
		return true
	_eq.sync_hook_tip = latch_point
	return false


## Where the body ends up: hanging just off the surface with the claw at hand height,
## or standing on top when you hooked the top of something.
func pull_goal(s: Resource) -> Vector3:
	if latch_normal.y > 0.7:
		return latch_point + Vector3.UP * 0.05
	var out := Vector3(latch_normal.x, 0.0, latch_normal.z)
	out = out.normalized() if out.length_squared() > 0.01 else -Vector3(_dir.x, 0.0, _dir.z).normalized()
	return latch_point + out * s.stop_distance - Vector3.UP * s.hand_height


## Direction to push off when letting go (horizontal, away from the surface).
func push_dir() -> Vector3:
	var out := Vector3(latch_normal.x, 0.0, latch_normal.z)
	return out.normalized() if out.length_squared() > 0.01 else Vector3.ZERO


func _arrive(body: CharacterBody3D, s: Resource) -> void:
	body.velocity = push_dir() * s.arrive_push + Vector3.UP * s.arrive_hop
	print("[hook] arrived %.2fm from goal after %.2fs" % [body.global_position.distance_to(pull_goal(s)), _pull_t])
	_let_go(s)


## The claw lets go and snaps back into the launcher (instantly, like OoT).
func _let_go(s: Resource) -> void:
	latched_to = null
	_tip = muzzle_position()
	_cooldown = s.cooldown
	_set_phase(Phase.IDLE)


func _set_phase(p: Phase) -> void:
	phase = p
	if _eq.is_local():
		_eq.sync_hook_phase = p


# ---------------------------------------------------------------- visuals (every peer)
## Launcher muzzle (where the claw sits on the launcher) in world space.
func muzzle_position() -> Vector3:
	var head := _claw_head()
	if head and head is MeshInstance3D and (head as MeshInstance3D).mesh:
		var bb: AABB = (head as MeshInstance3D).mesh.get_aabb()
		return head.global_transform * Vector3(0.0, bb.get_center().y, bb.end.z)
	return _eq._hand_origin()


func _claw_head() -> Node3D:
	var vis: Node3D = _eq._weapon_vis
	if not is_instance_valid(vis):
		return null
	return vis.find_child("ClawHead*", true, false) as Node3D


func update_visuals() -> void:
	var s := stats()
	var out: bool = s != null and _eq.sync_drawn and int(_eq.sync_hook_phase) != Phase.IDLE
	var head := _claw_head()
	if head:
		head.visible = not out
	if not out:
		_free_visuals()
		return
	var from := muzzle_position()
	var tip: Vector3 = _eq.sync_hook_tip
	if _tip_vis == null or _tip_model != s.tip_model_id:
		_free_visuals()
		_tip_model = s.tip_model_id
		_tip_vis = Node3D.new()
		_tip_vis.name = "GrappleClaw"
		_tip_vis.top_level = true
		_tip_vis.add_child(AssetRegistry.instantiate(s.tip_model_id))
		add_child(_tip_vis)
		Audio.attach_loop("hook.chain", _tip_vis)
		_chain = MultiMeshInstance3D.new()
		_chain.name = "Chain"
		_chain.top_level = true
		_chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_chain.multimesh = _make_chain_mesh(s)
		add_child(_chain)
	var dir := tip - from
	if dir.length() > 0.01:
		dir = dir.normalized()
	else:
		dir = -_player.model_root.global_basis.z
	_tip_vis.global_position = tip
	# claw model points -Z: face along the chain (it bites into whatever it latched)
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	_tip_vis.look_at(tip + dir, up)
	_layout_chain(from, tip - dir * 0.06, s)


func _make_chain_mesh(s: Resource) -> MultiMesh:
	var link := TorusMesh.new()
	link.inner_radius = 0.016
	link.outer_radius = 0.034
	link.rings = 6
	link.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = s.chain_color
	mat.metallic = 0.7
	mat.roughness = 0.35
	link.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link
	mm.instance_count = MAX_LINKS
	mm.visible_instance_count = 0
	return mm


## Alternating flat links from the muzzle to the claw.
func _layout_chain(from: Vector3, to: Vector3, s: Resource) -> void:
	var mm := _chain.multimesh
	var span := to - from
	var length := span.length()
	var count := mini(int(length / s.chain_link_spacing), MAX_LINKS)
	mm.visible_instance_count = count
	if count == 0:
		return
	var a := span / length
	var b := a.cross(Vector3.UP)
	if b.length_squared() < 0.01:
		b = a.cross(Vector3.RIGHT)
	b = b.normalized()
	var c := a.cross(b).normalized()
	for i in count:
		var p: Vector3 = from + a * ((i + 0.5) * s.chain_link_spacing)
		# TorusMesh lies in its XZ plane: stretch X along the chain, alternate the ring plane
		var basis := Basis(a * 1.7, b, c) if i % 2 == 0 else Basis(a * 1.7, c, -b)
		mm.set_instance_transform(i, Transform3D(basis, p))


func _free_visuals() -> void:
	for n in [_tip_vis, _chain]:
		if is_instance_valid(n):
			n.queue_free()
	_tip_vis = null
	_chain = null
	_tip_model = ""


func _update_dot(s: Resource) -> void:
	if not aiming:
		if _dot:
			_dot.visible = false
		_aim_hookable = false
		return
	if _dot == null:
		_dot = MeshInstance3D.new()
		_dot.name = "AimDot"
		_dot.top_level = true
		var m := SphereMesh.new()
		m.radius = 0.06
		m.height = 0.12
		m.radial_segments = 8
		m.rings = 4
		_dot_mat = StandardMaterial3D.new()
		_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dot_mat.no_depth_test = true
		m.material = _dot_mat
		_dot.mesh = m
		_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_dot)
	var q := _aim_query(s)
	_aim_hookable = q.hookable
	_dot.visible = q.hit
	_dot.global_position = q.point
	_dot_mat.albedo_color = s.dot_color_hit if q.hookable else s.dot_color_miss


func aim_on_hookable() -> bool:
	return aiming and _aim_hookable
