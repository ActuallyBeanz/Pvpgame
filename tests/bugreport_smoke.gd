extends Node
## Writes a test bug report from a camera at a cracked wall on the island (no player).
func _ready() -> void:
	var island: Node = load("res://scenes/match/island.tscn").instantiate()
	get_tree().root.add_child.call_deferred(island)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = island
	var wall: Node3D = get_tree().get_nodes_in_group("cracked_walls")[0]
	var cam := Camera3D.new()
	island.add_child(cam)
	cam.current = true
	cam.global_position = wall.global_position + wall.global_basis.z * 7.0 + Vector3.UP * 2.5
	cam.look_at(wall.global_position + Vector3.UP * 1.5, Vector3.UP)
	await get_tree().process_frame
	var text: String = BugReporter._describe("smoke test: first cracked wall", "report_smoketest")
	var f := FileAccess.open(ProjectSettings.globalize_path("res://_reports/report_smoketest.md"), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("[smoke] wrote %d chars, wall %s at %s" % [text.length(), wall.name, wall.global_position])
	get_tree().quit()
