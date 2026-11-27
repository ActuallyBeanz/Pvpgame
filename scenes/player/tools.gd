extends Node
## World tools, driven by Equipment when one is the drawn weapon (ItemDef.action_tag):
##   "fan"   Galeleaf Fan (Wind Waker Deku Leaf): LMB = gust (shoves players + bombs, blows out
##           fires); hold Jump while falling = glide (limited, refills on landing)
##   "staff" Sandspire Staff: hold LMB = aim (ring shows the spot), release = sand pillar;
##           quick tap LMB = pillar right under your feet (rides you up)
##   "rod"   Rimecaller Rod: LMB = elemental blast in front of you (frost; a Cinderpepper /
##           Sparkthistle infusion turns it fire / shock for a while); hold LMB on water and
##           release = ice platform (bridges, frost only). ToolStats.rod_shoots_orb = orb instead.
##   "trap"  Snapjaw Trap: LMB = set one at your feet (the item is its own ammo)
## The owner decides; the world objects are spawned on every peer by call_local RPCs.

const PillarScript := preload("res://scenes/props/tools/sand_pillar.gd")
const IceScript := preload("res://scenes/props/tools/ice_platform.gd")
const TrapScript := preload("res://scenes/props/tools/snap_trap.gd")
const FX := preload("res://systems/components/element_fx.gd")
const OrbScript := preload("res://scenes/weapons/magic_orb.gd")

var aiming := false
var glide_left := 0.0
var gliding := false
var _eq: Node
var _player: CharacterBody3D
var _cd := 0.0
var _hold_t := 0.0
var _ride: Node3D                          ## pillar rising under me: keep my feet on its top
var _ride_t := 0.0
var _seq := 0
var _mine: Dictionary = { "pillar": [], "ice": [] }    ## my spawned node names, oldest first
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D


func setup(equipment: Node, player: CharacterBody3D) -> void:
	_eq = equipment
	_player = player


## Deku Leaf canopy: while gliding the leaf leaves the hand and opens flat over your head.
var _canopy: Node3D
var _canopy_open := false


