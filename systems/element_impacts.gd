extends RefCounted
## What an element does to the WORLD where it lands (arrows, slingstones, rod blasts, orbs).
## Every peer runs this for its own copy of the projectile / blast, so each player's game
## checks only its OWN player for statuses (Wet, Confused, Dazzled, Revealed) - no extra
## networking. `owner_copy` = the shooter's copy: only it touches host-owned props.
## Add a new element: add a branch in impact() (and its colour / status in data).

const FX := preload("res://systems/components/element_fx.gd")
const Smoke := preload("res://scenes/props/fx/smoke_cloud.gd")
const LightOrb := preload("res://scenes/props/fx/light_orb.gd")
const HealPuddle := preload("res://scenes/props/fx/heal_puddle.gd")
const IceScript := preload("res://scenes/props/tools/ice_platform.gd")


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
		"flash", "sunburst":                       # Glarepetal: white-out for anyone looking
			var big := 1.5 if element == "sunburst" else 1.0     # Sunburst: bigger, and Reveals the dazzled
			FX.burst(at, scene, col, 30, 0.05, 7.0 * big)
			_flash_light(scene, at, col, 16.0 * big, 14.0 * size * big)
			Audio.play_at("target.hit", at, 6.0, 2.2)
			var me := local_player(tree)
			if me:
				me.status.flash_from(at, 11.0 * size * big)
				if element == "sunburst" and me.status.has("dazzled"):
					me.status.apply("revealed")
		"light":                                   # Lumenbell: a lasting light; reveals who's close
			var o := LightOrb.new()
			scene.add_child(o)
			o.global_position = at + Vector3.UP * 0.4
			_status_near(tree, at, 4.0 * size, "revealed")
		"water":                                   # Dewbloom: splash - Wet, puts fires out
			FX.burst(at, scene, col, 26, 0.06, 4.0)
			Audio.play_at("fire.extinguish", at, -2.0, 1.4)
			_status_near(tree, at, 2.5 * size, "wet")
			_douse(tree, at, 2.5 * size, owner_copy)
		# ---------------- brews (two plants mixed into a vial)
		"emberfog":                                # Cinderpepper + Smolderpuff: smoke that burns
			var c := Smoke.new()
			c.radius = 3.0 * size
			c.tint = Color(0.5, 0.38, 0.3)
			c.status_inside = "burning"
			c.damage_inside = 3.0
			scene.add_child(c)
			c.global_position = at
			FX.burst(at, scene, WorldRules.element_color("fire"), 16, 0.06, 3.0)
		"muddlehaze":                              # Muddlemoss + Smolderpuff: a lingering confusion cloud
			var c := Smoke.new()
			c.radius = 3.2 * size
			c.life = 8.0
			c.tint = Color(0.55, 0.42, 0.7)
			c.status_inside = "confused"
			scene.add_child(c)
			c.global_position = at
		"rimemist":                                # Frostcap + Dewbloom: Wet + Chilled, freezes water
			FX.burst(at, scene, col, 30, 0.06, 4.0)
			FX.smoke_puff(at + Vector3.UP * 0.3, scene, 1.6 * size)
			Audio.play_at("ice.hit", at, 2.0, 0.7)
			var me := local_player(tree)
			if me and (me as Node3D).global_position.distance_to(at) <= 3.5 * size:
				me.status.apply("wet")
				me.status.apply("chilled", 4.0)        # next frost hit = Frozen
			var lvl: float = Water.level_at(at + Vector3.UP * 0.5)
			if lvl > -INF and absf(lvl - at.y) < 1.0:
				var ice := IceScript.new()
				ice.name = "Rimemist_%d_%d" % [roundi(at.x * 10.0), roundi(at.z * 10.0)]
				ice.size = 4.0 * size
				ice.position = Vector3(at.x, lvl + 0.05, at.z)
				scene.add_child(ice)
		"stormdrop":                               # Sparkthistle + Dewbloom: soak, then a bolt from the sky
			FX.burst(at, scene, WorldRules.element_color("water"), 26, 0.06, 4.0)
			_status_near(tree, at, 3.0 * size, "wet")
			tree.create_timer(0.8).timeout.connect(func() -> void:
				if scene == null or not is_instance_valid(scene):
					return
				_bolt(scene, at + Vector3.UP * 9.0, at, col)
				_flash_light(scene, at, col, 6.0, 8.0)
				Audio.play_at("target.hit", at, 6.0, 0.5)
				_hit_local(tree, at, 3.0 * size, 10.0, "shock"))      # Wet + shock = ELECTROCUTED
		"chainspark":                              # Sparkthistle + Lumenbell: arcs to the 3 nearest players
			var hits := []
			for p in tree.get_nodes_in_group("players"):
				if not p.sync_dead and (p as Node3D).global_position.distance_to(at) <= 7.0 * size:
					hits.append(p)
			hits.sort_custom(func(a: Node3D, b: Node3D) -> bool:
				return a.global_position.distance_to(at) < b.global_position.distance_to(at))
			var from := at
			for i in mini(3, hits.size()):
				var to: Vector3 = (hits[i] as Node3D).global_position + Vector3.UP * 1.0
				_bolt(scene, from, to, col)
				from = to
				if hits[i].is_local():
					hits[i].health.receive_hit(WorldRules.make_hit(12.0, "magic", "shock", (to - at).normalized()), false)
			FX.burst(at, scene, col, 20, 0.05, 5.0)
			Audio.play_at("target.hit", at, 4.0, 1.6)
		"steamburst":                              # Cinderpepper + Frostcap: a big shove + puts fires out
			FX.smoke_puff(at + Vector3.UP * 0.5, scene, 2.6 * size)
			FX.burst(at, scene, Color(0.92, 0.92, 0.95), 30, 0.08, 7.0)
			Audio.play_at("fire.extinguish", at, 6.0, 0.6)
			_douse(tree, at, 3.0 * size, owner_copy)
			var me := local_player(tree)
			if me:
				var d: Vector3 = (me as Node3D).global_position - at
				if d.length() <= 5.0 * size:
					var flat := Vector3(d.x, 0.0, d.z)
					var push := (flat.normalized() if flat.length() > 0.2 else Vector3.FORWARD) * 9.0 + Vector3.UP * 6.0
					me.motor.knock(me, push * clampf(1.2 - d.length() / (5.0 * size), 0.4, 1.0))
					for s in ["burning", "chilled", "frozen"]:
						me.status.remove(s)
		"mendingdew":                              # Dewbloom + Lumenbell: a healing puddle
			var h := HealPuddle.new()
			h.radius = 2.5 * size
			scene.add_child(h)
			h.global_position = at
			Audio.play_at("item.get", at, -2.0, 0.9)
		"muddle":                                  # Muddlemoss: spores - Confused
			FX.burst(at, scene, col, 22, 0.07, 2.0)
			FX.smoke_puff(at + Vector3.UP * 0.3, scene, 0.8)
			_status_near(tree, at, 2.5 * size, "confused")


