extends Node
## Places the island's secrets into island.tscn under "SecretSpots" (re-runnable; replaces them):
##   Caves    at the old stash spots: door faces downhill, back into the slope, ground flattened.
##            The bombable doorway is the only way in; a good chest waits inside.
##   Plateaus raised out of the terrain with sheer cliffs (too tall to climb): grapple posts on
##            the rim, a good chest on top. Reach them with a grapple or stacked Sandspire pillars.
## Edits the Terrain3D (flatten / raise) and saves it. Run:
##   Godot_console.exe --headless --path . res://tools/map/build_secrets.tscn

const CaveScript := preload("res://scenes/props/world/cave.gd")
const PlateauScript := preload("res://scenes/props/world/plateau.gd")
const ISLAND := "res://scenes/match/island.tscn"

@export var plateau_count := 6
@export var plateau_height := 7.5          ## above the highest ground under it (> ledge climb, = 2 pillars)
@export var plateau_radius := Vector2(7.0, 9.5)
@export var plateau_min_gap := 80.0
@export var legendary_plateaus := 2

var island: Node3D
var data: Object


func _ready() -> void:
	island = (load(ISLAND) as PackedScene).instantiate()
	var old := island.get_node_or_null("SecretSpots")
	if old:
		island.remove_child(old)
		old.free()
	add_child(island)
	await get_tree().process_frame
	data = island.get_node("Terrain").get("t3d").data
	var root := Node3D.new()
	root.name = "SecretSpots"
	island.add_child(root)
	root.owner = island
	var taken: Array[Vector2] = []
	# ---- caves at the stash spots
	for i in island.stash_spots.size():
		var sp: Vector3 = island.stash_spots[i]
		var c := Vector2(sp.x, sp.y)
		var dir := _downhill(c)
		var yaw := atan2(dir.x, dir.y)
		var base: float = island.ground(c.x, c.y)
		_flatten_rect(c, yaw, base, Rect2(-6.5, -5.5, 13.0, 15.5), 3.0)   # local x, z (door side = +z)
		var cave := CaveScript.new()
		cave.name = "Cave_%d" % i
		cave.style = _style(island.get_node("Terrain").biome_at(c.x, c.y))
		cave.tier = "legendary" if sp.z > 0.5 else "rare"
		root.add_child(cave)
		cave.owner = island
		cave.position = Vector3(c.x, base - 0.05, c.y)
		cave.rotation.y = yaw
		taken.append(c)
		print("[secrets] %s %s %s at %s facing %.0f deg" % [cave.name, cave.style, cave.tier, c, rad_to_deg(yaw)])
	# ---- plateaus
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var cands: Array[Vector2] = []
	for x in range(-200, 201, 12):
		for z in range(-200, 201, 12):
			var p := Vector2(x, z) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			if _plateau_ok(p, 10.0):
				cands.append(p)
	var made := 0
	while made < plateau_count and not cands.is_empty():
		var best := -1
		var best_d := -1.0
		for k in cands.size():
			var d := INF
			for t in taken:
				d = minf(d, cands[k].distance_to(t))
			for s: Vector3 in island.spawn_points:
				d = minf(d, cands[k].distance_to(Vector2(s.x, s.z)) * 1.5)
			if d > best_d:
				best_d = d
				best = k
		if best < 0 or best_d < plateau_min_gap * 0.6:
			break
		var p := cands[best]
		cands.remove_at(best)
		var r := rng.randf_range(plateau_radius.x, plateau_radius.y)
		var top := _raise_plateau(p, r, rng)
		var pl := PlateauScript.new()
		pl.name = "Plateau_%d" % made
		pl.radius = r
		pl.tier = "legendary" if made < legendary_plateaus else "rare"
		pl.post_angle_deg = rng.randf_range(0, 120)
		root.add_child(pl)
		pl.owner = island
		pl.position = Vector3(p.x, top, p.y)
		taken.append(p)
		print("[secrets] %s r%.1f top %.1f at %s (%s)" % [pl.name, r, top, p, pl.tier])
		made += 1
	data.update_maps()
	var t3d: Node = island.get_node("Terrain").get("t3d")
	t3d.data.save_directory(t3d.data_directory)
	var out := PackedScene.new()
	out.pack(island)
	ResourceSaver.save(out, ISLAND)
	print("[secrets] DONE: %d caves, %d plateaus" % [island.stash_spots.size(), made])
	get_tree().quit()


