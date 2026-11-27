extends StaticBody3D
## Bombable wall (OoT cracked wall). Explosions and the hammer break it: swords, arrows and
## fire just clink off. When a bomb goes off close enough it bursts into rubble on every peer
## and stays open for the rest of the match. Fixed node names, so the break syncs by path.

const FX := preload("res://systems/components/element_fx.gd")
const MODELS := { "stone": "res://assets/models/env/wall_cracked_stone.glb", "sand": "res://assets/models/env/wall_cracked_sand.glb" }
const RUBBLE := { "stone": "res://assets/models/env/rubble_stone.glb", "sand": "res://assets/models/env/rubble_sand.glb" }

@export_enum("stone", "sand") var style := "stone"
var broken := false
var _model: Node3D


func _ready() -> void:
	add_to_group("cracked_walls")
	set_meta("material", "stone")
	_model = (load(MODELS.get(style, MODELS.stone)) as PackedScene).instantiate()
	_model.name = "Model"
	add_child(_model)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 3.2, 0.8)
	cs.shape = box
	cs.position.y = 1.6
	add_child(cs)


## Hits route here (WorldRules.deliver_hit). Bomb blasts ("blast") and hammer blows ("smash")
## break it; anything else clinks off.
func react_to_hit_info(hit: Dictionary, cosmetic: bool) -> void:
	if broken:
		return
	print("[secret] %s hit (blast=%s smash=%s cosmetic=%s)" % [name, hit.get("blast", false), hit.get("smash", false), cosmetic])
	if not bool(hit.get("blast", false)) and not bool(hit.get("smash", false)):
		Audio.play_at("shield.block", global_position + Vector3.UP * 1.5, -6.0, 0.7)    # clink
		return
	if not cosmetic:
		rpc_break.rpc()


@rpc("any_peer", "call_local", "reliable")
func rpc_break() -> void:
	if broken:
		return
	broken = true
	var at := global_position + Vector3.UP * 1.4
	var col := Color(0.6, 0.57, 0.52) if style == "stone" else Color(0.85, 0.66, 0.42)
	FX.burst(at, get_tree().current_scene, col, 40, 0.22, 7.0)
	FX.smoke_puff(at, get_tree().current_scene, 2.6)
	Audio.play_at("wood.break", at, 6.0, 0.45)
	Audio.play_at("ui.match_start", at, -2.0, 1.2)     # secret found!
	_model.visible = false
	($Shape as CollisionShape3D).set_deferred("disabled", true)
	var rubble := (load(RUBBLE.get(style, RUBBLE.stone)) as PackedScene).instantiate() as Node3D
	add_child(rubble)
	rubble.position = Vector3(0, 0, 0.8)
	print("[secret] %s blown open" % name)
