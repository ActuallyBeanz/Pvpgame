extends StaticBody3D
## Makes a prop targetable. groups: "lock_targets" = focus (RMB) can lock it,
## "boomerang_targets" = the boomerang's multi-target aim can select it.

@export var lock_height := 1.4
@export var focus_lockable := false        ## also lockable with focus (RMB)
@export var boomerang_target := true


func _ready() -> void:
	if focus_lockable:
		add_to_group("lock_targets")
	if boomerang_target:
		add_to_group("boomerang_targets")


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * lock_height


func is_lockable() -> bool:
	return is_inside_tree() and visible
