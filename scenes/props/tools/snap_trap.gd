extends Node3D
## Snapjaw Trap on the ground. Arms after a moment; whoever steps on it (checked by each
## player's own machine for itself) takes damage and is held in place. Then it's spent.
## The player who set it is safe until they've stepped off it once.

const FX := preload("res://systems/components/element_fx.gd")

var arm_time := 1.0
var damage := 25.0
var root_time := 1.6
var radius := 0.65
var placer_peer := 0
var placer_name := ""
var _t := 0.0
var _sprung := false
var _placer_clear := false
var _model: Node3D


func _ready() -> void:
	add_to_group("snap_traps")
	_model = AssetRegistry.instantiate("item.trap.snapjaw")
	add_child(_model)
	Audio.play_at("shield.block", global_position, -6.0, 1.5)


func _physics_process(delta: float) -> void:
	if _sprung:
		return
	_t += delta
	var me := get_tree().current_scene.get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as Node3D
	if me == null or me.get("sync_dead"):
		return
	var d := Vector2(me.global_position.x - global_position.x, me.global_position.z - global_position.z).length()
	var on_it := d < radius and absf(me.global_position.y - global_position.y) < 1.0
	if multiplayer.get_unique_id() == placer_peer and not _placer_clear:
		_placer_clear = not on_it
		return
	if _t >= arm_time and on_it:
		_sprung = true
		var hp: Node = me.get("health")
		if hp:
			hp.take_damage(damage, Vector3.ZERO, "hit", placer_name)
			hp.apply_root(root_time)
		rpc_snap.rpc()


@rpc("any_peer", "call_local", "reliable")
func rpc_snap() -> void:
	_sprung = true
	Audio.play_at("shield.bash", global_position, 4.0, 0.7)
	FX.burst(global_position + Vector3.UP * 0.2, get_tree().current_scene, Color(0.7, 0.7, 0.75), 14, 0.06, 4.0)
	if _model:
		var tw := create_tween()
		tw.tween_property(_model, "scale", Vector3(0.55, 1.4, 1.0), 0.08)
		tw.tween_interval(2.0)
		tw.tween_property(_model, "scale", Vector3.ZERO, 0.4)
		tw.tween_callback(queue_free)
