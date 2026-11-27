extends Node
## Map fixes from the in-game bug reports (_reports/, Nov 27). Edits the Terrain3D and adds
## editable nodes to island.tscn, then saves both. Safe to re-run (replaces what it added).
##   * Mesas: fill the old V-notches (they were walk-up ramps for the removed mesa walls) into
##     solid flat tops with sheer sides, and put a Plateau (grapple posts + chest) on each.
##   * Bridges: flat landing pad at both ends, flush with the deck; no humps under the deck.
##   * Bridge 1 / north canyon: the canyon ramp ran right under the bridge end - filled in and
##     re-cut 12 m further west so the bridge lands on solid ground.
##   * Swim exits: gentle ramps out of the water where reports said "I can't get up here".
##   * Lone islet: a Plateau (posts + chest). River gorge: grapple posts on both banks.
## Run: Godot_console.exe --headless --path . res://tools/map/fix_map_reports.tscn

const PlateauScript := preload("res://scenes/props/world/plateau.gd")
const PostScript := preload("res://scenes/props/world/grapple_post.gd")
const ISLAND := "res://scenes/match/island.tscn"
const T3D := preload("res://systems/world/island_terrain3d.gd")

## [centre, search radius] of the notched mesas
var mesas := [[Vector2(203, 55), 17.0], [Vector2(55, 70), 13.0], [Vector2(85, 172), 16.0]]
## swim-exit ramps: [from (in the water), floor height there, to (up the bank), height there, half width]
var ramps := [
	[Vector2(-179, -93), -1.6, Vector2(-179, -102.5), 2.4, 2.4],     # west canyon mouth
	[Vector2(-123.5, 183.5), -1.5, Vector2(-125.5, 175.5), 1.5, 2.6], # beach bank (report 18:32)
]
var old_trench := Rect2(-84, -129, 12, 26)                 # x, z, w, d: canyon ramp under bridge 1
var new_trench := [Vector2(-91, -100.5), -1.2, Vector2(-91, -132.0), 13.6, 2.2]
var islet := Vector2(-128, 214)
var gorge_posts := [Vector2(-106, -84.0), Vector2(-104, -108.5)]

var island: Node3D
var terrain: Node
var data: Object
var path_id := 6


func _ready() -> void:
	island = (load(ISLAND) as PackedScene).instantiate()
	add_child(island)
	await get_tree().process_frame
	terrain = island.get_node("Terrain")
	data = terrain.get("t3d").data
	path_id = T3D.LAYERS.find("path")
	var spots := island.get_node("SecretSpots")
	for c in spots.get_children():
		if c.name.begins_with("MesaTop_") or c.name == "Islet":
			spots.remove_child(c)
			c.free()
	var old := island.get_node_or_null("GrapplePoints")
	if old:
		island.remove_child(old)
		old.free()

	# --- mesas
	for i in mesas.size():
		var res := _close_mesa(mesas[i][0], mesas[i][1])
		if res.is_empty():
			continue
		var pl := PlateauScript.new()
		pl.name = "MesaTop_%d" % i
		pl.radius = res.r
		pl.tier = "rare"
		pl.post_angle_deg = 30.0 + i * 40.0
		spots.add_child(pl)
		pl.owner = island
		pl.position = res.at
		print("[fix] mesa %d: top %.1f r %.1f at %s" % [i, res.at.y, res.r, res.at])
	# --- north canyon ramp moved off the bridge-1 landing
	_fill_trench(old_trench)
	_ramp(new_trench[0], new_trench[1], new_trench[2], new_trench[3], new_trench[4], 1.4, true)
	# --- swim exits
	for r in ramps:
		_ramp(r[0], r[1], r[2], r[3], r[4], 2.0, true)
	# --- bridge ends (after the trench work: bridge 1 lands where the trench was)
	for b in island.get_node("Bridges").get_children():
		var a: Vector3 = b.get_node("A").global_position
		var e: Vector3 = b.get_node("B").global_position
		_landing(a, e)
		_landing(e, a)
	data.update_maps()
	# --- islet plateau
	var top := _top_of(islet, 14.0, 2.5)
	if not top.is_empty():
		var pl := PlateauScript.new()
		pl.name = "Islet"
		pl.radius = top.r
		pl.tier = "rare"
		spots.add_child(pl)
		pl.owner = island
		pl.position = top.at
		print("[fix] islet top %.1f r %.1f at %s" % [top.at.y, top.r, top.at])
	# --- grapple posts across the gorge
	var gp := Node3D.new()
	gp.name = "GrapplePoints"
	island.add_child(gp)
	gp.owner = island
	for i in gorge_posts.size():
		var q: Vector2 = gorge_posts[i]
		var post := PostScript.new()
		post.name = "GorgePost_%d" % i
		gp.add_child(post)
		post.owner = island
		post.global_position = Vector3(q.x, terrain.height_at(q.x, q.y) - 0.05, q.y)
	data.update_maps()
	var t3d: Node = terrain.get("t3d")
	t3d.data.save_directory(t3d.data_directory)
	var out := PackedScene.new()
	out.pack(island)
	ResourceSaver.save(out, ISLAND)
	print("[fix] DONE")
	get_tree().quit()