func _update_canopy() -> void:
	var glide: bool = _eq.sync_aiming and _eq.sync_drawn and _eq.weapon_type() == "fan" and not _player.sync_on_floor
	if glide == _canopy_open:
		return
	_canopy_open = glide
	var hand: Node3D = _eq._weapon_vis
	if glide:
		if _canopy == null:
			_canopy = AssetRegistry.instantiate("tool.fan.galeleaf")
			_canopy.name = "LeafCanopy"
			_player.model_root.add_child(_canopy)
		# shaft points forward, leaf flat above the head (front tipped up a little)
		_canopy.position = Vector3(0, 2.05, 0.5)
		_canopy.rotation = Vector3(deg_to_rad(-80.0), 0, 0)
		_canopy.scale = Vector3.ONE * 0.3
		_canopy.visible = true
		_canopy.create_tween().tween_property(_canopy, "scale", Vector3.ONE * 1.35, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if hand:
			hand.visible = false
		Audio.play_at("boomerang.catch", _player.global_position + Vector3.UP * 2.0, -6.0, 1.3)
	else:
		if _canopy:
			_canopy.visible = false
		if is_instance_valid(hand):
			hand.visible = true


## Hide previews / aim rings as soon as the tool isn't the drawn weapon any more.
func _process(_delta: float) -> void:
	if _eq == null:
		return
	_update_canopy()
	if not _eq.is_local():
		return
	var tag: String = _eq.weapon_type()
	if not _eq.sync_drawn or not (tag in ["staff", "rod", "trap"]):
		if (_ring and _ring.visible) or (_trap_ghost and _trap_ghost.visible):
			stop()


func stats() -> Resource:
	var s: Resource = _eq.stats()
	return s if s and "gust_range" in s else null


func stop() -> void:
	aiming = false
	if _ring:
		_ring.visible = false
	if _trap_ghost:
		_trap_ghost.visible = false
		_trap_circle.visible = false


## Equipment: every frame on the owner while a tool is the weapon.
func update(delta: float) -> void:
	var s := stats()
	if s == null:
		stop()
		return
	_cd = maxf(0.0, _cd - delta)
	var tag: String = _eq.weapon_type()
	var pressed := Input.is_action_just_pressed("attack")
	var held := Input.is_action_pressed("attack")
	var can_use: bool = _eq.sync_drawn and _eq._swap_timer < 0.0 and _cd <= 0.0 and not _player.motor.action_locked()
	match tag:
		"fan":
			if pressed and can_use and not gliding:      # no gusting while the leaf is open overhead
				_gust(s)
		"trap":
			if pressed and can_use and _eq.ammo_count() > 0:
				_place_trap(s)
		"staff", "rod":
			if held and can_use:
				if not aiming:
					_hold_t = 0.0
				aiming = true
				_hold_t += delta
			elif aiming and not held:
				aiming = false
				if can_use and tag == "staff" and _hold_t < 0.2:
					_pillar_under_feet(s)                   # quick tap: straight up from where you stand
				elif can_use and tag == "rod":
					var tr := _aim_point(s, tag)
					if tr.ok and tr.water and _hold_t >= 0.2 and rod_element() == "frost":
						_freeze(s, tr.pos)                  # held + aimed at water: ice platform
					elif s.rod_shoots_orb:
						_shoot_orb(s)
					else:
						_rod_blast(s, tr.pos if tr.ok else _player.global_position - _player.model_root.global_basis.z * 4.0)
				elif can_use:
					var t := _aim_point(s, tag)
					if t.ok:
						_raise_pillar(s, t.pos, t.get("base", ""))
					else:
						Audio.play("ui.error", -6.0)
			elif not can_use:
				aiming = false
	_eq.sync_aiming = aiming or gliding
	if _player.camera_rig:
		_player.camera_rig.set_aim(aiming, s)
	_update_ring(s, tag)
	_update_trap_preview(s, tag == "trap" and _eq.sync_drawn and _eq.ammo_count() > 0)


# ---------------------------------------------------------------- fan: glide (player.gd asks every tick)
func wants_glide(delta: float) -> bool:
	var s := stats()
	if s == null or _eq.weapon_type() != "fan" or not _eq.sync_drawn:
		gliding = false
		glide_left = s.glide_time if s else 0.0
		return false
	if _player.is_on_floor() or _player.motor.in_water():
		glide_left = s.glide_time
		gliding = false
		return false
	gliding = Input.is_action_pressed("jump") and _player.velocity.y < 0.5 and glide_left > 0.0 \
		and GameConfig.combat_input_enabled()
	if gliding:
		glide_left -= delta
	return gliding


func glide_fall() -> float:
	var s := stats()
	return s.glide_fall_speed if s else 1.6


func glide_speed() -> float:
	var s := stats()
	return s.glide_speed if s else 6.0


# ---------------------------------------------------------------- fan: gust
func _gust(s: Resource) -> void:
	_cd = s.cooldown
	var fwd: Vector3 = -_player.model_root.global_basis.z
	if _player.camera_rig:
		var c: Vector3 = -_player.camera_rig.camera.global_basis.z
		fwd = Vector3(c.x, 0.0, c.z).normalized()
	if _eq._model:
		_eq._model.play_action(&"1H_Melee_Attack_Slice_Horizontal", GUST_TIME)
	rpc_gust.rpc(_player.global_position + Vector3.UP, fwd)
	# the swing pushes you back a little
	if not _player.motor.in_water():
		_player.motor.knock(_player, -fwd * s.gust_recoil + Vector3.UP * 1.5)


@rpc("any_peer", "call_local", "reliable")
func rpc_gust(origin: Vector3, fwd: Vector3) -> void:
	var s := stats()
	var rng: float = s.gust_range if s else 10.0
	var half := deg_to_rad((s.gust_angle_deg if s else 45.0) * 0.5)
	var push: float = s.gust_push if s else 11.0
	var mine := multiplayer.get_remote_sender_id() == 0 or multiplayer.get_remote_sender_id() == multiplayer.get_unique_id()
	# whoosh, cut off when the swing ends
	var snd := Audio.play_at("boomerang.spin", origin, 2.0, 0.7)
	if snd:
		var stream := snd.stream
		get_tree().create_timer(GUST_TIME).timeout.connect(func() -> void:
			if is_instance_valid(snd) and snd.playing and snd.stream == stream:
				snd.stop())
	_gust_fx(origin, fwd, rng)
	var in_cone := func(p: Vector3) -> bool:
		var to := p - origin
		var flat := Vector3(to.x, 0.0, to.z)
		return flat.length() <= rng and flat.length() > 0.2 and fwd.angle_to(flat.normalized()) <= half
	# bombs: every peer pushes its own copies
	for b in get_tree().get_nodes_in_group("bombs"):
		if not b.exploded and in_cone.call((b as Node3D).global_position):
			b.velocity += fwd * push * 0.8 + Vector3.UP * 3.0
			b._rest = false
	# dummies / targets sway in the wind (visual, every peer)
	for t in get_tree().get_nodes_in_group("lock_targets"):
		if t is CharacterBody3D or not t.has_method("react_to_hit"):
			continue
		var tp: Vector3 = (t as Node3D).global_position + Vector3.UP
		if in_cone.call(tp):
			var near := 1.0 - clampf(origin.distance_to(tp) / rng, 0.0, 1.0)
			t.react_to_hit(lerpf(4.0, 14.0, near), fwd, true)
	# my own player (each machine moves only itself)
	var me := get_tree().current_scene.get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as CharacterBody3D
	if me and me != _player and not me.get("sync_dead") and in_cone.call(me.global_position + Vector3.UP):
		me.motor.knock(me, fwd * push + Vector3.UP * 3.5)
	# blow out burning things (the gust's owner reports it once)
	if mine:
		for r in get_tree().get_nodes_in_group("reactive"):
			if r.burning and not r.always_burning and in_cone.call(r.center()):
				r.receive_hit(WorldRules.make_hit(0.0, "blunt", "frost", fwd), false)


const GUST_TIME := 0.45        ## swing length: the whoosh and the wind effect last this long


## Wind Waker-style gust: a few swirling wind rings rushing out to the gust's range, plus
## streaks of air. Purely visual, every peer.
func _gust_fx(origin: Vector3, fwd: Vector3, rng: float) -> void:
	var root := _world_root()
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.8, 1.0, 0.9, 0.55)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 4:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.55
		t.outer_radius = 0.62
		t.rings = 24
		t.ring_segments = 3
		t.material = mat
		ring.mesh = t
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		# torus lies flat (XZ); stand it up so it faces along the gust
		ring.global_transform = Transform3D(basis * Basis(Vector3.RIGHT, PI * 0.5), origin + fwd * 0.8)
		ring.scale = Vector3.ONE * 0.4
		var delay := k * 0.06
		var tw := ring.create_tween()
		tw.tween_interval(delay)
		tw.set_parallel(true)
		tw.tween_property(ring, "global_position", origin + fwd * rng, GUST_TIME - delay).set_ease(Tween.EASE_OUT)
		tw.tween_property(ring, "scale", Vector3.ONE * (1.6 + k * 0.4), GUST_TIME - delay)
		tw.tween_property(ring, "rotation", ring.rotation + Vector3(0, 0, PI), GUST_TIME - delay)
		tw.chain().tween_callback(ring.queue_free)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.7
	p.amount = 36
	p.lifetime = GUST_TIME
	p.local_coords = false
	p.direction = Vector3(0, 0, -1)
	p.spread = rad_to_deg(atan(1.6 / rng)) * 2.0
	p.initial_velocity_min = rng / GUST_TIME * 0.8
	p.initial_velocity_max = rng / GUST_TIME * 1.05
	p.gravity = Vector3.ZERO
	p.damping_min = 4.0
	p.damping_max = 8.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.5)
	var pm := mat.duplicate() as StandardMaterial3D
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.albedo_color = Color(0.9, 1.0, 0.95, 0.5)
	q.material = pm
	p.mesh = q
	root.add_child(p)
	p.global_transform = Transform3D(basis, origin + fwd * 0.6)
	p.emitting = true
	get_tree().create_timer(GUST_TIME + 0.3).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- staff / rod aim