func _style(biome: String) -> String:
	match biome:
		"ash", "lava":
			return "basalt"
		"snow", "ice":
			return "snow"
		"sand", "mesa", "beach":
			return "sand"
	return "stone"


## Direction toward the lowest ground 9 m out (the door faces it; the back goes into the hill).
func _downhill(c: Vector2) -> Vector2:
	var best := Vector2.DOWN
	var bh := INF
	for k in 16:
		var a := TAU * k / 16.0
		var d := Vector2(sin(a), cos(a))
		var q := c + d * 9.0
		var h: float = island.ground(q.x, q.y)
		if Water.depth_at(Vector3(q.x, h + 0.3, q.y)) > 0.2:
			h += 50.0                                     # never face straight into water
		if h < bh:
			bh = h
			best = d
	return best


func _flatten_rect(c: Vector2, yaw: float, h: float, rect: Rect2, blend: float) -> void:
	var r := maxf(rect.size.x, rect.size.y) + blend + 2.0
	var fwd := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(fwd.y, -fwd.x)
	for x in range(int(c.x - r), int(c.x + r) + 1):
		for z in range(int(c.y - r), int(c.y + r) + 1):
			var off := Vector2(x, z) - c
			var lp := Vector2(off.dot(right), off.dot(fwd))
			var dx := maxf(rect.position.x - lp.x, lp.x - rect.end.x)
			var dz := maxf(rect.position.y - lp.y, lp.y - rect.end.y)
			var outside := maxf(maxf(dx, dz), 0.0)
			if outside > blend:
				continue
			var p := Vector3(x, 0, z)
			var cur: float = data.get_height(p)
			data.set_height(p, lerpf(h, cur, smoothstep(0.0, blend, outside)))


func _plateau_ok(p: Vector2, r: float) -> bool:
	if not island._inland(p, r + 12.0) or island._in_landmark(p, r + 10.0) or island._dist_to_paths(p) < r + 10.0:
		return false
	var b: String = island.get_node("Terrain").biome_at(p.x, p.y)
	if b in ["lava", "plaza", "path", "bed", "beach", "ice"]:
		return false
	if island.get_node("Terrain").slope_deg(p.x, p.y) > 18.0:
		return false
	for s: Vector3 in island.spawn_points:
		if p.distance_to(Vector2(s.x, s.z)) < 35.0:
			return false
	return island.ground(p.x, p.y) > 2.0


## Raise a flat top with sheer cliffs (a wobbly round edge). Returns the top height.
func _raise_plateau(c: Vector2, r: float, rng: RandomNumberGenerator) -> float:
	var hi := -INF
	for k in 24:
		var a := TAU * k / 24.0
		hi = maxf(hi, island.ground(c.x + cos(a) * r, c.y + sin(a) * r))
	hi = maxf(hi, island.ground(c.x, c.y))
	var top := hi + plateau_height
	var wob := []
	for k in 12:
		wob.append(rng.randf_range(-0.14, 0.14))
	var band := 1.6
	for x in range(int(c.x - r - band - 2), int(c.x + r + band + 3)):
		for z in range(int(c.y - r - band - 2), int(c.y + r + band + 3)):
			var off := Vector2(x, z) - c
			var a := fposmod(off.angle(), TAU) / TAU * 12.0
			var i0 := int(a) % 12
			var w: float = lerpf(wob[i0], wob[(i0 + 1) % 12], a - floor(a))
			var edge := r * (1.0 + w)
			var d := off.length()
			if d > edge + band:
				continue
			var p := Vector3(x, 0, z)
			var cur: float = data.get_height(p)
			var k := smoothstep(edge, edge + band, d)
			var h := lerpf(top + rng.randf_range(-0.08, 0.08), cur, k)
			data.set_height(p, maxf(h, cur))
			if d > edge - 1.0:
				data.set_control_blend(p, 1.0)            # cliff faces: rock
	return top
