extends Node
## World tools, driven by Equipment when one is the drawn weapon (ItemDef.action_tag):
##   "fan"   Galeleaf Fan (Wind Waker Deku Leaf): LMB = gust (shoves players + bombs, blows out
##           fires); hold Jump while falling = glide (limited, refills on landing)
##   "staff" Sandspire Staff: hold LMB = aim (ring shows the spot), release = sand pillar
##   "rod"   Rimecaller Rod: hold LMB = aim; release on water = ice platform (bridges),
##           on land = frost blast (damage + slows players)
##   "trap"  Snapjaw Trap: LMB = set one at your feet (the item is its own ammo)
## The owner decides; the world objects are spawned on every peer by call_local RPCs.

const PillarScript := preload("res://scenes/props/tools/sand_pillar.gd")
const IceScript := preload("res://scenes/props/tools/ice_platform.gd")
const TrapScript := preload("res://scenes/props/tools/snap_trap.gd")
const FX := preload("res://systems/components/element_fx.gd")

var aiming := false
var glide_left := 0.0
var gliding := false
var _eq: Node
var _player: CharacterBody3D
var _cd := 0.0
var _seq := 0
var _mine: Dictionary = { "pillar": [], "ice": [] }    ## my spawned node names, oldest first
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D


func setup(equipment: Node, player: CharacterBody3D) -> void:
	_eq = equipment
	_player = player


func stats() -> Resource:
	var s: Resource = _eq.stats()
	return s if s and "gust_range" in s else null


func stop() -> void:
	aiming = false
	if _ring:
		_ring.visible = false


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
			if pressed and can_use:
				_gust(s)
		"trap":
			if pressed and can_use and _eq.ammo_count() > 0:
				_place_trap(s)
		"staff", "rod":
			if held and can_use:
				aiming = true
			elif aiming and not held:
				aiming = false
				if can_use:
					var t := _aim_point(s, tag)
					if t.ok:
						if tag == "staff":
							_raise_pillar(s, t.pos)
						elif t.water:
							_freeze(s, t.pos)
						else:
							_frost_blast(s, t.pos)
					else:
						Audio.play("ui.error", -6.0)
			elif not can_use:
				aiming = false
	_eq.sync_aiming = aiming or gliding
	if _player.camera_rig:
		_player.camera_rig.set_aim(aiming, s)
	_update_ring(s, tag)


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
		_eq._model.play_action(&"1H_Melee_Attack_Slice_Horizontal", 0.4)
	rpc_gust.rpc(_player.global_position + Vector3.UP, fwd)


@rpc("any_peer", "call_local", "reliable")
func rpc_gust(origin: Vector3, fwd: Vector3) -> void:
	var s := stats()
	var rng: float = s.gust_range if s else 10.0
	var half := deg_to_rad((s.gust_angle_deg if s else 45.0) * 0.5)
	var push: float = s.gust_push if s else 11.0
	var mine := multiplayer.get_remote_sender_id() == 0 or multiplayer.get_remote_sender_id() == multiplayer.get_unique_id()
	Audio.play_at("boomerang.spin", origin, 2.0, 0.6)
	for k in 10:
		FX.burst(origin + fwd * (1.0 + k * rng / 10.0), get_tree().current_scene, Color(0.85, 1.0, 0.9, 0.7), 2, 0.05, 3.0)
	var in_cone := func(p: Vector3) -> bool:
		var to := p - origin
		var flat := Vector3(to.x, 0.0, to.z)
		return flat.length() <= rng and flat.length() > 0.2 and fwd.angle_to(flat.normalized()) <= half
	# bombs: every peer pushes its own copies
	for b in get_tree().get_nodes_in_group("bombs"):
		if not b.exploded and in_cone.call((b as Node3D).global_position):
			b.velocity += fwd * push * 0.8 + Vector3.UP * 3.0
			b._rest = false
	# my own player (each machine moves only itself)
	var me := get_tree().current_scene.get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as CharacterBody3D
	if me and me != _player and not me.get("sync_dead") and in_cone.call(me.global_position + Vector3.UP):
		me.motor.reset(me.motor.facing)
		me.velocity = fwd * push + Vector3.UP * 3.5
	# blow out burning things (the gust's owner reports it once)
	if mine:
		for r in get_tree().get_nodes_in_group("reactive"):
			if r.burning and not r.always_burning and in_cone.call(r.center()):
				r.receive_hit(WorldRules.make_hit(0.0, "blunt", "frost", fwd), false)


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
	return { "ok": true, "pos": ground_pos, "water": false }


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
	_ring.visible = true
	if t2.ok:
		_ring.global_position = t2.pos + Vector3.UP * 0.06
		_ring_mat.albedo_color = Color(0.5, 0.85, 1.0, 0.85) if t2.water else Color(1.0, 0.85, 0.4, 0.85)
	else:
		var cam: Camera3D = _player.camera_rig.camera
		_ring.global_position = cam.global_position - cam.global_basis.z * minf(s.max_range, 8.0)
		_ring_mat.albedo_color = Color(1.0, 0.3, 0.25, 0.6)


