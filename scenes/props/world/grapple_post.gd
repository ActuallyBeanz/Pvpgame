@tool
extends StaticBody3D
## A wooden grapple post (Grappleclaw / Skytether latch onto it). Drop one anywhere a gap or
## ledge needs a way across/up; with snap_to_ground it sits on the terrain under it.

@export var snap_to_ground := true
@export var terrain_path: NodePath = ^"../../Terrain"

const MODEL := preload("res://assets/models/env/grapple_post.glb")


func _ready() -> void:
	add_to_group("hook_targets")
	set_meta("material", "wood")
	for c in get_children():
		if c.name.begins_with("_"):
			c.free()
	var m := MODEL.instantiate()
	m.name = "_Model"
	add_child(m)
	var cs := CollisionShape3D.new()
	cs.name = "_Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 2.6, 0.5)
	cs.shape = box
	cs.position.y = 1.3
	add_child(cs)
	if snap_to_ground:
		var t := get_node_or_null(terrain_path)
		if t and t.has_method("height_at"):
			global_position.y = t.height_at(global_position.x, global_position.z) - 0.05
