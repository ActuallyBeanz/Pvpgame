@tool
extends Node3D
## High plateau marker: the plateau itself is TERRAIN (raised with sheer cliffs by
## tools/map/build_secrets.gd - reshape it with the Terrain3D tools). This node sits on the top:
## it adds wooden grapple posts on the rim (Grappleclaw / Skytether latch onto them) and a
## good chest spot in the middle. Too tall to climb: get up with a grapple or two stacked
## Sandspire pillars.

@export var radius := 8.0:
	set(v):
		radius = v
		if is_inside_tree():
			_build()
@export var posts := 3:
	set(v):
		posts = v
		if is_inside_tree():
			_build()
@export var post_angle_deg := 20.0         ## turn the ring of posts
@export_enum("uncommon", "rare", "legendary") var tier := "rare"


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		if c.name.begins_with("_"):
			c.free()
	var ps := load("res://assets/models/env/grapple_post.glb") as PackedScene
	for i in posts:
		var a := deg_to_rad(post_angle_deg) + TAU * float(i) / float(maxi(posts, 1))
		var body := StaticBody3D.new()
		body.name = "_Post_%d" % i
		body.add_to_group("hook_targets")
		body.set_meta("material", "wood")
		body.add_child(ps.instantiate())
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.5, 2.6, 0.5)
		cs.shape = box
		cs.position.y = 1.3
		body.add_child(cs)
		add_child(body)
		body.position = Vector3(cos(a), 0, sin(a)) * (radius - 1.2)
		body.rotation.y = -a + PI * 0.5
	var spot := Marker3D.new()
	spot.name = "_ChestSpot"
	spot.add_to_group("secret_spots")
	spot.set_meta("tier", tier)
	add_child(spot)
