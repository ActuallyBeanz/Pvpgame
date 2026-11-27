@tool
extends Node3D
## Secret cave: a rock outcrop whose ONLY way in is a bombable doorway (bombs / hammer). Inside:
## glowing crystals and a good chest (spawned by the match at the "ChestSpot" marker, so its loot
## changes each match). Drop one in the editor, turn it so the door (+Z) faces open ground and
## sink it so the floor meets the terrain (tools/map/build_secrets.gd flattens the ground for you).
## The door is a CrackedWall named "Door" (fixed name: its break syncs by node path).

const CrackedWall := preload("res://scenes/props/world/cracked_wall.gd")
const GLOW := { "stone": Color(0.47, 0.86, 1.0), "sand": Color(1.0, 0.78, 0.35),
	"basalt": Color(1.0, 0.43, 0.2), "snow": Color(0.67, 0.9, 1.0) }

@export_enum("stone", "sand", "basalt", "snow") var style := "stone":
	set(v):
		style = v
		if is_inside_tree():
			_build()
@export_enum("uncommon", "rare", "legendary") var tier := "rare"

var _shell: Node3D


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		if c.name.begins_with("_"):
			c.free()
	_shell = (load("res://assets/models/env/cave_%s.glb" % style) as PackedScene).instantiate()
	_shell.name = "_Shell"
	add_child(_shell)
	var body := StaticBody3D.new()
	body.name = "_Rock"
	body.set_meta("material", "stone")
	add_child(body)
	for mi in _shell.find_children("*", "MeshInstance3D", true, false):
		var cs := CollisionShape3D.new()
		cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
		cs.transform = (mi as Node3D).transform
		body.add_child(cs)
	var light := OmniLight3D.new()
	light.name = "_Glow"
	light.light_color = GLOW.get(style, Color.WHITE)
	light.light_energy = 1.6
	light.omni_range = 7.5
	add_child(light)
	light.position = Vector3(0, 1.8, 0.5)
	if Engine.is_editor_hint():
		for part in ["wall_frame_", "wall_fill_"]:                # preview of the door
			var p := (load("res://assets/models/env/%s%s.glb" % [part, style]) as PackedScene).instantiate() as Node3D
			p.name = "_Door" + part
			add_child(p)
			p.position = Vector3(0, 0, 3.5)
	else:
		var door := CrackedWall.new()
		door.name = "Door"
		door.style = style
		add_child(door)
		door.position = Vector3(0, 0, 3.5)
	var spot := Marker3D.new()
	spot.name = "_ChestSpot"
	spot.add_to_group("secret_spots")
	spot.set_meta("tier", tier)
	add_child(spot)
	spot.position = Vector3(0, 0, -0.6)
	spot.rotation.y = 0.0                                        # chest faces the door