func _h(x: float, z: float) -> float:
	return data.get_height(Vector3(x, 0, z))


func _seth(x: float, z: float, h: float) -> void:
	data.set_height(Vector3(x, 0, z), h)


## Fill notches/cuts in a mesa: mask = ground well above the surrounding base, morphological
## close (dilate + erode, 3 m) to swallow the V-cuts, flatten the mask to the top height.
func _close_mesa(c: Vector2, R: float) -> Dictionary:
	var ring: Array[float] = []
	for k in 32:
		var a := TAU * k / 32.0
		ring.append(_h(c.x + cos(a) * (R + 4.0), c.y + sin(a) * (R + 4.0)))
	ring.sort()
	var base: float = ring[ring.size() / 2]
	var hs: Array[float] = []
	var n := int(R) + 3
	for x in range(-n, n + 1):
		for z in range(-n, n + 1):
			if Vector2(x, z).length() <= R:
				hs.append(_h(c.x + x, c.y + z))
	hs.sort()
	var top: float = hs[int(hs.size() * 0.93)]
	if top - base < 4.0:
		return {}
	var thr := base + (top - base) * 0.4
	var mask := {}
	for x in range(-n, n + 1):
		for z in range(-n, n + 1):
			if Vector2(x, z).length() <= R and _h(c.x + x, c.y + z) > thr:
				mask[Vector2i(x, z)] = true
	var closed := _erode(_dilate(mask, 3), 3)
	var sum := Vector2.ZERO
	for k in closed:
		var p := Vector2(c.x + k.x, c.y + k.y)
		var cur := _h(p.x, p.y)
		var edge := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not closed.has(k + d):
				edge += 1
		var want := top - (0.6 if edge > 0 else 0.0)         # soften the very lip a touch
		if cur < want:
			_seth(p.x, p.y, want)
		data.set_control_blend(Vector3(p.x, 0, p.y), 1.0 if edge > 0 else 0.0)
		sum += p
	# pits just outside (old notch mouths dug below the plain): lift to the plain
	for x in range(-n - 2, n + 3):
		for z in range(-n - 2, n + 3):
			if closed.has(Vector2i(x, z)):
				continue
			var p := Vector2(c.x + x, c.y + z)
			var cur := _h(p.x, p.y)
			if cur < base - 0.8 and cur > 0.5:
				_seth(p.x, p.y, base - 0.2)
	var centre := sum / maxf(closed.size(), 1)
	var radius := sqrt(closed.size() / PI)
	return { "at": Vector3(centre.x, top, centre.y), "r": maxf(radius, 4.0) }


func _dilate(m: Dictionary, r: int) -> Dictionary:
	var out := {}
	for k in m:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if dx * dx + dz * dz <= r * r:
					out[k + Vector2i(dx, dz)] = true
	return out


func _erode(m: Dictionary, r: int) -> Dictionary:
	var out := {}
	for k in m:
		var keep := true
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if dx * dx + dz * dz <= r * r and not m.has(k + Vector2i(dx, dz)):
					keep = false
					break
			if not keep:
				break
		if keep:
			out[k] = true
	return out


