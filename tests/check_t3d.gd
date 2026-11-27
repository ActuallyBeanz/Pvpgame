extends Node
## Headless check that the Terrain3D extension loads in this Godot build.
func _ready() -> void:
	print("T3D class: ", ClassDB.class_exists("Terrain3D"))
	if ClassDB.class_exists("Terrain3D"):
		var t: Node = ClassDB.instantiate("Terrain3D")
		print("T3D version: ", t.get("version"))
		t.free()
	get_tree().quit()
