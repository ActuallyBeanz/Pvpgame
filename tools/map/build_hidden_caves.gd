extends Node
## Hidden caves (replaces the old above-ground cave outcrops). Re-runnable.
##   * hand-picked spots (bug reports "hide a cave here"): the nearest cliff face from the hint,
##     a bombable door flush with the cliff
##   * river caves: auto-picked spots where a gorge wall rises out of the water with a thick hill
##     behind it; open mouth just above the water - swim up and climb in
## For each: punches a Terrain3D hole at the mouth, raises the hill if it's too thin to hold the
## room, flattens the approach, adds a HiddenCave node under SecretSpots. Saves terrain + scene.
## Run: Godot_console.exe --headless --path . res://tools/map/build_hidden_caves.tscn

const CaveScript := preload("res://scenes/props/world/hidden_cave.gd")
const ISLAND := "res://scenes/match/island.tscn"

## hints from the bug reports: [player position xz, tier]
var hand_spots := [[Vector2(198.1, -213.1), "legendary"], [Vector2(-207.0, -200.8), "rare"]]
## Pinned results ([at, out, floor, door, tier]) so re-running doesn't drift (each run reshapes
## the hills it searched). Clear this to search again from the hints / rivers.
var pinned := [
	[Vector2(195.1302, -210.1302), Vector2(0.707107, -0.707107), -1.0, "cracked", "legendary"],
	[Vector2(-198.3, -200.8), Vector2(-1.0, 0.0), -1.0, "cracked", "rare"],
	[Vector2(-9.05, 115.0), Vector2(1.0, 0.0), 0.45, "open", "rare"],
	[Vector2(1.924443, -121.0756), Vector2(-0.707107, -0.707107), 0.45, "open", "uncommon"],
	[Vector2(157.0, -83.2), Vector2(0.0, -1.0), 0.45, "open", "rare"],
	[Vector2(55.92444, -1.075557), Vector2(-0.707107, -0.707107), 0.45, "open", "uncommon"],
]
## Spots from earlier test runs: holes cleared + cliff notch filled back in.
var stale := [
	[Vector2(197.0777, -209.2846), Vector2(0.258819, -0.965926)],
	[Vector2(-199.1932, -197.5663), Vector2(-0.92388, -0.382683)],
	[Vector2(2.645539, -121.0273), Vector2(-0.382683, -0.92388)],
	[Vector2(139.0, -82.2), Vector2(0.0, -1.0)],
	[Vector2(-119.0, -102.05), Vector2(0.0, 1.0)],
]
@export var river_caves := 4
@export var river_min_gap := 70.0
@export var river_floor := 0.45                 ## above the sea / river level (0)

const TL := 7.0            # tunnel length (model)
const ROOM := Vector2(6.4, 19.5)   # room half width, back depth (model, with walls)
var island: Node3D
var terrain: Node
var data: Object
var placed: Array[Vector2] = []


func _ready() -> void:
	island = (load(ISLAND) as PackedScene).instantiate()
	add_child(island)
	await get_tree().process_frame
	terrain = island.get_node("Terrain")
	data = terrain.get("t3d").data
	var spots := island.get_node("SecretSpots")
	for c in spots.get_children():
		if c.name.begins_with("Cave_") or c.name.begins_with("Hidden"):
			spots.remove_child(c)
			c.free()
	for st in stale:
		_repair(st[0], st[1])
	var n := 0
	if not pinned.is_empty():
		for pin in pinned:
			var fl: float = pin[2]
			if fl < -0.5:                                   # hand spots: ground in front of the mouth
				var q: Vector2 = pin[0] + (pin[1] as Vector2) * 1.5
				fl = _h(q.x, q.y)
			_make(spots, "HiddenCave_%d" % n, pin[0], pin[1], fl, pin[3], pin[4])
			n += 1
		_finish(n)
		return
	for hs in hand_spots:
		var e := _cliff_entrance(hs[0])
		if e.is_empty():
			print("[caves] no cliff near %s" % hs[0])
			continue
		_make(spots, "HiddenCave_%d" % n, e.at, e.out, e.floor, "cracked", hs[1])
		n += 1
	var cands := _river_candidates()
	print("[caves] %d river candidates" % cands.size())
	var made := 0
	while made < river_caves and not cands.is_empty():
		var best := -1
		var best_d := -1.0
		for k in cands.size():
			var d := 1e9
			for p in placed:
				d = minf(d, (cands[k].at as Vector2).distance_to(p))
			d += float(cands[k].score) * 2.0
			if d > best_d:
				best_d = d
				best = k
		var c: Dictionary = cands[best]
		cands.remove_at(best)
		var ok := true
		for p in placed:
			if (c.at as Vector2).distance_to(p) < river_min_gap:
				ok = false
		if not ok:
			continue
		_make(spots, "HiddenCave_%d" % n, c.at, c.out, river_floor, "open", "rare" if made % 2 == 0 else "uncommon")
		n += 1
		made += 1
	_finish(n)


