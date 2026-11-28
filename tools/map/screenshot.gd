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

## `-- fixes` renders these instead (the Nov 27 bug-report spots)
const FIX_VIEWS := [
	["fix_mesaA", Vector3(178, 27, 36), Vector3(204, 14, 55)],
	["fix_mesaB", Vector3(33, 21, 50), Vector3(55, 12, 70)],
	["fix_mesaC", Vector3(62, 23, 156), Vector3(85, 13, 172)],
	["fix_islet", Vector3(-106, 13, 194), Vector3(-130, 3, 216)],
	["fix_bridge1", Vector3(-92, 19, -128), Vector3(-73, 9, -113)],
	["fix_trench", Vector3(-91, 9, -88), Vector3(-91, 5, -118)],
	["fix_bridge3", Vector3(-92, 10, -14), Vector3(-77, 3, -24)],
	["fix_bridge6", Vector3(-18, 11, 172), Vector3(-7, 6, 163)],
	["fix_gorge", Vector3(-122, 19, -96), Vector3(-105, 13, -96)],
	["fix_shore", Vector3(-134, 6, 192), Vector3(-125, 1, 178)],
	["fix_canyonW", Vector3(-179, 5, -82), Vector3(-179, 3, -104)],
]

## `-- fixes2`: batch 2 spots (+ every HiddenCave from outside and inside, + an underwater view)
const FIX2_VIEWS := [
	["f2_frozen", Vector3(-100, 18, -122), Vector3(-75, 10, -150)],
	["f2_crater", Vector3(145, 52, -178), Vector3(160, 39, -200)],
	["f2_lavaend", Vector3(186, 13, -104), Vector3(175, 5.5, -117)],
	["f2_lavaflow", Vector3(166, 30, -132), Vector3(155, 19, -145)],
	["f2_eastposts", Vector3(190, 20, -70), Vector3(175, 9, -93)],
	["f2_eastshore", Vector3(216, 6, -192), Vector3(203, 2, -205)],
	["f2_pondW", Vector3(-200, 11, 100), Vector3(-200, 5, 80)],
	["f2_bridge1", Vector3(-62, 17, -108), Vector3(-73, 9.5, -114)],
	["f2_ashrocks", Vector3(146, 32, -150), Vector3(155, 27, -165)],
	["f2_underwater", Vector3(-200, 3.6, 92), Vector3(-200, 3.4, 80)],
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
	var args := OS.get_cmdline_user_args()
	var fixes := "fixes" in args or "fixes2" in args
	var views := (FIX2_VIEWS if "fixes2" in args else FIX_VIEWS if fixes else VIEWS).duplicate()
	if "fixes2" in args:
		var uw := preload("res://scenes/player/underwater_fx.gd").new()
		uw.camera = cam
		add_child(uw)
	await get_tree().process_frame
	if "fixes2" in args:
		for c in island.get_node("SecretSpots").get_children():
			if c.name.begins_with("HiddenCave"):
				var n3 := c as Node3D
				var outv := n3.global_basis.z
				views.append([c.name + "_out", n3.global_position + outv * 11.0 + Vector3.UP * 3.5, n3.global_position + Vector3.UP * 1.5])
				views.append([c.name + "_in", n3.global_position - outv * 3.0 + Vector3.UP * 1.7, n3.global_position - outv * 15.0 + Vector3.UP * 0.8])
	var spots := island.get_node_or_null("SecretSpots")
	if spots and not fixes:
		for c in spots.get_children():
			var n3 := c as Node3D
			if c.name == "Cave_0" or c.name == "Cave_4":
				var fwd := n3.global_basis.z
				views.append([c.name, n3.global_position + fwd * 13.0 + Vector3.UP * 4.0, n3.global_position + Vector3.UP * 1.8])
			elif c.name == "Plateau_3" or c.name == "Plateau_4":
				views.append([c.name, n3.global_position + Vector3(22, -2, 18), n3.global_position + Vector3.DOWN * 3.0])
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for i in 30:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("%s.png" % v[0]))
		print("[shot] ", v[0])
	get_tree().quit()
