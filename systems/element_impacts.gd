extends RefCounted
## What an element does to the WORLD where it lands (arrows, slingstones, rod blasts, orbs).
## Every peer runs this for its own copy of the projectile / blast, so each player's game
## checks only its OWN player for statuses (Wet, Confused, Dazzled, Revealed) - no extra
## networking. `owner_copy` = the shooter's copy: only it touches host-owned props.
## Add a new element: add a branch in impact() (and its colour / status in data).

const FX := preload("res://systems/components/element_fx.gd")
const Smoke := preload("res://scenes/props/fx/smoke_cloud.gd")
const LightOrb := preload("res://scenes/props/fx/light_orb.gd")


static func impact(tree: SceneTree, element: String, at: Vector3, size: float, owner_copy: bool) -> void:
	if tree == null or tree.current_scene == null:
		return
	var scene := tree.current_scene
	var col := WorldRules.element_color(element)
	match element:
		"smoke":                                   # Smolderpuff: a cloud you can't see or lock on through
			var c := Smoke.new()
			c.radius = 3.0 * size
			scene.add_child(c)
			c.global_position = at
		"flash":                                   # Glarepetal: white-out for anyone looking
			FX.burst(at, scene, col, 30, 0.05, 7.0)
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 16.0
			l.omni_range = 14.0 * size
			scene.add_child(l)
			l.global_position = at + Vector3.UP * 0.5
			var tw := l.create_tween()
			tw.tween_property(l, "light_energy", 0.0, 0.5)
			tw.tween_callback(l.queue_free)
			Audio.play_at("target.hit", at, 6.0, 2.2)
			var me := local_player(tree)
			if me:
				me.status.flash_from(at, 11.0 * size)
		"light":                                   # Lumenbell: a lasting light; reveals who's close
			var o := LightOrb.new()
			scene.add_child(o)
			o.global_position = at + Vector3.UP * 0.4
			_status_near(tree, at, 4.0 * size, "revealed")
		"water":                                   # Dewbloom: splash - Wet, puts fires out
			FX.burst(at, scene, col, 26, 0.06, 4.0)
			Audio.play_at("fire.extinguish", at, -2.0, 1.4)
			_status_near(tree, at, 2.5 * size, "wet")
			var r := 2.5 * size
			for f in tree.get_nodes_in_group("burn_fields"):
				if (f as Node3D).global_position.distance_to(at) <= r + 1.5:
					FX.smoke_puff((f as Node3D).global_position + Vector3.UP * 0.4, scene, 1.2)
					f.queue_free()
			if owner_copy:
				for rx in tree.get_nodes_in_group("reactive"):
					if rx.burning and not rx.always_burning and (rx.center() as Vector3).distance_to(at) <= r + 1.0:
						rx.receive_hit(WorldRules.make_hit(0.0, "splash", "water", Vector3.DOWN), false)
		"muddle":                                  # Muddlemoss: spores - Confused
			FX.burst(at, scene, col, 22, 0.07, 2.0)
			FX.smoke_puff(at + Vector3.UP * 0.3, scene, 0.8)
			_status_near(tree, at, 2.5 * size, "confused")


static func local_player(tree: SceneTree) -> Node:
	for p in tree.get_nodes_in_group("players"):
		if p.is_local() and not p.sync_dead and p.get("status") != null:
			return p
	return null


static func _status_near(tree: SceneTree, at: Vector3, radius: float, id: String) -> void:
	var me := local_player(tree)
	if me and (me as Node3D).global_position.distance_to(at) <= radius + 0.5:
		me.status.apply(id)


## True if a smoke cloud sits between a and b (lock-on and aim checks).
static func smoke_blocks(tree: SceneTree, a: Vector3, b: Vector3) -> bool:
	for c in tree.get_nodes_in_group("smoke_clouds"):
		var p: Vector3 = (c as Node3D).global_position + Vector3.UP * 1.0
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if (a + ab * t).distance_to(p) < float(c.radius) * float(c.density()):
			return true
	return false
