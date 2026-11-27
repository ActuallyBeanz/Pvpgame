extends Node3D
## Makes a prop react to hits and elements: wood burns and spreads fire, ice melts
## near heat and shatters to blunt hits, anything with hp breaks.
##
## Add as a child of a prop scene's root and set material_id (blank = the root's
## metadata "material"). Every collision body under the root is tagged so
## projectiles find this node through WorldRules.deliver_hit().
##
## Multiplayer: the host owns hp / heat / fire. Clients forward their real
## (non-cosmetic) hits to the host; the host pushes state to everyone with _sync.
## Props need the same node path on every peer (give them fixed names).

signal state_changed(hp: float, burning: bool)
signal destroyed
signal respawned

const FX := preload("res://systems/components/element_fx.gd")

@export var material_id := ""
@export var max_hp_override := 0.0           ## > 0 replaces the material's max_hp
@export var always_burning := false          ## brazier / campfire: permanent, never spreads
@export var fire_height := 0.6               ## flame position above the prop origin (m)
@export var fire_size := 1.0
@export var fire_zone_radius := 0.0          ## > 0: arrows flying through here catch fire
@export var sync_interval := 0.25            ## host -> clients while state is changing
@export var respawn_time := 0.0              ## > 0: comes back this many seconds after breaking (test area)

var mat: Resource
var max_hp := 0.0
var hp := 0.0
var heat := 0.0
var burning := false
var dead := false

var _root: Node3D
var _base_scale := Vector3.ONE
var _flames: Node3D
var _fire_loop: Node
var _overlay: StandardMaterial3D
var _sync_t := 0.0
var _spread_t := 0.0
var _dirty := false
var _broken := false


func _ready() -> void:
	_root = get_parent() as Node3D
	if material_id == "" and _root and _root.has_meta("material"):
		material_id = str(_root.get_meta("material"))
	mat = WorldRules.get_material(material_id)
	max_hp = max_hp_override if max_hp_override > 0.0 else (mat.max_hp if mat else 0.0)
	hp = max_hp
	_base_scale = _root.scale
	add_to_group("reactive")
	_tag_bodies(_root)
	_overlay = StandardMaterial3D.new()
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(0.05, 0.03, 0.02, 0.0)
	_overlay.emission_enabled = true
	_overlay.emission = Color(1.0, 0.35, 0.05)
	_overlay.emission_energy_multiplier = 0.0
	if fire_zone_radius > 0.0:
		_make_fire_zone()
	if always_burning:
		_set_burning_visual(true)
		burning = true


func center() -> Vector3:
	return _root.global_position + Vector3.UP * fire_height


func hp_ratio() -> float:
	return hp / max_hp if max_hp > 0.0 else 1.0


# ------------------------------------------------------------------ hits (all peers)
func receive_hit(hit: Dictionary, cosmetic: bool) -> void:
	if dead:
		return
	_hit_feedback(hit)
	if cosmetic:
		return
	if multiplayer.is_server():
		_apply_hit(hit)
	else:
		_srv_hit.rpc_id(1, hit)


@rpc("any_peer", "call_remote", "reliable")
func _srv_hit(hit: Dictionary) -> void:
	if multiplayer.is_server() and not dead:
		_apply_hit(hit)


func _hit_feedback(hit: Dictionary) -> void:
	if mat == null:
		return
	var pos := center()
	if mat.hit_sound != "":
		Audio.play_at(mat.hit_sound, pos)
	if max_hp > 0.0:
		FX.burst(pos, get_tree().current_scene, mat.debris_color, 6, 0.07, 2.5)
	if str(hit.get("element", "")) == "frost" and burning and not always_burning:
		FX.smoke_puff(pos, get_tree().current_scene, fire_size)


# ------------------------------------------------------------------ host simulation
func _apply_hit(hit: Dictionary) -> void:
	var tags := WorldRules.hit_tags(hit)
	var fx := WorldRules.effects(material_id, tags)
	if fx.has("extinguish") and burning and not always_burning:
		burning = false
		heat = 0.0
		_dirty = true
	if float(hit.get("heat", 0.0)) > 0.0:
		add_heat(float(hit.heat))
	if fx.has("ignite") and mat and mat.flammable:
		_ignite()
	_damage(float(hit.get("damage", 0.0)) * WorldRules.damage_mult(material_id, tags))
	_push()


## Gentle heat from a flaming weapon held close (no hit sound / debris). Call on any peer.
func warm(amount: float) -> void:
	if dead:
		return
	if multiplayer.is_server():
		add_heat(amount)
		_push()
	else:
		_srv_warm.rpc_id(1, amount)


@rpc("any_peer", "call_remote", "unreliable")
func _srv_warm(amount: float) -> void:
	if multiplayer.is_server() and not dead:
		add_heat(amount)
		_push()


## Host only. Fire spread, lit arrows and braziers all come through here.
func add_heat(amount: float) -> void:
	if dead or mat == null or always_burning:
		return
	if mat.melts_from_heat:
		_damage(amount * mat.melt_per_heat)
	if mat.flammable and not burning:
		heat += amount
		if heat >= mat.ignite_heat:
			_ignite()
	_dirty = true


func _ignite() -> void:
	if not burning:
		burning = true
		_dirty = true
		print("[reactive] %s caught fire" % _root.name)


