extends AnimatableBody3D
## Sandspire Staff pillar: rises out of the ground (carrying whoever stands on it), stays for a
## while, then crumbles. Spawned on every peer by Tools.rpc_pillar (same name everywhere).

const FX := preload("res://systems/components/element_fx.gd")

var height := 4.0
var size := 1.8
var rise_time := 0.45
var life := 14.0
var _base := Vector3.ZERO
var _crumbling := false


func _ready() -> void:
	add_to_group("sand_pillars")
	set_meta("material", "stone")
	sync_to_physics = true
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, height, size)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.72, 0.48)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position.y = -height * 0.5
	add_child(mi)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(size * 1.1, 0.25, size * 1.1)
	top.mesh = tm
	var tmat := mat.duplicate() as StandardMaterial3D
	tmat.albedo_color = Color(0.93, 0.8, 0.56)
	top.material_override = tmat
	top.position.y = -0.12
	add_child(top)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, height, size)
	cs.shape = box
	cs.position.y = -height * 0.5
	add_child(cs)
	_base = global_position
	global_position = _base - Vector3.UP * height          # starts buried, top flush with the ground
	var tw := create_tween()
	tw.tween_property(self, "global_position", _base, rise_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	FX.burst(_base, get_tree().current_scene, Color(0.9, 0.78, 0.5), 18, 0.12, 4.0)
	Audio.play_at("wood.break", _base, 0.0, 0.5)
	get_tree().create_timer(life).timeout.connect(crumble)


func crumble() -> void:
	if _crumbling or not is_inside_tree():
		return
	_crumbling = true
	FX.burst(global_position + Vector3.DOWN * height * 0.5, get_tree().current_scene, Color(0.86, 0.72, 0.48), 26, 0.14, 3.0)
	FX.smoke_puff(global_position, get_tree().current_scene, 1.4)
	var tw := create_tween()
	tw.tween_property(self, "global_position", _base - Vector3.UP * height, 0.6)
	tw.tween_callback(queue_free)
