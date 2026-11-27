extends Node
## Renders the island from a few viewpoints to res://_shots/*.png (git-ignored) and quits (visual checks).
## Run (NOT headless): Godot.exe --path . res://tools/map/screenshot.tscn --resolution 1600x900

const VIEWS := [
	["overview", Vector3(0, 260, 330), Vector3(0, 0, -20)],
	["wellspring", Vector3(40, 30, -10), Vector3(0, 6, -60)],
	["volcano", Vector3(90, 60, -120), Vector3(160, 20, -200)],
	["lava_close", Vector3(140, 40, -150), Vector3(150, 25, -185)],
	["lava_sea", Vector3(60, 40, -260), Vector3(110, 5, -230)],
	["bridge", Vector3(8, 16, 4), Vector3(23, 10, 7)],
	["bridge_deck", Vector3(21, 13.5, -10), Vector3(25, 11, 12)],
	["mesa_wall", Vector3(40, 22, 100), Vector3(66, 14, 76)],
	["forest", Vector3(-120, 25, 40), Vector3(-165, 10, 10)],
]


func _ready() -> void:
	var island: Node = load("res://scenes/match/island.tscn").instantiate()
	island.set("allow_respawn", true)
	add_child(island)
	var cam := Camera3D.new()
	cam.far = 3000.0
	add_child(cam)
	cam.current = true
	var dir := ProjectSettings.globalize_path("res://_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	for v in VIEWS:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for i in 30:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("%s.png" % v[0]))
		print("[shot] ", v[0])
	get_tree().quit()
