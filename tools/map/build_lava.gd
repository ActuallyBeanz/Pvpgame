extends Node
## Places the volcano's lava (re-runnable; replaces the "Lava" node in island.tscn):
##   a LavaPool in the crater, LavaFlows traced downhill from the crater rim (steepest descent),
##   each flow carves its channel into the terrain, and ends in a pool where it stops on land
##   (or steams into the sea). Afterwards everything is plain nodes you can edit in Godot.
## Run: Godot_console.exe --headless --path . res://tools/map/build_lava.tscn

const LavaFlow := preload("res://systems/world/lava/lava_flow.gd")
const LavaPool := preload("res://systems/world/lava/lava_pool.gd")
const ISLAND := "res://scenes/match/island.tscn"

@export var crater := Vector2(160, -200)
@export var crater_radius := 12.0
@export var flow_count := 3
@export var start_angles := 12             ## candidates tried around the rim


func _ready() -> void:
	var ps: PackedScene = load(ISLAND)
	var island: Node3D = ps.instantiate()
	add_child(island)
	await get_tree().process_frame
	var terrain: Node = island.get_node("Terrain")
	var old := island.get_node_or_null("Lava")
	if old:
		island.remove_child(old)
		old.free()
	var root := Node3D.new()
	root.name = "Lava"
	island.add_child(root)
	root.owner = island
	# crater pool
	var floor_y: float = terrain.height_at(crater.x, crater.y)
	var pool := LavaPool.new()
	pool.name = "CraterPool"
	pool.radius = crater_radius
	pool.light_energy = 7.0
	root.add_child(pool)
	pool.owner = island
	pool.position = Vector3(crater.x, floor_y + 0.8, crater.y)
	# trace candidate flows from the rim, keep the longest distinct ones
	var cands := []
	for k in start_angles:
		var a := TAU * float(k) / float(start_angles)
		var start := crater + Vector2(cos(a), sin(a)) * (crater_radius + 7.0)
		cands.append(_trace(terrain, start, Vector2(cos(a), sin(a))))
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.drop > y.drop)
	var picked := []
	for c: Dictionary in cands:
		if picked.size() >= flow_count:
			break
		var far_enough := true
		for p: Dictionary in picked:
			if (c.pts[c.pts.size() - 1] as Vector2).distance_to(p.pts[p.pts.size() - 1]) < 40.0:
				far_enough = false
		if far_enough and c.pts.size() > 15:
			picked.append(c)
	for i in picked.size():
		var c: Dictionary = picked[i]
		var f := LavaFlow.new()
		f.name = "LavaFlow_%d" % i
		f.width = 3.5 + i * 0.7
		f.terrain_path = NodePath("../../Terrain")
		var cv := Curve3D.new()
		var pts: Array = c.pts
		# start in the crater pool so the flow reads as pouring over the rim
		var first: Vector2 = crater + ((pts[0] as Vector2) - crater).normalized() * (crater_radius * 0.6)
		cv.add_point(Vector3(first.x, 0, first.y))
		for j in range(0, pts.size(), 3):
			var p: Vector2 = pts[j]
			cv.add_point(Vector3(p.x, 0, p.y))
		f.curve = cv
		root.add_child(f)
		f.owner = island
		f.set("carve_channel", true)                     # dig its channel into the terrain
		var end: Vector2 = pts[pts.size() - 1]
		var end_h: float = terrain.height_at(end.x, end.y)
		if end_h > 0.5:                                  # stopped on land: pool up
			var ep := LavaPool.new()
			ep.name = "FlowPool_%d" % i
			ep.radius = 5.0 + i
			root.add_child(ep)
			ep.owner = island
			ep.position = Vector3(end.x, end_h + 0.35, end.y)
		print("[lava] flow %d: %d m long, drops %.0f m, ends at %s (h %.1f)" % [i, pts.size() * 2, c.drop, end, end_h])
	# save the carved terrain + the scene
	var t3d: Node = terrain.get("t3d")
	t3d.data.save_directory(t3d.data_directory)
	var out := PackedScene.new()
	out.pack(island)
	ResourceSaver.save(out, ISLAND)
	print("[lava] DONE: crater pool + %d flows" % picked.size())
	get_tree().quit()


## Steepest descent with a little momentum, 2 m steps. Returns { pts: Array[Vector2], drop: float }.
func _trace(terrain: Node, start: Vector2, dir0: Vector2) -> Dictionary:
	var p := start
	var dir := dir0
	var pts := [p]
	var h0: float = terrain.height_at(p.x, p.y)
	var h: float = h0
	for i in 260:
		var best := Vector2.ZERO
		var best_score := INF
		for k in 16:
			var a := TAU * float(k) / 16.0
			var d := Vector2(cos(a), sin(a))
			var q := p + d * 2.0
			var hq: float = terrain.height_at(q.x, q.y)
			var score := hq - h - d.dot(dir) * 0.35
			if score < best_score:
				best_score = score
				best = d
		var nxt := p + best * 2.0
		var hn: float = terrain.height_at(nxt.x, nxt.y)
		if hn > h + 0.05 or hn < -0.5:                  # uphill (a hollow) or into the sea: stop here
			if hn < -0.5:
				pts.append(nxt)
			break
		dir = (dir * 0.6 + best * 0.4).normalized()
		p = nxt
		h = hn
		pts.append(p)
	return { "pts": pts, "drop": h0 - h }