## Where the camera points (within range): ground for the staff, water surface or ground for the rod.
func _aim_point(s: Resource, tag: String) -> Dictionary:
	var out := { "ok": false, "pos": Vector3.ZERO, "water": false }
	if _player.camera_rig == null:
		return out
	var cam: Camera3D = _player.camera_rig.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var max_d: float = s.max_range + from.distance_to(_player.global_position)
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_d, 1)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	var ground_pos: Vector3 = hit.position if not hit.is_empty() else Vector3.INF
	# water surface along the ray (before any ground hit)
	var water_pos := Vector3.INF
	var stop_d := from.distance_to(ground_pos) if ground_pos != Vector3.INF else max_d
	var d := 0.5
	while d < stop_d:
		var p := from + dir * d
		var lvl: float = Water.level_at(p)
		if lvl > -INF and p.y <= lvl:
			water_pos = Vector3(p.x, lvl, p.z)
			break
		d += 0.5
	if tag == "rod" and water_pos != Vector3.INF and water_pos.distance_to(_player.global_position) <= s.max_range + 2.0:
		return { "ok": true, "pos": water_pos, "water": true }
	if ground_pos == Vector3.INF or ground_pos.distance_to(_player.global_position) > s.max_range + 2.0:
		return out
	if water_pos != Vector3.INF:
		return out                                   # staff can't raise sand from under water
	var n: Vector3 = hit.normal
	if n.y < 0.6:
		return out                                   # walls / steep slopes
	var base := ""
	var col: Object = hit.collider
	if col is Node and (col as Node).is_in_group("sand_pillars"):
		base = str((col as Node).name)               # raised on top of another pillar
	return { "ok": true, "pos": ground_pos, "water": false, "base": base }