func _finish(n: int) -> void:
	data.update_maps()
	var t3d: Node = terrain.get("t3d")
	t3d.data.save_directory(t3d.data_directory)
	var out := PackedScene.new()
	out.pack(island)
	ResourceSaver.save(out, ISLAND)
	print("[caves] DONE: %d hidden caves" % n)
	get_tree().quit()


func _h(x: float, z: float) -> float:
	return data.get_height(Vector3(x, 0, z))


## From a hint spot: the closest steep rise; the mouth goes at its foot, facing back out.
func _cliff_entrance(hint: Vector2) -> Dictionary:
	var base := _h(hint.x, hint.y)
	var best_dir := Vector2.ZERO
	var best_k := 99.0
	for i in 48:
		var a := TAU * i / 48.0
		var d := Vector2(cos(a), sin(a))
		var k := 0.5
		while k < 16.0:
			var q := hint + d * k
			if _h(q.x, q.y) > base + 6.0:
				break
			k += 0.5
		if k < best_k:
			best_k = k
			best_dir = d
	if best_k > 15.0:
		return {}
	var k2 := 0.0
	while k2 < best_k:
		var q := hint + best_dir * k2
		if _h(q.x, q.y) > base + 1.0:
			break
		k2 += 0.25
	var at := hint + best_dir * maxf(k2 - 0.3, 0.0)
	return { "at": at, "out": -best_dir, "floor": base }


## River-wall spots: in the water, a wall rising right next to it, thick hill behind, land across.
func _river_candidates() -> Array:
	var out := []
	for x in range(-230, 231, 3):
		for z in range(-230, 231, 3):
			var p := Vector2(x, z)
			if _h(p.x, p.y) > -1.2:
				continue
			for i in 16:
				var a := TAU * i / 16.0
				var d := Vector2(cos(a), sin(a))
				var face := -1.0
				var k := 0.5
				while k <= 6.0:
					var q := p + d * k
					if _h(q.x, q.y) > river_floor:
						face = k
						break
					k += 0.25
				if face < 0.0:
					continue
				var e := p + d * (face - 0.2)
				var right := Vector2(d.y, -d.x)
				var min_cover := 1e9
				for s in [3.0, 6.0, 10.0, 14.0, 18.0]:
					for l in [-5.0, 0.0, 5.0]:
						var q2: Vector2 = e + d * s + right * l
						min_cover = minf(min_cover, _h(q2.x, q2.y) - river_floor)
				if min_cover < 7.0:
					continue
				var across := false
				for s2 in range(6, 34, 2):
					var q3 := e - d * s2
					if _h(q3.x, q3.y) > 3.0:
						across = true
						break
				if not across:
					continue                                    # open sea, not a river
				out.append({ "at": e, "out": -d, "score": minf(min_cover, 14.0) })
	return out


func _style(at: Vector2, into: Vector2) -> String:
	var q := at + into * 10.0
	match str(terrain.biome_at(q.x, q.y)):
		"ash", "lava":
			return "basalt"
		"snow", "ice":
			return "snow"
		"sand", "mesa", "beach":
			return "sand"
	return "stone"


