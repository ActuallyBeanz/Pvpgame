extends Node
## Player health (OoT hearts: 1 heart = 10 hp). Lives under the Player as "Health".
## Each player's OWN machine applies damage to itself (same trust model as movement) and
## publishes Player.sync_health / sync_dead; attackers route hits here with rpc_hit.
## Sources: weapon hits (WorldRules hits, headshots already multiplied by the shooter),
## bombs, fall damage, drowning, lava. Roll i-frames and a raised shield (frontal) still work.
## Death drops your whole inventory and switches you to spectating; the test arena
## respawns you after a few seconds (scene property allow_respawn).

signal died(killer: String)
signal damaged(amount: float, kind: String)

const FX := preload("res://systems/components/element_fx.gd")
const Motor := preload("res://scenes/player/movement_motor.gd")

@export var max_health := 100.0
@export var hitstun_time := 0.3
@export var knockback := 4.5
@export var fall_safe_height := 7.0        ## falls shorter than this don't hurt
@export var fall_damage_per_m := 7.0
@export var drown_damage := 10.0           ## per second once your breath is gone
@export var lava_dps := 30.0
@export var respawn_delay := 4.0

var health := 100.0
var dead := false
var hitstun := 0.0
var root_left := 0.0                       ## snared (trap): can't move
var slow_left := 0.0                       ## frost: half speed
var spectate_index := 0
var _player: CharacterBody3D
var _air_peak := -INF
var _was_on_floor := true
var _lava_t := 0.0
var _respawn_t := 0.0
var _last_attacker := ""
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
var _shown_dead := false


func _ready() -> void:
	_player = get_parent()
	health = max_health
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1, 0.15, 0.1, 0.0)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(1, 0.1, 0.05)
	if _player.is_local():
		_player.sync_health = health
		_player.motor.drowning.connect(func() -> void: take_damage(drown_damage, Vector3.ZERO, "drowning", ""))


# ---------------------------------------------------------------- hits (entry points)
## A WorldRules hit landed on this player (called on the attacker's peer).
func receive_hit(hit: Dictionary, cosmetic: bool) -> void:
	_flash()
	if cosmetic:
		return
	var by := multiplayer.get_unique_id()
	if _player.is_local():
		_apply_hit(float(hit.get("damage", 0.0)), hit.get("dir", Vector3.ZERO), str(hit.get("element", "")), by)
	else:
		rpc_hit.rpc_id(_player.get_multiplayer_authority(), float(hit.get("damage", 0.0)), hit.get("dir", Vector3.ZERO), str(hit.get("element", "")))


@rpc("any_peer", "call_remote", "reliable")
func rpc_hit(damage: float, dir: Vector3, element: String) -> void:
	if _player.is_local():
		_apply_hit(damage, dir, element, multiplayer.get_remote_sender_id())


func _apply_hit(damage: float, dir: Vector3, element: String, by_peer: int) -> void:
	if dead or _player.is_invulnerable():
		return
	var attacker := _name_of(by_peer)
	if by_peer != multiplayer.get_unique_id():
		_last_attacker = attacker
	take_damage(damage, dir, "fire" if element == "fire" else "hit", attacker)
	if element == "frost":
		slow_left = maxf(slow_left, 2.5)
		FX.burst(_player.global_position + Vector3.UP, get_tree().current_scene, Color(0.75, 0.95, 1.0), 10, 0.06, 2.5)


## Owner only: lose health, get knocked back / stunned, maybe die.
func take_damage(amount: float, dir: Vector3, kind: String, source: String) -> void:
	if dead or amount <= 0.0 or not _player.is_local():
		return
	health = maxf(0.0, health - amount)
	_player.sync_health = health
	damaged.emit(amount, kind)
	_flash()
	if kind == "hit" or kind == "fire":
		hitstun = hitstun_time
		var push := Vector3(dir.x, 0.0, dir.z)
		if push.length() > 0.05 and not _player.motor.in_water():
			_player.motor.knock(_player, push.normalized() * knockback + Vector3.UP * 2.5)
		if _player.model_root.get_child_count() > 0 and _player.model_root.get_child(0).has_method("play_action"):
			_player.model_root.get_child(0).play_action(&"Hit_A", 0.3)
	Audio.play("target.hit", 0.0, 0.8)
	print("[health] -%.0f (%s) -> %.0f/%.0f" % [amount, kind, health, max_health])
	if health <= 0.0:
		_die(source if source != "" else (_last_attacker if kind != "fall" else "the fall"))


## Owner: held in place (trap).
func apply_root(t: float) -> void:
	root_left = maxf(root_left, t)
	_player.velocity = Vector3.ZERO