func _update_ring(s: Resource, tag: String) -> void:
	var show: bool = aiming and (tag == "staff" or tag == "rod")
	if not show:
		if _ring:
			_ring.visible = false
		return
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.top_level = true
		var t := TorusMesh.new()
		t.inner_radius = 0.8
		t.outer_radius = 1.0
		t.rings = 24
		t.ring_segments = 4
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		t.material = _ring_mat
		_ring.mesh = t
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	var t2 := _aim_point(s, tag)
	if tag == "rod" and not (t2.ok and t2.water and rod_element() == "frost"):
		_ring.visible = false                        # rod: the ring only marks where ice would form
		return
	_ring.visible = true
	if t2.ok:
		_ring.global_position = t2.pos + Vector3.UP * 0.06
		_ring_mat.albedo_color = Color(0.5, 0.85, 1.0, 0.85) if t2.water else Color(1.0, 0.85, 0.4, 0.85)
	else:
		var cam: Camera3D = _player.camera_rig.camera
		_ring.global_position = cam.global_position - cam.global_basis.z * minf(s.max_range, 8.0)
		_ring_mat.albedo_color = Color(1.0, 0.3, 0.25, 0.6)


# ---------------------------------------------------------------- staff: channeling look (every peer)
## While the Sandspire Staff is aimed (LMB held): sand swirls up around the caster's feet, the
## staff head glows and pulses brighter the longer you channel. Driven by synced aiming, so
## everyone sees it.
var _chan: Node3D
var _chan_light: OmniLight3D
var _chan_t := 0.0