static func _flash_light(scene: Node, at: Vector3, col: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	scene.add_child(l)
	l.global_position = at + Vector3.UP * 0.5
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


static func _bolt(scene: Node, from: Vector3, to: Vector3, col: Color) -> void:
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, m)
	for i in 8:
		var t := float(i) / 7.0
		var p := from.lerp(to, t)
		if i > 0 and i < 7:
			p += Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3))
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)
	scene.get_tree().create_timer(0.18).timeout.connect(mi.queue_free)


## Put out fires: rod burn fields (every peer) and burning props (shooter's copy -> host).
static func _douse(tree: SceneTree, at: Vector3, r: float, owner_copy: bool) -> void:
	var scene := tree.current_scene
	for f in tree.get_nodes_in_group("burn_fields"):
		if (f as Node3D).global_position.distance_to(at) <= r + 1.5:
			FX.smoke_puff((f as Node3D).global_position + Vector3.UP * 0.4, scene, 1.2)
			f.queue_free()
	if owner_copy:
		for rx in tree.get_nodes_in_group("reactive"):
			if rx.burning and not rx.always_burning and (rx.center() as Vector3).distance_to(at) <= r + 1.0:
				rx.receive_hit(WorldRules.make_hit(0.0, "splash", "water", Vector3.DOWN), false)


## My own player takes an element hit if they're within r (runs the status reactions).
static func _hit_local(tree: SceneTree, at: Vector3, r: float, dmg: float, element: String) -> void:
	var me := local_player(tree)
	if me and (me as Node3D).global_position.distance_to(at) <= r + 0.5:
		var dir: Vector3 = ((me as Node3D).global_position - at).normalized()
		me.health.receive_hit(WorldRules.make_hit(dmg, "magic", element, dir), false)


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
