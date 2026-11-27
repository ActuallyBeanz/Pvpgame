extends Node
## Player statuses (Wet, Burning, Chilled, Frozen, Shocked, Dazzled, Confused, Revealed...).
## Everything about a status lives in data (res://data/status/): this node only runs the rules.
##   Owner: applies / times out statuses, element-on-status reactions, damage over time,
##          Wet from water, and publishes the list in Player.sync_statuses.
##   Every peer: shows the effects (drips, flames, frost, sparks, swirl, glow-through-walls).
## Lives under the Player as "Status".

const RULES := preload("res://data/status/status_rules.tres")
const FX := preload("res://systems/components/element_fx.gd")

var active: Dictionary = {}                ## owner: id -> { "left": sec, "total": sec, "strength": 0..1 }
var _player: CharacterBody3D
var _dot_t := 0.0
var _fire_t := 0.0
var _vfx: Dictionary = {}                  ## every peer: id -> Node3D effect
var _shown := ""                           ## last sync_statuses we built effects for
var _reveal_mat: StandardMaterial3D
var _screen: ColorRect                     ## owner: dazzle white-out


func _ready() -> void:
	_player = get_parent()


static func rules() -> Resource:
	return RULES


func def(id: String) -> Resource:
	return RULES.get_status(id)


# ---------------------------------------------------------------- queries (owner)
func has(id: String) -> bool:
	return active.has(id)


func time_left(id: String) -> float:
	return float(active[id].left) if active.has(id) else 0.0


func move_mult() -> float:
	var m := 1.0
	for id: String in active:
		var d := def(id)
		if d:
			m *= d.move_mult
	return m


func rooted() -> bool:
	return move_mult() <= 0.01


func stunned() -> bool:
	for id: String in active:
		var d := def(id)
		if d and d.stuns:
			return true
	return false


func controls_inverted() -> bool:
	for id: String in active:
		var d := def(id)
		if d and d.invert_controls:
			return true
	return false


## Sorted for the HUD: [{ id, name, color, left, total }]
func list() -> Array:
	var out := []
	for id: String in active:
		var d := def(id)
		if d:
			out.append({ "id": id, "name": d.display_name, "color": d.color,
				"left": float(active[id].left), "total": float(active[id].total) })
	return out


# ---------------------------------------------------------------- applying (owner)
## Give a status. duration < 0 = its default. strength 0..1 (dazzle uses it). Returns true if it took.
func apply(id: String, duration := -1.0, strength := 1.0) -> bool:
	if not _player.is_local() or _player.sync_dead:
		return false
	var d := def(id)
	if d == null:
		return false
	for b: String in d.blocked_by:
		if active.has(b):
			return false
	for r: String in d.removes:
		remove(r)
	var t: float = d.duration if duration < 0.0 else duration
	if t <= 0.0:
		return false
	if active.has(id):
		var cur: Dictionary = active[id]
		if d.refresh or t > float(cur.left):
			cur.left = t
			cur.total = t
		cur.strength = maxf(float(cur.strength), strength)
	else:
		active[id] = { "left": t, "total": t, "strength": strength }
	_publish()
	return true


func remove(id: String) -> void:
	if active.erase(id):
		_publish()


func clear() -> void:
	active.clear()
	_publish()


## A hit with this element / action is landing on me (owner, from Health). Runs the reactions,
## gives the element's status, and returns the damage to take.
func on_hit(element: String, action: String, damage: float, from_dir: Vector3) -> float:
	var tags := [element, action]
	var block := false
	for rx: Resource in RULES.reactions:
		if rx == null or not active.has(rx.status) or not tags.has(rx.element) or rx.element == "":
			continue
		damage = damage * rx.damage_mult + rx.bonus_damage
		if rx.consume_status:
			remove(rx.status)
		if rx.apply_status != "":
			apply(rx.apply_status, rx.apply_duration)
		block = block or rx.block_element_status
		if rx.popup != "":
			popup.rpc(rx.popup, rx.popup_color)
		print("[status] %s + %s -> x%.2f %s" % [rx.status, rx.element, rx.damage_mult, rx.popup])
	if element != "" and not block:
		var sid: String = RULES.element_status.get(element, "")
		if sid != "":
			var dur: float = RULES.element_duration.get(element, -1.0)
			var strength := 1.0
			if def(sid) and def(sid).screen_flash:
				strength = _facing_strength(-from_dir)
				dur = (def(sid).duration if dur < 0.0 else dur) * lerpf(0.4, 1.0, strength)
			apply(sid, dur, strength)
	return damage


