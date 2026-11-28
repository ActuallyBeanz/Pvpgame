@tool
extends Node3D
## Hidden cave: a tunnel into a cliff that opens into a crystal-lit room UNDER the terrain.
## The node sits on the floor at the mouth; +Z points out of the cliff. The Terrain3D has a hole
## punched at the mouth (tools/map/build_hidden_caves.gd does that, plus raising the hill if it's
## too thin to hold the room). door = "cracked": a bombable wall flush with the cliff (bombs /
## hammer); "open": just a dark opening (river caves - swim up and climb in).
## A good chest spawns at the back (ChestSpot), new loot every match.

const CrackedWall := preload("res://scenes/props/world/cracked_wall.gd")
const GLOW := { "stone": Color(0.47, 0.86, 1.0), "sand": Color(1.0, 0.78, 0.35),
	"basalt": Color(1.0, 0.43, 0.2), "snow": Color(0.67, 0.9, 1.0) }

@export_enum("stone", "sand", "basalt", "snow") var style := "stone":
	set(v):
		style = v
		if is_inside_tree():
			_build()
@export_enum("cracked", "open") var door := "cracked":
	set(v):
		door = v
		if is_inside_tree():
			_build()
@export_enum("uncommon", "rare", "legendary") var tier := "rare"
@export var room_light := 2.2
@export var terrain_path: NodePath = ^"../../Terrain"   ## to size the rock filling the recess above


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		if c.name.begins_with("_") or c.name == "Door":
			c.free()
	var shell := (load("res://assets/models/env/cave_den_%s.glb" % style) as PackedScene).instantiate()
	shell.name = "_Shell"
	add_child(shell)
	var body := StaticBody3D.new()
	body.name = "_Rock"
	body.set_meta("material", "stone")
	add_child(body)
	for mi in shell.find_children("*", "MeshInstance3D", true, false):
		var cs := CollisionShape3D.new()
		var sh := (mi as MeshInstance3D).mesh.create_trimesh_shape() as ConcavePolygonShape3D
		sh.backface_collision = true
		cs.shape = sh
		cs.transform = (mi as Node3D).transform
		body.add_child(cs)
	_build_chimney()
	var col: Color = GLOW.get(style, Color.WHITE)
	for p in [[Vector3(0, 2.8, -12.5), room_light, 11.0], [Vector3(0, 2.2, -5.0), room_light * 0.35, 5.0]]:
		var l := OmniLight3D.new()
		l.name = "_Glow"
		l.light_color = col
		l.light_energy = p[1]
		l.omni_range = p[2]
		l.shadow_enabled = false
		add_child(l)
		l.position = p[0]
	if door == "cracked":
		if Engine.is_editor_hint():
			for part in ["wall_frame_", "wall_fill_"]:
				var w := (load("res://assets/models/env/%s%s.glb" % [part, style]) as PackedScene).instantiate() as Node3D
				w.name = "_Door" + part
				add_child(w)
				w.position = Vector3(0, 0, 0.4)
		else:
			var d := CrackedWall.new()
			d.name = "Door"                                  # fixed name: its break syncs by path
			d.style = style
			add_child(d)
			d.position = Vector3(0, 0, 0.4)
	var spot := Marker3D.new()
	spot.name = "_ChestSpot"
	spot.add_to_group("secret_spots")
	spot.set_meta("tier", tier)
	add_child(spot)
	spot.position = Vector3(0, 0, -15.0)


## The builder carves a recess just above the mouth (a heightfield can't overhang); fill it with
## stacked rock up to the cliff top so the cliff reads as one face.
func _build_chimney() -> void:
	var t := get_node_or_null(terrain_path)
	if t == null or not t.has_method("height_at"):
		return
	var back := global_transform * Vector3(0, 0, -3.4)
	var top: float = t.height_at(back.x, back.z)
	var beside := -INF                                     # untouched ground either side of the recess
	for side in [-4.4, 4.4]:
		var q := global_transform * Vector3(side, 0, -1.4)
		beside = maxf(beside, t.height_at(q.x, q.z))
	top = minf(top, beside - 0.4)                       # just under the grass line
	var rise := top - global_position.y - 4.6
	if is_nan(rise) or rise < 0.5:
		return
	var ps := load("res://assets/models/env/cave_chimney_%s.glb" % style) as PackedScene
	var body := StaticBody3D.new()
	body.name = "_Chimney"
	body.set_meta("material", "stone")
	add_child(body)
	var y := 4.4
	var end := 4.6 + rise
	while y < end - 0.3:
		var h := minf(9.6, end - y + 0.2)                      # last piece trimmed to the cliff top
		var piece := ps.instantiate() as Node3D
		body.add_child(piece)
		piece.position = Vector3(0, y, -0.2)
		piece.scale = Vector3(1.0, h / 10.0, 1.0)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(7.4, h, 2.6)
		cs.shape = box
		cs.position = Vector3(0, y + h * 0.5, -1.6)
		body.add_child(cs)
		y += h