func _damage(d: float) -> void:
	if max_hp <= 0.0 or d <= 0.0 or dead:
		return
	hp = maxf(0.0, hp - d)
	_dirty = true
	if hp <= 0.0:
		dead = true


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or mat == null:
		return
	if dead:
		_push()  # died from heat / burning since the last sync
		return
	if burning and not always_burning:
		_damage(mat.burn_dps * delta)
		_spread_t += delta
		if _spread_t >= 0.5:
			_spread(_spread_t)
			_spread_t = 0.0
	elif heat > 0.0:
		heat = maxf(0.0, heat - mat.cool_per_sec * delta)
	_sync_t += delta
	if _dirty and (_sync_t >= sync_interval or dead):
		_push()


func _spread(dt: float) -> void:
	var me := center()
	for r in get_tree().get_nodes_in_group("reactive"):
		if r == self or r.dead:
			continue
		var d: float = (r.center() as Vector3).distance_to(me)
		if d <= mat.spread_radius:
			r.add_heat(mat.spread_heat_per_sec * dt)


func _push() -> void:
	if not _dirty:
		return
	_dirty = false
	_sync_t = 0.0
	_sync.rpc(hp, burning, dead)


@rpc("authority", "call_local", "reliable")
func _sync(new_hp: float, new_burning: bool, new_dead: bool) -> void:
	hp = new_hp
	burning = new_burning
	if (_flames == null) == burning:
		if not burning and not new_dead:
			FX.smoke_puff(center(), get_tree().current_scene, fire_size)
			Audio.play_at("fire.extinguish", center())
		_set_burning_visual(burning)
	_update_damage_visual()
	state_changed.emit(hp, burning)
	if new_dead:
		_break()


# ------------------------------------------------------------------ visuals
func _set_burning_visual(on: bool) -> void:
	if on and _flames == null:
		_flames = FX.flames(fire_size)
		add_child(_flames)
		_flames.position = Vector3.UP * fire_height
		_fire_loop = Audio.attach_loop("fire.loop", _flames)
		if not always_burning:
			Audio.play_at("fire.ignite", center())
	elif not on and _flames:
		_flames.queue_free()
		_flames = null
		_fire_loop = null


func _update_damage_visual() -> void:
	if mat == null:
		return
	var r := hp_ratio()
	if mat.flammable:
		_overlay.albedo_color.a = clampf((1.0 - r) * 0.85, 0.0, 0.85) if (burning or r < 1.0) else 0.0
		_overlay.emission_energy_multiplier = 0.6 * (1.0 - r) if burning else 0.0
		_apply_overlay(_overlay.albedo_color.a > 0.01)
	if mat.melts_from_heat and _root:
		var s := lerpf(0.35, 1.0, r)
		_root.scale = Vector3(_base_scale.x * lerpf(0.6, 1.0, r), _base_scale.y * s, _base_scale.z * lerpf(0.6, 1.0, r))


func _apply_overlay(on: bool) -> void:
	for m in _root.find_children("*", "GeometryInstance3D", true, false):
		if m.get_parent() == _flames or (_flames and _flames.is_ancestor_of(m)):
			continue
		(m as GeometryInstance3D).material_overlay = _overlay if on else null


func _break() -> void:
	if _broken:
		return
	_broken = true
	dead = true
	var pos := center()
	var scene := get_tree().current_scene
	if mat:
		match mat.break_style:
			"shatter":
				FX.burst(pos, scene, mat.debris_color, 28, 0.16, 6.0)
			"crumble":
				FX.burst(pos, scene, mat.debris_color, 24, 0.2, 3.0)
			_:
				FX.burst(pos, scene, mat.debris_color.darkened(0.4 if burning else 0.0), 22, 0.14, 4.5)
		if burning:
			FX.smoke_puff(pos, scene, fire_size * 1.5)
		if mat.break_sound != "":
			Audio.play_at(mat.break_sound, pos)
	print("[reactive] %s destroyed" % _root.name)
	destroyed.emit()
	if respawn_time <= 0.0:
		_root.queue_free()
		return
	_set_present(false)
	if multiplayer.is_server():
		get_tree().create_timer(respawn_time).timeout.connect(func() -> void:
			if is_inside_tree():
				_respawn.rpc())


@rpc("authority", "call_local", "reliable")
func _respawn() -> void:
	dead = false
	_broken = false
	burning = false
	heat = 0.0
	hp = max_hp
	_dirty = false
	_root.scale = _base_scale
	_set_burning_visual(always_burning)
	burning = always_burning
	_update_damage_visual()
	_apply_overlay(false)
	_set_present(true)
	FX.smoke_puff(center(), get_tree().current_scene, 0.6)
	print("[reactive] %s respawned" % _root.name)
	respawned.emit()


## Hide / show the prop and switch its collision off / on (used by respawning props).
func _set_present(on: bool) -> void:
	_root.visible = on
	for cs in _root.find_children("*", "CollisionShape3D", true, false):
		(cs as CollisionShape3D).set_deferred("disabled", not on)
	if not on and _flames:
		_flames.queue_free()
		_flames = null


func _tag_bodies(n: Node) -> void:
	if n is CollisionObject3D:
		n.set_meta("reactive", self)
	for c in n.get_children():
		if c != self:
			_tag_bodies(c)


func _make_fire_zone() -> void:
	var a := Area3D.new()
	a.name = "FireZone"
	a.collision_layer = WorldRules.FIRE_ZONE_LAYER
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = true
	a.set_meta("fire_zone", true)
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = fire_zone_radius
	cs.shape = sph
	a.add_child(cs)
	add_child(a)
	a.position = Vector3.UP * (fire_height + fire_zone_radius * 0.15)