## Flash: full strength when you look toward it, weak when it's behind you.
func _facing_strength(toward_source: Vector3) -> float:
	var cam: Camera3D = _player.camera_rig.camera if _player.camera_rig else null
	if cam == null or toward_source.length() < 0.01:
		return 1.0
	var look := -cam.global_basis.z
	return clampf(look.dot(toward_source.normalized()) * 0.5 + 0.5, 0.15, 1.0)


## Something bright went off at `at` (Glarepetal): dazzle me if I can see it.
func flash_from(at: Vector3, radius: float) -> void:
	if not _player.is_local() or _player.sync_dead:
		return
	var eye := _player.global_position + Vector3.UP * 1.5
	var d := eye.distance_to(at)
	if d > radius:
		return
	var q := PhysicsRayQueryParameters3D.create(eye, at, 1)
	if not _player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return                                       # behind a wall
	var s := _facing_strength(at - eye) * lerpf(1.0, 0.5, d / radius)
	var dd := def("dazzled")
	apply("dazzled", (dd.duration if dd else 1.6) * lerpf(0.4, 1.0, s), s)


# ---------------------------------------------------------------- per tick (owner)
func tick(delta: float) -> void:
	if _player.sync_dead:
		if not active.is_empty():
			clear()
		return
	# water makes you Wet (and keeps you Wet while you're in it)
	if _player.motor.in_water() or float(_player.motor.water_depth) > 0.25:   # swimming or wading
		apply("wet", RULES.wet_from_water)
	_fire_contact(delta)
	var expired := []
	for id: String in active:
		active[id].left = float(active[id].left) - delta
		if float(active[id].left) <= 0.0:
			expired.append(id)
	for id: String in expired:
		active.erase(id)
	if not expired.is_empty():
		_publish()
	# damage over time, in half-second ticks
	_dot_t += delta
	if _dot_t >= 0.5:
		_dot_t -= 0.5
		for id: String in active:
			var d := def(id)
			if d and d.dot_per_sec > 0.0:
				_player.health.take_damage(d.dot_per_sec * 0.5, Vector3.ZERO, "dot_" + d.dot_kind, "")
	_update_screen()


## Flames touching me (any fire zone: burning crates / trees / shacks, braziers, torches, the rod's
## burning field): contact damage every half second, and I catch fire. Wet steams off first.
func _fire_contact(delta: float) -> void:
	_fire_t -= delta
	if _fire_t > 0.0:
		return
	_fire_t = 0.5
	var w := _player.get_world_3d()
	var p := _player.global_position
	var touching := WorldRules.fire_zone_at(w, p + Vector3.UP * 0.3) or WorldRules.fire_zone_at(w, p + Vector3.UP * 1.1) \
		or WorldRules.fire_zone_at(w, p + Vector3.UP * 1.7)
	if not touching:
		return
	if active.has("wet"):
		remove("wet")
		popup.rpc("Sizzle", Color(0.85, 0.85, 0.85))
		_player.health.take_damage(RULES.fire_contact_dps * 0.25, Vector3.ZERO, "dot_fire", "")
		return
	_player.health.take_damage(RULES.fire_contact_dps * 0.5, Vector3.ZERO, "dot_fire", "")
	if RULES.fire_contact_status != "":
		apply(RULES.fire_contact_status)


func _publish() -> void:
	var ids := PackedStringArray(active.keys())
	ids.sort()
	_player.sync_statuses = ",".join(ids)


