extends Node
func _ready() -> void:
	for c in ["Terrain3D", "Terrain3DMaterial", "Terrain3DCollision", "Terrain3DData", "Terrain3DRegion"]:
		if not ClassDB.class_exists(c):
			print(c, " missing")
			continue
		var out := []
		for e in ClassDB.class_get_enum_list(c, true):
			var vals := []
			for k in ClassDB.class_get_enum_constants(c, e, true):
				vals.append("%s=%d" % [k, ClassDB.class_get_integer_constant(c, k)])
			out.append("%s{%s}" % [e, ", ".join(vals)])
		print("## ", c, ": ", " ".join(out))
	var t: Node = ClassDB.instantiate("Terrain3D")
	print("material prop: ", t.get("material"), " assets: ", t.get("assets"), " region_size: ", t.get("region_size"))
	for p in t.get_property_list():
		if p.name in ["material", "assets", "data", "collision_mode", "region_size", "mesh_size", "mesh_lods", "cull_margin", "free_editor_textures"]:
			print("prop ", p.name, " type ", p.type, " hint ", p.hint_string)
	t.free()
	get_tree().quit()