func update_visuals(delta: float) -> void:
	var on: bool = _eq.sync_drawn and _eq.sync_aiming and _eq.weapon_type() == "staff" and not _player.sync_dead
	if not on:
		_chan_t = 0.0
		if _chan:
			_chan.queue_free()
			_chan = null
			_chan_light = null
		return
	_chan_t += delta
	if _chan == null:
		_chan = Node3D.new()
		_chan.name = "StaffChannel"
		_player.add_child(_chan)
		var col := Color(1.0, 0.8, 0.45)
		_chan.add_child(_sand_swirl(col))
		_chan_light = OmniLight3D.new()
		_chan_light.light_color = col
		_chan_light.omni_range = 3.0
		_chan.add_child(_chan_light)
	var head: Vector3 = (_eq._weapon_vis.global_position if is_instance_valid(_eq._weapon_vis) else _player.global_position + Vector3.UP * 1.4) + Vector3.UP * 0.7
	_chan_light.global_position = head
	var ramp := clampf(_chan_t / 0.6, 0.0, 1.0)
	_chan_light.light_energy = ramp * (1.4 + 0.6 * sin(_chan_t * 12.0))


func _sand_swirl(col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.9
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.9
	p.emission_ring_inner_radius = 0.6
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.tangential_accel_min = 2.0                 # swirl around the caster
	p.tangential_accel_max = 3.0
	p.radial_accel_min = -0.8                    # and draw in toward them
	p.radial_accel_max = -0.4
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.r, col.g, col.b, 0.85)
	q.material = m
	p.mesh = q
	p.position = Vector3.UP * 0.1
	return p


# ---------------------------------------------------------------- staff: pillar
func _pillar_under_feet(s: Resource) -> void:
	var space := _player.get_world_3d().direct_space_state
	var from := _player.global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or Water.depth_at(hit.position) > 0.0:
		Audio.play("ui.error", -6.0)
		return
	var base := ""
	var col: Object = hit.collider
	if col is Node and (col as Node).is_in_group("sand_pillars"):
		base = str((col as Node).name)
	_raise_pillar(s, hit.position, base)


## Owner: while a pillar rises under me, ride its top (a moving block won't lift a
## CharacterBody that was standing on the ground beside it).
func _physics_process(delta: float) -> void:
	if _ride == null:
		return
	_ride_t -= delta
	if not is_instance_valid(_ride) or _ride_t <= 0.0:
		_ride = null
		return
	var top: float = _ride.global_position.y
	var p := _player.global_position
	var half: float = _ride.size * 0.5 + 0.3
	if absf(p.x - _ride.global_position.x) <= half and absf(p.z - _ride.global_position.z) <= half and p.y < top + 0.05:
		_player.global_position.y = top + 0.02
		_player.velocity.y = maxf(_player.velocity.y, 0.0)


func _raise_pillar(s: Resource, at: Vector3, base: String) -> void:
	_cd = s.cooldown
	_seq += 1
	var nm := "Pillar_%d_%d" % [multiplayer.get_unique_id(), _seq]
	_track("pillar", nm, s.max_pillars)
	if _eq._model:
		_eq._model.play_action(&"Spellcast_Shoot", 0.5)
	# On a ledge the footprint hangs over the drop: run the column down to the lowest ground
	# under its corners instead, so it reads as a pillar rising out of the cliff face.
	var half: float = s.pillar_size * 0.5
	var low := at.y
	var space := _player.get_world_3d().direct_space_state
	for off in [Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half), Vector2.ZERO]:
		var o: Vector2 = off
		var from := Vector3(at.x + o.x, at.y + 1.5, at.z + o.y)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 14.0, 1)
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		low = minf(low, (hit.position as Vector3).y if not hit.is_empty() else at.y - 12.0)
	low = maxf(low, at.y - 12.0)
	var top: float = at.y + s.pillar_height
	rpc_pillar.rpc(nm, Vector3(at.x, top, at.z), top - low, s.pillar_height, base)


