extends StaticBody3D
## Treasure chest. Its look tells you the tier (common wood -> legendary purple/gold glow).
## Walk up + E: the host rolls the contents from this tier's loot pool, every peer sees the lid
## swing open and the items pop out as normal pickups (same names everywhere, so taking syncs).
## Shares the pickup interface (group "pickups", taken, display_name(), request_take()).

const PickupScene := preload("res://scenes/items/pickup.tscn")
const FX := preload("res://systems/components/element_fx.gd")
const MODELS := {
	"common": "res://assets/models/items/chest_common.glb", "uncommon": "res://assets/models/items/chest_uncommon.glb",
	"rare": "res://assets/models/items/chest_rare.glb", "legendary": "res://assets/models/items/chest_legendary.glb",
}
const TIER_COLOR := { "common": Color(1, 0.9, 0.6), "uncommon": Color(0.85, 0.95, 1.0),
	"rare": Color(0.4, 0.7, 1.0), "legendary": Color(0.85, 0.45, 1.0) }

@export_enum("common", "uncommon", "rare", "legendary") var tier := "common"
@export var interact_radius := 2.4
var loot_pool: Array = []                  ## item ids (set by the map from its loot tables)
var rolls := Vector2i(1, 2)                ## how many items come out (min, max)
var taken := false                         ## opened
var _lid: Node3D


func _ready() -> void:
	add_to_group("pickups")
	set_meta("material", "wood")
	var ps: PackedScene = load(MODELS.get(tier, MODELS.common))
	var model := ps.instantiate()
	model.name = "Model"
	add_child(model)
	_lid = model.find_child("Lid", true, false) as Node3D
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0 + 0.1 * MODELS.keys().find(tier), 0.6, 0.7)
	cs.shape = box
	cs.position.y = 0.3
	add_child(cs)
	if tier == "rare" or tier == "legendary":
		var l := OmniLight3D.new()
		l.light_color = TIER_COLOR[tier]
		l.light_energy = 1.2
		l.omni_range = 4.0
		l.position = Vector3(0, 0.9, 0.3)
		add_child(l)


func display_name() -> String:
	return "%s Chest" % tier.capitalize()


func prompt_text() -> String:
	return "[E] Open %s" % display_name()


func request_take() -> void:
	if taken:
		return
	if multiplayer.is_server():
		rpc_request_open()
	else:
		rpc_request_open.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_open() -> void:
	if not multiplayer.is_server() or taken:
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var player := get_tree().current_scene.get_node_or_null("Players/%d" % peer) as Node3D
	if player == null or player.global_position.distance_to(global_position) > interact_radius + 1.0:
		return
	var items := PackedStringArray()
	if not loot_pool.is_empty():
		for i in randi_range(rolls.x, rolls.y):
			items.append(str(loot_pool[randi() % loot_pool.size()]))
	rpc_opened.rpc(items)


@rpc("authority", "call_local", "reliable")
func rpc_opened(items: PackedStringArray) -> void:
	taken = true
	if _lid:
		var tw := create_tween()
		tw.tween_property(_lid, "rotation:x", deg_to_rad(-105.0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var c: Color = TIER_COLOR.get(tier, Color.WHITE)
	FX.burst(global_position + Vector3.UP * 0.6, get_tree().current_scene, c, 18 + 8 * MODELS.keys().find(tier), 0.07, 3.5)
	Audio.play_at("item.get", global_position, 0.0, 0.9)
	var front := global_basis.z
	for i in items.size():
		if not ItemDB.has_item(items[i]):
			continue
		var pu := PickupScene.instantiate()
		pu.name = "%s_Loot_%d" % [name, i]
		pu.item_id = items[i]
		get_parent().add_child(pu)
		var side := global_basis.x * ((i - (items.size() - 1) * 0.5) * 0.9)
		pu.global_position = global_position + front * 1.3 + side
