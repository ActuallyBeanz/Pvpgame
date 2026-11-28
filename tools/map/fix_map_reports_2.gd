extends Node
## Map fixes from the second batch of bug reports (Nov 27, 18:58-19:07). Re-runnable.
##   * grapple posts across the east river; ramps out of the water (east shore, west pond)
##   * frozen lake: ground flattened under a round ice sheet (was a square slab 2 m up in the air)
##   * bridge 1 landing smoothed (the old trench fill left a blocky step)
##   * lava pools sit in real basins (the flow-end pool was level with the ground = invisible)
## Run: Godot_console.exe --headless --path . res://tools/map/fix_map_reports_2.tscn

const PostScript := preload("res://scenes/props/world/grapple_post.gd")
const ISLAND := "res://scenes/match/island.tscn"
const T3D := preload("res://systems/world/island_terrain3d.gd")

var posts := { "EastRiverPost_0": Vector2(175, -82.5), "EastRiverPost_1": Vector2(174, -103.5) }
var ramps := [
	[Vector2(209.5, -199.0), -1.5, Vector2(199.5, -208.5), 5.6, 2.6],    # east sea shore (report 19:01)
	[Vector2(-200, 84.0), 3.6, Vector2(-200, 76.5), 7.7, 2.4],            # west pond (report 19:07)
]
var frozen := Vector4(-75, -150, 26, 10.45)       # x, z, radius, ground height under the ice
var bridge1_end := Vector2(-73.9, -113.7)

var island: Node3D
var data: Object
var path_id := 6


func _ready() -> void:
	island = (load(ISLAND) as PackedScene).instantiate()
	add_child(island)
	await get_tree().process_frame
	var terrain := island.get_node("Terrain")
	data = terrain.get("t3d").data
	path_id = T3D.LAYERS.find("path")
	var gp := island.get_node("GrapplePoints")
	for k in posts:
		var old := gp.get_node_or_null(k)
		if old:
			gp.remove_child(old)
			old.free()
		var q: Vector2 = posts[k]
		var post := PostScript.new()
		post.name = k
		gp.add_child(post)
		post.owner = island
		post.global_position = Vector3(q.x, _h(q.x, q.y) - 0.05, q.y)
	for r in ramps:
		_ramp(r[0], r[1], r[2], r[3], r[4], 2.0)
	_flatten_disc(Vector2(frozen.x, frozen.y), frozen.z + 1.0, frozen.w, 4.0)
	var lakes: Array[Vector4] = island.lakes
	lakes[0] = Vector4(frozen.x, frozen.y, frozen.z, frozen.w + 0.05)  # ice top just over the ground
	island.lakes = lakes
	_smooth(bridge1_end + Vector2(-3, -2), 11.0, 3)
	var b1 := island.get_node("Bridges/Bridge_1")
	_landing((b1.get_node("B") as Node3D).global_position, (b1.get_node("A") as Node3D).global_position)
	for p in island.get_node("Lava").get_children():
		if p.get("radius") != null:
			_basin(p as Node3D, float(p.get("radius")))
	data.update_maps()
	var t3d: Node = terrain.get("t3d")
	t3d.data.save_directory(t3d.data_directory)
	var out := PackedScene.new()
	out.pack(island)
	ResourceSaver.save(out, ISLAND)
	print("[fix2] DONE")
	get_tree().quit()


func _h(x: float, z: float) -> float:
	return data.get_height(Vector3(x, 0, z))


func _seth(x: float, z: float, h: float) -> void:
	data.set_height(Vector3(x, 0, z), h)


func _ramp(a: Vector2, ha: float, b: Vector2, hb: float, half_w: float, blend: float) -> void:
	var ab := b - a
	var L := ab.length()
	var dir := ab / L
	var right := Vector2(dir.y, -dir.x)
	for x in range(int(minf(a.x, b.x) - 8), int(maxf(a.x, b.x) + 9)):
		for z in range(int(minf(a.y, b.y) - 8), int(maxf(a.y, b.y) + 9)):
			var off := Vector2(x, z) - a
			var s := off.dot(dir)
			var lat := absf(off.dot(right))
			if s < -1.0 or s > L + 2.0 or lat > half_w + blend:
				continue
			var w := 1.0 - smoothstep(half_w, half_w + blend, lat)
			if s > L:
				w *= 1.0 - (s - L) / 2.0
			if s < 0.0:
				w *= 1.0 + s
			var fh := lerpf(ha, hb, clampf(s / L, 0.0, 1.0))
			_seth(x, z, lerpf(_h(x, z), fh, w))
			if lat < half_w and fh > 0.2:
				data.set_control_base_id(Vector3(x, 0, z), path_id)
				data.set_control_blend(Vector3(x, 0, z), 0.0)


func _flatten_disc(c: Vector2, r: float, h: float, blend: float) -> void:
	for x in range(int(c.x - r - blend - 1), int(c.x + r + blend + 2)):
		for z in range(int(c.y - r - blend - 1), int(c.y + r + blend + 2)):
			var d := Vector2(x, z).distance_to(c)
			if d > r + blend:
				continue
			var w := 1.0 - smoothstep(r, r + blend, d)
			_seth(x, z, lerpf(_h(x, z), h, w))


## Box-blur the heights in a disc (n passes), fading the effect out toward the edge.
func _smooth(c: Vector2, r: float, passes: int) -> void:
	for p in passes:
		var nh := {}
		for x in range(int(c.x - r), int(c.x + r) + 1):
			for z in range(int(c.y - r), int(c.y + r) + 1):
				var d := Vector2(x, z).distance_to(c)
				if d > r:
					continue
				var sum := 0.0
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						sum += _h(x + dx, z + dz)
				var w := 1.0 - smoothstep(r * 0.6, r, d)
				nh[Vector2i(x, z)] = lerpf(_h(x, z), sum / 9.0, w)
		for k: Vector2i in nh:
			_seth(k.x, k.y, nh[k])


func _landing(e: Vector3, o: Vector3) -> void:
	var dir := Vector2(e.x - o.x, e.z - o.z).normalized()
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
			if s < 0.0:
				if lat < 2.6 and cur > deck - 0.25 + s * 0.15:
					_seth(x, z, deck - 0.25 + s * 0.15)
				continue
			var w := (1.0 - smoothstep(2.6, 5.0, lat)) * (1.0 - smoothstep(2.0, 8.0, s))
			_seth(x, z, lerpf(cur, deck, w))


## A lava pool needs a hollow: deep middle, shore sloping up just past its (wobbly) edge, a lip.
func _basin(pool: Node3D, r: float) -> void:
	var c := Vector2(pool.global_position.x, pool.global_position.z)
	var y := pool.global_position.y
	for x in range(int(c.x - r * 1.3 - 4), int(c.x + r * 1.3 + 5)):
		for z in range(int(c.y - r * 1.3 - 4), int(c.y + r * 1.3 + 5)):
			var off := Vector2(x, z) - c
			var a := off.angle()
			var d := off.length() / (1.0 + 0.12 * sin(3.0 * a) + 0.07 * sin(5.0 * a + 1.3))   # wobbly shore
			var cur := _h(x, z)
			if d < r * 0.8:
				_seth(x, z, minf(cur, y - 0.9))
			elif d < r * 1.25:
				_seth(x, z, lerpf(y - 0.9, y + 0.3, (d - r * 0.8) / (r * 0.45)))
			elif d < r * 1.25 + 3.0:
				var t := (d - r * 1.25) / 3.0
				_seth(x, z, maxf(cur, lerpf(y + 0.3, cur, t)))
	print("[fix2] basin for %s r %.1f at %.1f" % [pool.name, r, y])
