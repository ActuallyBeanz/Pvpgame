extends StaticBody3D
## Rimecaller Rod ice: a slab frozen on the water surface (lay several for a bridge).
## Melts after a while, much sooner if a flame touches it. Same name on every peer.

const FX := preload("res://systems/components/element_fx.gd")

var size := 3.2
var life := 22.0
var melt_near_fire := 3.0
var _left := 0.0
var _mat: StandardMaterial3D
var _check := 0.0


func _ready() -> void:
	add_to_group("ice_platforms")
	set_meta("material", "ice")
	_left = life
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, 0.5, size)
	mi.mesh = bm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.75, 0.92, 1.0, 0.9)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.1
	_mat.metallic = 0.2
	_mat.emission_enabled = true
	_mat.emission = Color(0.4, 0.75, 1.0)
	_mat.emission_energy_multiplier = 0.25
	mi.material_override = _mat
	mi.position.y = -0.25
	add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.5, size)
	cs.shape = box
	cs.position.y = -0.25
	add_child(cs)
	scale = Vector3(0.2, 1, 0.2)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.25)
	FX.burst(global_position, get_tree().current_scene, Color(0.8, 0.95, 1.0), 16, 0.08, 3.5)
	Audio.play_at("ice.hit", global_position, 0.0, 0.8)


func _physics_process(delta: float) -> void:
	_left -= delta
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		if WorldRules.fire_zone_at(get_world_3d(), global_position + Vector3.UP * 0.4):
			_left = minf(_left, melt_near_fire)
	if _left < 2.0:
		_mat.albedo_color.a = 0.9 * maxf(_left / 2.0, 0.0)
	if _left <= 0.0:
		melt()


func melt() -> void:
	if not is_inside_tree():
		return
	FX.smoke_puff(global_position, get_tree().current_scene, 1.0)
	Audio.play_at("fire.extinguish", global_position, -6.0, 1.3)
	queue_free()
