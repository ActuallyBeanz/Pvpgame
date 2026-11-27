extends Node
## Replaces the auto-generated box bridges with editable Bridge nodes (systems/world/bridge.gd)
## where paths cross water, saved into island.tscn under "Bridges". Re-runnable (rebuilds them).
## Afterwards: drag a bridge's A / B markers in the editor, or duplicate a bridge for a new one.
## Run: Godot_console.exe --headless --path . res://tools/map/build_bridges.tscn

const BridgeScript := preload("res://systems/world/bridge.gd")
const ISLAND := "res://scenes/match/island.tscn"


func _ready() -> void:
	var island: Node3D = (load(ISLAND) as PackedScene).instantiate()
	for c in island.get_children():               # old Bridge nodes (also a mis-named one from an old run)
		if c.name == "Bridges" or str(c.name).begins_with("@"):
			island.remove_child(c)
			c.free()                              # so the island regenerates its crossings list
	add_child(island)
	await get_tree().process_frame
	for c in island.get_children():               # the runtime box bridges it just generated
		if c.name == "Bridges" or str(c.name).begins_with("@"):
			island.remove_child(c)
			c.free()
	var root := Node3D.new()
	root.name = "Bridges"
	island.add_child(root)
	root.owner = island
	var i := 0
	for c: Array in island.crossings:
		var a2: Vector2 = c[0]
		var b2: Vector2 = c[1]
		var dir := (b2 - a2).normalized()
		a2 -= dir * 1.0                           # a metre onto each bank
		b2 += dir * 1.0
		var pa := Vector3(a2.x, island.ground(a2.x, a2.y) + 0.03, a2.y)
		var pb := Vector3(b2.x, island.ground(b2.x, b2.y) + 0.03, b2.y)
		var br := BridgeScript.new()
		br.name = "Bridge_%d" % i
		br.terrain_path = NodePath("../../Terrain")
		root.add_child(br)
		br.owner = island
		br.position = pa
		for m in [["A", Vector3.ZERO], ["B", pb - pa]]:
			var mk := Marker3D.new()
			mk.name = m[0]
			br.add_child(mk)
			mk.owner = island
			mk.position = m[1]
		print("[bridges] %s: %.0f m" % [br.name, pa.distance_to(pb)])
		i += 1
	var out := PackedScene.new()
	out.pack(island)
	ResourceSaver.save(out, ISLAND)
	print("[bridges] DONE: %d" % i)
	get_tree().quit()