func _make(parent: Node, nm: String, at: Vector2, out: Vector2, floor_y: float, door: String, tier: String) -> void:
	var into := -out
	var right := Vector2(into.y, -into.x)
	# 1. hill thick enough over tunnel + room (raise where thin), approach flat
	for x in range(int(at.x - 26), int(at.x + 27)):
		for z in range(int(at.y - 26), int(at.y + 27)):
			var off := Vector2(x, z) - at
			var s := off.dot(into)
			var l := absf(off.dot(right))
			var cur := _h(x, z)
			if s >= 1.5 and s <= ROOM.y + 3.0:
				var hw := 3.6 if s < TL + 0.5 else ROOM.x + 0.6
				var need := floor_y + (5.4 if s < TL + 0.5 else 6.6)
				var w := 1.0 - smoothstep(hw, hw + 4.0, l)
				w *= 1.0 - smoothstep(ROOM.y + 0.5, ROOM.y + 3.0, s)
				if cur < need and w > 0.0:
					data.set_height(Vector3(x, 0, z), lerpf(cur, need + 0.6, w))
			elif door == "cracked" and s < -0.3 and s > -7.0 and l < 5.0:   # dry approach: flat
				var w2 := (1.0 - smoothstep(2.6, 5.0, l)) * (1.0 - smoothstep(-5.0, -7.0, s))
				data.set_height(Vector3(x, 0, z), lerpf(cur, floor_y - 0.05, w2))
	# 1b. recess the cliff right above the mouth to just over the tunnel roof (a heightfield can't
	#     overhang: without this the hole would open a slot all the way up a tall cliff face)
	for x in range(int(at.x - 8), int(at.x + 9)):
		for z in range(int(at.y - 8), int(at.y + 9)):
			var off := Vector2(x, z) - at
			var s := off.dot(into)
			var l := absf(off.dot(right))
			if s < -0.2 or s > 2.6 or l > 3.8:
				continue
			var cap := floor_y + 4.8 + smoothstep(3.0, 3.8, l) * 20.0 + smoothstep(2.2, 2.6, s) * 20.0
			var cur := _h(x, z)
			if cur > cap:
				data.set_height(Vector3(x, 0, z), cap)
	# 2. hole where the terrain crosses the tunnel / room volume (old holes cleared first: re-runnable)
	for x in range(int(at.x - 24), int(at.x + 25)):
		for z in range(int(at.y - 24), int(at.y + 25)):
			data.set_control_hole(Vector3(x, 0, z), false)
	var holes := 0
	for x in range(int(at.x - 24), int(at.x + 25)):
		for z in range(int(at.y - 24), int(at.y + 25)):
			var off := Vector2(x, z) - at
			var s := off.dot(into)
			var l := absf(off.dot(right))
			var hw := 2.4 if s < TL else ROOM.x - 0.4
			if s < -0.2 or s > ROOM.y or l > hw:
				continue
			var cur := _h(x, z)
			# mouth: only the front row (every triangle touching a holed vertex goes - holing the shelf
			# next to the cliff would open a slot to the sky). Deeper in: only where it cuts the room.
			var roof := floor_y + (5.0 if s < 1.0 else 4.4 if s < TL else 6.0)
			if s < 2.6 and s >= 1.0:
				continue
			if cur > floor_y - 1.5 and cur < roof:
				data.set_control_hole(Vector3(x, 0, z), true)
				holes += 1
	# 3. the cave
	var cave := CaveScript.new()
	cave.name = nm
	cave.style = _style(at, into)
	cave.door = door
	cave.tier = tier
	parent.add_child(cave)
	cave.owner = island
	cave.position = Vector3(at.x, floor_y, at.y)
	cave.rotation.y = atan2(out.x, out.y)
	placed.append(at)
	print("[caves] %s %s %s %s at %s facing %s, %d hole cells" % [nm, cave.style, door, tier, at, out, holes])


## Undo a stale cave mouth: clear its holes, fill the cliff notch from the rock either side.
func _repair(at: Vector2, out: Vector2) -> void:
	var into := -out
	var right := Vector2(into.y, -into.x)
	for x in range(int(at.x - 24), int(at.x + 25)):
		for z in range(int(at.y - 24), int(at.y + 25)):
			data.set_control_hole(Vector3(x, 0, z), false)
	for x in range(int(at.x - 6), int(at.x + 7)):
		for z in range(int(at.y - 6), int(at.y + 7)):
			var off := Vector2(x, z) - at
			var s := off.dot(into)
			var l := off.dot(right)
			if s < -0.2 or s > 3.0 or absf(l) > 4.0:
				continue
			var a := at + into * s + right * 4.6
			var b := at + into * s - right * 4.6
			var fill := lerpf(_h(b.x, b.y), _h(a.x, a.y), (l + 4.6) / 9.2)
			if _h(x, z) < fill:
				data.set_height(Vector3(x, 0, z), fill)
