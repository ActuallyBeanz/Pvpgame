extends StaticBody3D
## Practice target (training dummy / archery target). Optional lock-on point for focus
## (group "lock_targets"), and a springy wobble + straw puff when something hits it.
## Local scenery: every peer runs the same reaction from its own projectile copies,
## so no networking is needed for the cosmetic part.

signal was_hit(damage: float, total_hits: int)

const FX := preload("res://systems/components/element_fx.gd")

@export var lockable := true
@export var lock_height := 1.15            ## lock point above the base (chest)
@export var head_height := 1.4             ## hits above this (from the base) count as headshots
@export var wobble_per_damage := 0.04      ## radians of kick per point of damage
@export var max_kick := 0.6
@export var wobble_stiffness := 70.0
@export var wobble_damping := 7.0
@export var puff_color := Color(0.95, 0.8, 0.4)
@export var show_damage_numbers := true
@export var burn_show_time := 1.6          ## fire hits: flames flicker on it this long (visual only)

var total_damage := 0.0
var _flames: Node3D
var _burn_left := 0.0

var hits := 0
var _tilt := Vector2.ZERO                  ## x = pitch, y = roll (radians)
var _tilt_vel := Vector2.ZERO

@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group("no_climb")
	if lockable:
		add_to_group("lock_targets")


## "head" or "body" for a hit at this world point (arrows multiply headshots).
func hit_zone(p: Vector3) -> String:
	return "head" if p.y - global_position.y >= head_height else "body"


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * lock_height


func is_lockable() -> bool:
	return lockable


## Hit with tags (WorldRules.make_hit). Damage numbers show on the attacker's screen.
func react_to_hit_info(hit: Dictionary, cosmetic: bool) -> void:
	var dmg := float(hit.get("damage", 0.0))
	var element := str(hit.get("element", ""))
	react_to_hit(maxf(dmg, 4.0), hit.get("dir", Vector3.FORWARD), cosmetic)
	if element == "fire":
		_burn_left = burn_show_time
		if _flames == null:
			_flames = FX.flames(0.8, true)
			add_child(_flames)
			_flames.position = Vector3.UP * lock_height * 0.8
	if not cosmetic:
		total_damage += dmg
		if show_damage_numbers and dmg > 0.0:
			var c := WorldRules.element_color(element) if element != "" else Color(1, 1, 1)
			FX.damage_number(get_lock_point() + Vector3.UP * 0.5, get_tree().current_scene, dmg, c)


## Called by arrows / boomerangs on every peer. cosmetic = remote copy (no gameplay).
func react_to_hit(damage: float, dir: Vector3, cosmetic: bool) -> void:
	hits += 1
	var d := global_basis.inverse() * dir
	var kick := minf(maxf(damage, 4.0) * wobble_per_damage, max_kick) * wobble_stiffness * 0.15
	_tilt_vel += Vector2(d.z, -d.x).normalized() * kick
	_puff()
	Audio.play_at("target.hit", get_lock_point(), clampf(damage / 10.0 - 4.0, -6.0, 2.0))
	if not cosmetic:
		was_hit.emit(damage, hits)


func _process(delta: float) -> void:
	if _flames:
		_burn_left -= delta
		if _burn_left <= 0.0:
			_flames.queue_free()
			_flames = null


func _physics_process(delta: float) -> void:
	if _tilt == Vector2.ZERO and _tilt_vel == Vector2.ZERO:
		return
	var acc := -_tilt * wobble_stiffness - _tilt_vel * wobble_damping
	_tilt_vel += acc * delta
	_tilt += _tilt_vel * delta
	if _tilt.length() < 0.001 and _tilt_vel.length() < 0.01:
		_tilt = Vector2.ZERO
		_tilt_vel = Vector2.ZERO
	visual.rotation = Vector3(_tilt.x, visual.rotation.y, _tilt.y)


func _puff() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := BoxMesh.new()
	m.size = Vector3(0.05, 0.015, 0.05)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = puff_color
	m.material = mat
	p.mesh = m
	add_child(p)
	p.position = Vector3.UP * lock_height
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