@rpc("any_peer", "call_local", "reliable")
func rpc_pillar(nm: String, top: Vector3, total: float, rise: float, base: String) -> void:
	var s := stats()
	var p := PillarScript.new()
	p.name = nm
	p.height = total
	p.rise = rise
	p.rests_on = base
	if s:
		p.size = s.pillar_size
		p.rise_time = s.pillar_rise_time
		p.life = s.pillar_life
	p.position = top                              # set before _ready: it remembers where to rise to
	_world_root().add_child(p)
	# my own pillar coming up under me: ride it
	var me_sent := multiplayer.get_remote_sender_id() == 0 or multiplayer.get_remote_sender_id() == multiplayer.get_unique_id()
	if me_sent and _player.is_local():
		var pp := _player.global_position
		if absf(pp.x - top.x) <= p.size * 0.5 + 0.3 and absf(pp.z - top.z) <= p.size * 0.5 + 0.3:
			_ride = p
			_ride_t = p.rise_time + 0.3


# ---------------------------------------------------------------- rod: ice / frost
func _freeze(s: Resource, at: Vector3) -> void:
	_cd = s.cooldown * 0.6
	_seq += 1
	var nm := "Ice_%d_%d" % [multiplayer.get_unique_id(), _seq]
	_track("ice", nm, s.max_ice)
	if _eq._model:
		_eq._model.play_action(&"Spellcast_Shoot", 0.4)
	rpc_ice.rpc(nm, at)


@rpc("any_peer", "call_local", "reliable")
func rpc_ice(nm: String, at: Vector3) -> void:
	var s := stats()
	var ice := IceScript.new()
	ice.name = nm
	if s:
		ice.size = s.ice_size
		ice.life = s.ice_life
		ice.melt_near_fire = s.ice_melt_near_fire
	ice.position = at + Vector3.UP * 0.05
	_world_root().add_child(ice)


func _rod_blast(s: Resource, at: Vector3) -> void:
	_cd = s.cooldown
	if _eq._model:
		_eq._model.play_action(&"Spellcast_Shoot", 0.4)
	var element := rod_element()
	var origin := _player.global_position + Vector3.UP
	var to := at - origin
	var dir: Vector3 = Vector3(to.x, 0.0, to.z).normalized() if Vector3(to.x, 0.0, to.z).length() > 0.1 else -_player.model_root.global_basis.z
	rpc_cast_fx.rpc(origin, dir, element, float(s.frost_range))
	var space := _player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	var hits := {}
	for k in 4:
		var c: Vector3 = origin + dir * (1.5 + k * float(s.frost_range) / 4.0)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(), c)
		q.collision_mask = 3
		q.exclude = [_player.get_rid()]
		for r in space.intersect_shape(q, 16):
			var col: Object = r.collider
			if col == null or hits.has(col.get_instance_id()):
				continue
			if col.has_method("react_to_hit_info") or col.has_method("react_to_hit") or WorldRules.reactive_of(col) != null:
				hits[col.get_instance_id()] = true
				WorldRules.deliver_hit(col, WorldRules.make_hit(s.frost_damage, "magic", element, dir), false)


## Cast animation for the rod blast (every peer): a flash ring at the rod, then a wave of
## ice spikes / fire bursts / sparks running out along the ground in front of the caster.
@rpc("any_peer", "call_local", "unreliable")
func rpc_cast_fx(origin: Vector3, dir: Vector3, element: String, reach: float) -> void:
	var scene := get_tree().current_scene
	var col := WorldRules.element_color(element)
	var hand: Vector3 = _eq._hand_origin() if is_instance_valid(_eq) else origin
	_flash_ring(hand, col)
	FX.burst(hand, scene, col, 10, 0.05, 3.0)
	Audio.play_at("ice.hit" if element == "frost" else ("fire.ignite" if element == "fire" else "target.hit"), origin, 2.0, 0.6)
	for k in 4:
		var c: Vector3 = origin + dir * (1.5 + k * reach / 4.0)
		get_tree().create_timer(0.06 * k).timeout.connect(func() -> void: _wave_step(c, dir, element, col, k))


func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 4.0, 1)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p + Vector3.DOWN