# ---------------------------------------------------------------- staff: pillar
func _raise_pillar(s: Resource, at: Vector3) -> void:
	_cd = s.cooldown
	_seq += 1
	var nm := "Pillar_%d_%d" % [multiplayer.get_unique_id(), _seq]
	_track("pillar", nm, s.max_pillars)
	if _eq._model:
		_eq._model.play_action(&"Spellcast_Shoot", 0.5)
	rpc_pillar.rpc(nm, at)


@rpc("any_peer", "call_local", "reliable")
func rpc_pillar(nm: String, at: Vector3) -> void:
	var s := stats()
	var p := PillarScript.new()
	p.name = nm
	if s:
		p.height = s.pillar_height
		p.size = s.pillar_size
		p.rise_time = s.pillar_rise_time
		p.life = s.pillar_life
	_world_root().add_child(p)
	p.global_position = at + Vector3.UP * p.height


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
	_world_root().add_child(ice)
	ice.global_position = at + Vector3.UP * 0.05


func _frost_blast(s: Resource, at: Vector3) -> void:
	_cd = s.cooldown
	if _eq._model:
		_eq._model.play_action(&"Spellcast_Shoot", 0.4)
	var origin := _player.global_position + Vector3.UP
	var to := at - origin
	var dir: Vector3 = Vector3(to.x, 0.0, to.z).normalized() if Vector3(to.x, 0.0, to.z).length() > 0.1 else -_player.model_root.global_basis.z
	var space := _player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	var hits := {}
	for k in 4:
		var c: Vector3 = origin + dir * (1.5 + k * float(s.frost_range) / 4.0)
		FX.burst(c, get_tree().current_scene, Color(0.75, 0.95, 1.0), 6, 0.06, 2.5)
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
				WorldRules.deliver_hit(col, WorldRules.make_hit(s.frost_damage, "blunt", "frost", dir), false)
	Audio.play_at("ice.hit", origin, 2.0, 0.6)


# ---------------------------------------------------------------- trap
func _place_trap(s: Resource) -> void:
	_cd = 0.4
	var w: Resource = _eq.weapon()
	_eq.consume(w.ammo_item_id, 1)
	var fwd: Vector3 = -_player.model_root.global_basis.z
	var at := _player.global_position + fwd * 1.1
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 3.0, 1)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		at = hit.position
	_seq += 1
	if _eq._model:
		_eq._model.play_action(&"Interact", 0.4)
	rpc_trap.rpc("Trap_%d_%d" % [multiplayer.get_unique_id(), _seq], at, str(_player.display_name))
	_eq.after_bomb_released()                          # last trap set: hands down


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
	_world_root().add_child(t)
	t.global_position = at


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
