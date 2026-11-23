extends Node
## Autoload: AssetRegistry. model_id -> PackedScene.
## Gameplay code only ever asks for ids, never file paths, so models can be
## swapped by editing res://data/registry/models.tres in the Inspector.

const REGISTRY_PATH := "res://data/registry/models.tres"
const MISSING_ID := "debug.missing"

var _scenes: Dictionary = {}   # String -> PackedScene


func _ready() -> void:
	load_registry(REGISTRY_PATH)


func load_registry(path: String) -> void:
	var reg := load(path)
	if reg == null or not ("models" in reg):
		push_error("AssetRegistry: could not load %s" % path)
		return
	for id: String in reg.models:
		if reg.models[id]:
			_scenes[id] = reg.models[id]


## Add or override an entry at runtime (e.g. from a future asset download API).
func register(model_id: String, scene: PackedScene) -> void:
	_scenes[model_id] = scene


func has_model(model_id: String) -> bool:
	return _scenes.has(model_id)


func ids_with_prefix(prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _scenes:
		if id.begins_with(prefix):
			out.append(id)
	out.sort()
	return out


func get_scene(model_id: String) -> PackedScene:
	if _scenes.has(model_id):
		return _scenes[model_id]
	push_warning("AssetRegistry: '%s' missing, using placeholder." % model_id)
	return _scenes.get(MISSING_ID)


func instantiate(model_id: String) -> Node3D:
	var scene := get_scene(model_id)
	if scene == null:
		return Node3D.new()
	return scene.instantiate() as Node3D
