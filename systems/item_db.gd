extends Node
## Autoload: ItemDB. item_id -> ItemDef resource (data/items/item_def.gd).

const REGISTRY_PATH := "res://data/registry/items.tres"

var _items: Dictionary = {}


func _ready() -> void:
	var reg := load(REGISTRY_PATH)
	if reg == null or not ("items" in reg):
		push_error("ItemDB: could not load %s" % REGISTRY_PATH)
		return
	for id: String in reg.items:
		if reg.items[id]:
			_items[id] = reg.items[id]


func get_item(item_id: String) -> Resource:
	if not _items.has(item_id):
		push_warning("ItemDB: unknown item '%s'" % item_id)
	return _items.get(item_id)


func has_item(item_id: String) -> bool:
	return _items.has(item_id)