## Fill a trench back up to the line between its two rims.
func _fill_trench(r: Rect2) -> void:
	for z in range(int(r.position.y), int(r.end.y) + 1):
		var hl := _h(r.position.x - 1.0, z)
		var hr := _h(r.end.x + 1.0, z)
		for x in range(int(r.position.x), int(r.end.x) + 1):
			var t := (x - r.position.x) / r.size.x
			var f := lerpf(hl, hr, t)
			if _h(x, z) < f:
				_seth(x, z, f)


## A corridor ramp from a (height ha) to b (height hb): floor set inside half_w, blended outside.
func _ramp(a: Vector2, ha: float, b: Vector2, hb: float, half_w: float, blend: float, paint: bool) -> void:
	var ab := b - a
	var L := ab.length()
	var dir := ab / L
	var right := Vector2(dir.y, -dir.x)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (half_w + blend + 1)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (half_w + blend + 1)
	for x in range(int(lo.x), int(hi.x) + 1):
		for z in range(int(lo.y), int(hi.y) + 1):
			var off := Vector2(x, z) - a
			var s := off.dot(dir)
			var lat := absf(off.dot(right))
			if s < -1.0 or s > L + 2.0 or lat > half_w + blend:
				continue
			var t := clampf(s / L, 0.0, 1.0)
			var floor_h := lerpf(ha, hb, t)
			var w := 1.0 - smoothstep(half_w, half_w + blend, lat)
			if s > L:                                       # fade out past the top
				w *= 1.0 - (s - L) / 2.0
			if s < 0.0:
				w *= 1.0 + s
			var cur := _h(x, z)
			_seth(x, z, lerpf(cur, floor_h, w))
			if paint and lat < half_w and floor_h > 0.2:
				data.set_control_base_id(Vector3(x, 0, z), path_id)
				data.set_control_blend(Vector3(x, 0, z), 0.0)


## Flat landing at bridge end `e` (the other end is `o`): flush with the deck, then blending back
## into the ground over 6 m; the ground under the last metres of deck is cut below it.
func _landing(e: Vector3, o: Vector3) -> void:
	var dir := Vector2(e.x - o.x, e.z - o.z).normalized()     # pointing off the bridge
	var right := Vector2(dir.y, -dir.x)
	var deck := e.y - 0.06
	var c := Vector2(e.x, e.z)
	for x in range(int(c.x - 12), int(c.x + 13)):
		for z in range(int(c.y - 12), int(c.y + 13)):
			var off := Vector2(x, z) - c
			var s := off.dot(dir)
			var lat := absf(off.dot(right))
			if s < -4.0 or s > 8.0 or lat > 5.0:
				continue
			var cur := _h(x, z)
			if s < 0.0:                                      # under the deck: never poke through
				if lat < 2.6 and cur > deck - 0.25 + s * 0.15:
					_seth(x, z, deck - 0.25 + s * 0.15)
				continue
			var w := (1.0 - smoothstep(2.6, 5.0, lat)) * (1.0 - smoothstep(2.0, 8.0, s))
			_seth(x, z, lerpf(cur, deck, w))
			if lat < 2.2 and s < 5.0:
				data.set_control_base_id(Vector3(x, 0, z), path_id)
				data.set_control_blend(Vector3(x, 0, z), 0.0)


## Flat-ish top of an islet / hill near p: centroid + radius of ground above min_h.
func _top_of(p: Vector2, R: float, min_h: float) -> Dictionary:
	var sum := Vector2.ZERO
	var n := 0
	var hsum := 0.0
	for x in range(int(p.x - R), int(p.x + R) + 1):
		for z in range(int(p.y - R), int(p.y + R) + 1):
			var h := _h(x, z)
			if h > min_h and Vector2(x, z).distance_to(p) <= R:
				sum += Vector2(x, z)
				hsum += h
				n += 1
	if n < 10:
		return {}
	var cc := sum / n
	return { "at": Vector3(cc.x, _h(cc.x, cc.y), cc.y), "r": maxf(sqrt(n / PI), 4.0) }