func _wave_step(c: Vector3, dir: Vector3, element: String, col: Color, k: int) -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	var g := _ground(c)
	FX.burst(g + Vector3.UP * 0.3, scene, col, 8, 0.06, 2.5)
	match element:
		"fire":
			var f := FX.flames(0.9, k == 1)
			scene.add_child(f)
			f.global_position = g
			get_tree().create_timer(0.55).timeout.connect(f.queue_free)
		"shock":
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 4.0
			l.omni_range = 4.0
			scene.add_child(l)
			l.global_position = g + Vector3.UP * 0.6
			var tw := l.create_tween()
			tw.tween_property(l, "light_energy", 0.0, 0.25)
			tw.tween_callback(l.queue_free)
			_bolt(g + Vector3.UP * 2.2, g, col)
		_:
			var side := dir.cross(Vector3.UP).normalized()
			for n in 3:
				var off := side * (float(n) - 1.0) * 0.6 + dir * randf_range(-0.3, 0.3)
				_ice_spike(g + off, randf_range(0.6, 1.1) * (1.2 if n == 1 else 0.85))


## One ice spike: pops out of the ground, holds, sinks away.
func _ice_spike(at: Vector3, h: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.18
	cm.height = h
	cm.radial_segments = 4
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.93, 1.0, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	m.emission_enabled = true
	m.emission = Color(0.45, 0.8, 1.0)
	m.emission_energy_multiplier = 0.6
	cm.material = m
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = at + Vector3.UP * (h * 0.5 - 0.1)
	mi.rotation = Vector3(randf_range(-0.25, 0.25), randf() * TAU, randf_range(-0.25, 0.25))
	mi.scale = Vector3(1, 0.05, 1)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(mi, "scale", Vector3(0.6, 0.05, 0.6), 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## Shock: a jagged bolt dropping onto the spot.
func _bolt(from: Vector3, to: Vector3, col: Color) -> void:
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, m)
	for i in 7:
		var t := float(i) / 6.0
		var p := from.lerp(to, t)
		if i > 0 and i < 6:
			p += Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	get_tree().create_timer(0.15).timeout.connect(mi.queue_free)


## Expanding ring at the rod when it fires.
func _flash_ring(at: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.25
	t.outer_radius = 0.32
	t.rings = 16
	t.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = col
	t.material = m
	mi.mesh = t
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = at
	var fwd: Vector3 = -_player.model_root.global_basis.z
	mi.look_at(at + fwd, Vector3.UP if absf(fwd.y) < 0.99 else Vector3.FORWARD)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)     # torus faces forward
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 3.0, 0.25)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(mi.queue_free)


## Element of the rod's blast / orbs: frost, unless an infusion (Cinderpepper, Sparkthistle...) is on it.
func rod_element() -> String:
	var e: String = _eq.weapon_element()
	return e if e != "" else "frost"


func _shoot_orb(s: Resource) -> void:
	_cd = s.orb_cooldown
	var origin: Vector3 = _eq._hand_origin() + Vector3.UP * 0.25
	var aim: Vector3 = _eq._crosshair_point(origin, s.orb_range)
	var dir := (aim - origin).normalized()
	if dir.length() < 0.5:
		dir = -_player.model_root.global_basis.z
	var vel: Vector3 = dir * s.orb_speed
	var element := rod_element()
	if _eq._model:
		_eq._model.play_action(&"Spellcast_Shoot", 0.35)
	_make_orb(origin, vel, element, false)
	rpc_orb.rpc(origin, vel, element)


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_orb(origin: Vector3, vel: Vector3, element: String) -> void:
	_make_orb(origin, vel, element, true)


func _make_orb(origin: Vector3, vel: Vector3, element: String, cosmetic: bool) -> void:
	var s := stats()
	var o := OrbScript.new()
	o.name = "Orb"
	o.element = element
	o.cosmetic = cosmetic
	o.shooter_rid = _player.get_rid()
	if s:
		o.damage = s.orb_damage
		o.splash_radius = s.orb_splash
		o.lifetime = s.orb_range / maxf(s.orb_speed, 1.0)
	_eq._projectiles_root().add_child(o, true)
	o.launch(origin, vel)
	Audio.play_at("ice.hit" if element == "frost" else ("fire.ignite" if element == "fire" else "boomerang.throw"), origin, -6.0, 1.7)