@rpc("any_peer", "call_local", "reliable")
func popup(text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 44
	l.outline_size = 10
	l.pixel_size = 0.004
	l.modulate = color
	get_tree().current_scene.add_child(l)
	l.global_position = _player.global_position + Vector3.UP * 2.3
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", l.global_position + Vector3.UP * 0.8, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


# ---------------------------------------------------------------- dazzle screen (owner)
func _update_screen() -> void:
	var a := 0.0
	for id: String in active:
		var d := def(id)
		if d and d.screen_flash:
			var e: Dictionary = active[id]
			a = maxf(a, float(e.strength) * clampf(float(e.left) / maxf(float(e.total), 0.01) * 1.6, 0.0, 1.0))
	if a <= 0.0 and _screen == null:
		return
	if _screen == null:
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		_screen = ColorRect.new()
		_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_screen)
	_screen.color = Color(1, 1, 0.94, a * 0.95)
	_screen.visible = a > 0.0


# ---------------------------------------------------------------- effects (every peer)
func _process(_delta: float) -> void:
	var now: String = _player.sync_statuses
	if now == _shown:
		return
	_shown = now
	var want := {}
	for id in now.split(",", false):
		want[id] = true
	for id: String in _vfx.keys():
		if not want.has(id):
			_drop_vfx(id)
	for id: String in want:
		if not _vfx.has(id):
			_vfx[id] = _make_vfx(id)


func _drop_vfx(id: String) -> void:
	var n: Variant = _vfx.get(id)
	_vfx.erase(id)
	if n is Node and is_instance_valid(n):
		(n as Node).queue_free()
	if id == "revealed" or (def(id) and def(id).reveals):
		_set_reveal(false)


func _make_vfx(id: String) -> Node3D:
	var d := def(id)
	var root := Node3D.new()
	root.name = "Status_" + id
	_player.add_child(root)
	if d == null:
		return root
	if d.reveals:
		_set_reveal(true)
	match d.vfx:
		"flames":
			var f := FX.flames(0.7, false)
			root.add_child(f)
			f.position = Vector3.UP * 0.6
		"drip":
			root.add_child(_particles(d.color, 16, 0.6, Vector3(0, -6, 0), 0.35, 1.2))
		"frost":
			root.add_child(_particles(d.color, 18, 0.9, Vector3(0, -0.4, 0), 0.45, 0.8))
		"sparks":
			root.add_child(_particles(d.color, 22, 0.25, Vector3.ZERO, 0.4, 0.9, 3.0))
		"swirl":
			var p := _particles(d.color, 14, 0.8, Vector3(0, 0.3, 0), 0.35, 0.0)
			p.position = Vector3.UP * 2.0
			p.tangential_accel_min = 4.0
			p.tangential_accel_max = 5.0
			root.add_child(p)
		"glow":
			root.add_child(_particles(d.color, 10, 1.0, Vector3(0, 0.6, 0), 0.5, 0.9))
	return root


func _particles(col: Color, n: int, life: float, grav: Vector3, radius: float, y: float, speed := 0.3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.gravity = grav
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.5
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = col
	q.material = m
	p.mesh = q
	p.position = Vector3.UP * (y if y > 0.0 else 1.0)
	return p


## Revealed: a see-through-walls glow on the whole model (every peer sees it).
func _set_reveal(on: bool) -> void:
	if _reveal_mat == null:
		_reveal_mat = StandardMaterial3D.new()
		_reveal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_reveal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_reveal_mat.no_depth_test = true
		_reveal_mat.albedo_color = Color(1.0, 0.9, 0.5, 0.35)
		_reveal_mat.render_priority = 10
	for g in _player.model_root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		# a second pass on whatever the mesh draws with (doesn't fight the hit-flash overlay)
		var base: Material = (gi as MeshInstance3D).get_active_material(0) if gi is MeshInstance3D else null
		if base is BaseMaterial3D:
			if on:
				var copy := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
				copy.next_pass = _reveal_mat
				(gi as MeshInstance3D).set_surface_override_material(0, copy)
				gi.set_meta("_reveal_copy", true)
			elif gi.has_meta("_reveal_copy"):
				(gi as MeshInstance3D).set_surface_override_material(0, null)
				gi.remove_meta("_reveal_copy")
