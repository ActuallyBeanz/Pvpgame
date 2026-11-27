extends StaticBody3D
## Bombable wall (OoT cracked wall): a stone doorway (frame, always solid) plugged with cracked
## rubble (the fill). Explosions and the hammer break the fill: swords, arrows and fire just
## clink off. When it blows it bursts into rubble on every peer and the doorway stays open for
## the rest of the match. Fixed node names, so the break syncs by path.
## Styles: stone (mossy), sand (glyph), basalt (ember veins), snow (snow caps + icicles).

const FX := preload("res://systems/components/element_fx.gd")
const DIR := "res://assets/models/env/"
const OPENING := Vector2(2.6, 2.5)             ## the fill's size (frame: 3.6 x 3.2 x 0.8 overall)
const DUST := { "stone": Color(0.6, 0.57, 0.52), "sand": Color(0.85, 0.66, 0.42),
	"basalt": Color(0.3, 0.27, 0.27), "snow": Color(0.7, 0.74, 0.8) }

@export_enum("stone", "sand", "basalt", "snow") var style := "stone"
var broken := false
var _model: Node3D


func _ready() -> void:
	add_to_group("cracked_walls")
	set_meta("material", "stone")
	if not DUST.has(style):
		style = "stone"
	# the doorway itself: its own body so it stays solid after the fill blows
	var frame := StaticBody3D.new()
	frame.name = "Frame"
	frame.set_meta("material", "stone")
	frame.add_child((load(DIR + "wall_frame_%s.glb" % style) as PackedScene).instantiate())
	var pw := (3.6 - OPENING.x) * 0.5
	for part in [[Vector3(-(OPENING.x + pw) * 0.5, 1.6, 0), Vector3(pw, 3.2, 0.8)],
			[Vector3((OPENING.x + pw) * 0.5, 1.6, 0), Vector3(pw, 3.2, 0.8)],
			[Vector3(0, (OPENING.y + 3.2) * 0.5, 0), Vector3(OPENING.x, 3.2 - OPENING.y, 0.8)]]:
		var fcs := CollisionShape3D.new()
		var fb := BoxShape3D.new()
		fb.size = part[1]
		fcs.shape = fb
		fcs.position = part[0]
		frame.add_child(fcs)
	add_child(frame)
	_model = (load(DIR + "wall_fill_%s.glb" % style) as PackedScene).instantiate()
	_model.name = "Model"
	add_child(_model)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(OPENING.x, OPENING.y, 0.7)
	cs.shape = box
	cs.position.y = OPENING.y * 0.5
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
	var col: Color = DUST.get(style, DUST.stone)
	FX.burst(at, get_tree().current_scene, col, 40, 0.22, 7.0)
	FX.smoke_puff(at, get_tree().current_scene, 2.6)
	Audio.play_at("wood.break", at, 6.0, 0.45)
	Audio.play_at("ui.match_start", at, -2.0, 1.2)     # secret found!
	_model.visible = false
	($Shape as CollisionShape3D).set_deferred("disabled", true)
	var rubble := (load(DIR + "rubble_%s.glb" % style) as PackedScene).instantiate() as Node3D
	add_child(rubble)
	rubble.position = Vector3(0, 0, 0.8)
	print("[secret] %s blown open" % name)