# ---------------------------------------------------------------- trap
func _place_trap(s: Resource) -> void:
	_cd = 0.4
	var w: Resource = _eq.weapon()
	_eq.consume(w.ammo_item_id, 1)
	var at := _trap_spot()
	_seq += 1
	if _eq._model:
		_eq._model.play_action(&"Interact", 0.4)
	rpc_trap.rpc("Trap_%d_%d" % [multiplayer.get_unique_id(), _seq], at, str(_player.display_name))
	_eq.after_bomb_released()                          # last trap set: hands down


## Where a trap would land: just in front of your feet, dropped onto the ground.
func _trap_spot() -> Vector3:
	var fwd: Vector3 = -_player.model_root.global_basis.z
	var at := _player.global_position + fwd * 1.1
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 3.0, 1)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		at = hit.position
	return at


## Ghost trap + its trigger circle where it would go (owner only, while a trap is drawn).
var _trap_ghost: Node3D
var _trap_circle: MeshInstance3D


func _update_trap_preview(s: Resource, show: bool) -> void:
	if not show:
		if _trap_ghost:
			_trap_ghost.visible = false
			_trap_circle.visible = false
		return
	if _trap_ghost == null:
		_trap_ghost = AssetRegistry.instantiate("item.trap.snapjaw")
		_trap_ghost.top_level = true
		add_child(_trap_ghost)
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.albedo_color = Color(1.0, 0.85, 0.4, 0.4)
		for g in _trap_ghost.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).material_override = gm
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trap_circle = MeshInstance3D.new()
		_trap_circle.top_level = true
		var t := TorusMesh.new()
		t.inner_radius = (s.trap_radius if s else 0.65) - 0.05
		t.outer_radius = (s.trap_radius if s else 0.65) + 0.03
		t.rings = 24
		t.ring_segments = 3
		var cm := gm.duplicate() as StandardMaterial3D
		cm.albedo_color = Color(1.0, 0.45, 0.3, 0.7)
		t.material = cm
		_trap_circle.mesh = t
		_trap_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_trap_circle)
	var at := _trap_spot()
	_trap_ghost.visible = true
	_trap_circle.visible = true
	_trap_ghost.global_position = at
	_trap_ghost.rotation.y = _player.model_root.global_rotation.y
	_trap_circle.global_position = at + Vector3.UP * 0.04


@rpc("any_peer", "call_local", "reliable")
func rpc_trap(nm: String, at: Vector3, placer: String) -> void:
	var s: Resource = ItemDB.get_item("trap_snapjaw").stats
	var t := TrapScript.new()
	t.name = nm
	t.placer_peer = multiplayer.get_remote_sender_id() if multiplayer.get_remote_sender_id() != 0 else multiplayer.get_unique_id()
	t.placer_name = placer
	if s:
		t.arm_time = s.trap_arm_time
		t.damage = s.trap_damage
		t.root_time = s.trap_root_time
		t.radius = s.trap_radius
	t.position = at
	_world_root().add_child(t)


# ---------------------------------------------------------------- helpers
func _world_root() -> Node:
	var scene := get_tree().current_scene
	var r := scene.get_node_or_null("WorldTools")
	if r == null:
		r = Node3D.new()
		r.name = "WorldTools"
		scene.add_child(r)
	return r


## Keep at most `limit` of my pillars / ice at once: the oldest goes first.
func _track(kind: String, nm: String, limit: int) -> void:
	var list: Array = _mine[kind]
	list.append(nm)
	while list.size() > limit:
		rpc_expire.rpc(str(list.pop_front()))


@rpc("any_peer", "call_local", "reliable")
func rpc_expire(nm: String) -> void:
	var n := _world_root().get_node_or_null(nm)
	if n == null:
		return
	if n.has_method("crumble"):
		n.crumble()
	elif n.has_method("melt"):
		n.melt()
