extends Node3D
## World pickup. Bobs and spins; press interact nearby to take it.
## Host-authoritative: a client asks the host (rpc_request_take), the host checks
## distance + availability, then tells every peer who got it (rpc_taken).
## Spawned with the same name on every peer (deterministic) so RPC paths match.

const GROUP := "pickups"

@export var item_id := ""
@export var amount := 0                    ## 0 = use the item's default amount
@export var interact_radius := 2.2
@export var bob_height := 0.15
@export var bob_speed := 2.0
@export var spin_speed := 1.2
@export var glow_color := Color(1.0, 0.82, 0.35)

var item: Resource
var taken := false
var _t := 0.0
var _visual: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	item = ItemDB.get_item(item_id)
	if item == null:
		return
	var mid: String = item.pickup_model_id if item.pickup_model_id != "" else item.model_id
	_visual = AssetRegistry.instantiate(mid)
	add_child(_visual)
	_t = randf() * TAU
	# Modern-lighting accent: soft glow light + emissive ground ring.
	var light := OmniLight3D.new()
	light.light_color = glow_color
	light.light_energy = 0.8
	light.omni_range = 2.5
	light.position = Vector3(0, 0.8, 0)
	add_child(light)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.65
	torus.rings = 16
	torus.ring_segments = 4
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = glow_color
	mat.emission_enabled = true
	mat.emission = glow_color
	mat.emission_energy_multiplier = 1.5
	ring.material_override = mat
	ring.position.y = 0.03
	ring.scale.y = 0.3
	add_child(ring)


func _process(delta: float) -> void:
	if _visual == null:
		return
	_t += delta
	_visual.position.y = 0.6 + sin(_t * bob_speed) * bob_height
	_visual.rotation.y += spin_speed * delta


func display_name() -> String:
	return item.display_name if item else item_id


func give_amount() -> int:
	return amount if amount > 0 else (item.amount if item else 0)


## Called by the local player's Equipment.
func request_take() -> void:
	if taken:
		return
	if multiplayer.is_server():
		rpc_request_take()
	else:
		rpc_request_take.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_take() -> void:
	if not multiplayer.is_server() or taken:
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var player := get_tree().current_scene.get_node_or_null("Players/%d" % peer) as Node3D
	if player == null or player.global_position.distance_to(global_position) > interact_radius + 1.0:
		return  # too far: ignore (anti-cheat-lite)
	rpc_taken.rpc(peer)


@rpc("authority", "call_local", "reliable")
func rpc_taken(peer: int) -> void:
	taken = true
	if peer == multiplayer.get_unique_id():
		Audio.play("item.ammo" if item and item.kind == "ammo" else "item.get")
	else:
		Audio.play_at("item.pickup_far", global_position)
	if peer == multiplayer.get_unique_id():
		var player := get_tree().current_scene.get_node_or_null("Players/%d" % peer)
		if player and player.has_node("Equipment"):
			player.get_node("Equipment").receive_item(item_id, give_amount())
	queue_free()