# ---------------------------------------------------------------- environment (owner, every physics tick)
func tick(delta: float) -> void:
	hitstun = maxf(0.0, hitstun - delta)
	root_left = maxf(0.0, root_left - delta)
	slow_left = maxf(0.0, slow_left - delta)
	if dead:
		_tick_dead(delta)
		return
	var on_floor := _player.is_on_floor()
	var y := _player.global_position.y
	var motor = _player.motor
	if motor.in_water() or motor.is_busy() or _player.equipment.hook.pulling():
		_air_peak = -INF                     # water / ledges / grapple: no fall damage
	elif not on_floor:
		_air_peak = maxf(_air_peak, y)
	if on_floor and not _was_on_floor and _air_peak > -INF:
		var drop := _air_peak - y
		if drop > fall_safe_height:
			take_damage((drop - fall_safe_height) * fall_damage_per_m, Vector3.ZERO, "fall", "")
		_air_peak = -INF
	if on_floor:
		_air_peak = -INF
	_was_on_floor = on_floor
	# lava
	if Water.kind_at(_player.global_position + Vector3.UP * 0.2) == "lava":
		_lava_t -= delta
		if _lava_t <= 0.0:
			_lava_t = 0.5
			take_damage(lava_dps * 0.5, Vector3.ZERO, "lava", "lava")
			FX.burst(_player.global_position + Vector3.UP, get_tree().current_scene, Color(1, 0.45, 0.1), 8, 0.06, 3.0)
	else:
		_lava_t = 0.0


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash_mat.albedo_color.a = 0.6 * clampf(_flash_t / 0.25, 0.0, 1.0)
		_flash_mat.emission_energy_multiplier = 1.5 * clampf(_flash_t / 0.25, 0.0, 1.0)
		if _flash_t <= 0.0:
			_set_overlay(null)
	# every peer: show / hide the body when its owner dies or respawns
	if _player.sync_dead != _shown_dead:
		_shown_dead = _player.sync_dead
		_player.model_root.visible = not _shown_dead
		_player.collision_layer = 0 if _shown_dead else 2
		var tag := _player.get_node_or_null("NameTag")
		if tag:
			tag.visible = not _shown_dead and not _player.is_local()
		if _shown_dead:
			FX.burst(_player.global_position + Vector3.UP, get_tree().current_scene, Color(0.9, 0.9, 1.0), 26, 0.1, 4.0)
			FX.smoke_puff(_player.global_position + Vector3.UP * 0.6, get_tree().current_scene, 1.4)


func _flash() -> void:
	_flash_t = 0.25
	_set_overlay(_flash_mat)


func _set_overlay(m: Material) -> void:
	for g in _player.model_root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).material_overlay = m


# ---------------------------------------------------------------- death / spectate / respawn
func _die(killer: String) -> void:
	if dead:
		return
	dead = true
	health = 0.0
	_player.sync_health = 0.0
	var eq = _player.equipment
	eq._unequip()
	for i in eq.inventory.size():
		if eq.inventory[i] != "":
			eq.drop_item(i, 0, true)
	_player.sync_dead = true
	_player.velocity = Vector3.ZERO
	_respawn_t = respawn_delay
	spectate_index = 0
	died.emit(killer)
	rpc_announce.rpc(_player.display_name, killer)


@rpc("any_peer", "call_local", "reliable")
func rpc_announce(victim: String, killer: String) -> void:
	var msg := "%s was defeated" % victim if killer == "" else "%s was defeated by %s" % [victim, killer]
	print("[match] " + msg)
	var hud := get_tree().current_scene.get_node_or_null("MatchHud")
	if hud and hud.has_method("show_feed"):
		hud.show_feed(msg)


func _tick_dead(delta: float) -> void:
	var allow: bool = bool(get_tree().current_scene.get("allow_respawn")) if "allow_respawn" in get_tree().current_scene else false
	if allow:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_respawn()
			return
	# spectate: the camera follows a living player (LMB = next)
	var alive := alive_others()
	if GameConfig.gameplay_input_enabled and Input.is_action_just_pressed("attack"):
		spectate_index += 1
	var rig = _player.camera_rig
	if rig:
		rig.follow(alive[spectate_index % alive.size()] if not alive.is_empty() else _player)


func _respawn() -> void:
	dead = false
	health = max_health
	_player.sync_health = health
	_player.sync_dead = false
	_player.global_position = _player.spawn_point
	_player.velocity = Vector3.ZERO
	_player.motor.reset(_player.motor.facing)
	_player.motor.breath = _player.motor.profile.breath_max
	_player.reset_physics_interpolation()
	if _player.camera_rig:
		_player.camera_rig.follow(_player)


func alive_others() -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("players"):
		if p != _player and not p.sync_dead:
			out.append(p)
	return out


func _name_of(peer: int) -> String:
	var p := get_tree().current_scene.get_node_or_null("Players/%d" % peer)
	return str(p.display_name) if p else ""
