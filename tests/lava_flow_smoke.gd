extends Node
## Real island match: stand in a lava flow with no input -> the current drags you downhill;
## walking in lava is slowed. Prints PASS/FAIL.   godot --headless res://tests/lava_flow_smoke.tscn
var _t := 0.0
var _phase := 0
var _player: CharacterBody3D
var _p0 := Vector3.ZERO
var _down := Vector3.ZERO


func _ready() -> void:
	if get_tree().current_scene == self:
		var driver: Node = get_script().new()
		get_tree().root.add_child.call_deferred(driver)
		return
	Lobby.local_profile = { "name": "Solo", "color": 3 }
	Lobby.match_scene = "res://scenes/match/island.tscn"
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _physics_process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	var scene := get_tree().current_scene
	match _phase:
		0:
			if scene and scene.has_node("Players/1") and _t > 3.0:
				_player = scene.get_node("Players/1")
				var flow := scene.get_node("Lava/LavaFlow_2") as Path3D
				var L := flow.curve.get_baked_length()
				var a := flow.global_transform * flow.curve.sample_baked(L * 0.5)
				var b := flow.global_transform * flow.curve.sample_baked(L * 0.5 + 3.0)
				_down = Vector3(b.x - a.x, 0, b.z - a.z).normalized()
				_player.global_position = Vector3(a.x, scene.ground(a.x, a.z) + 0.3, a.z)
				_player.velocity = Vector3.ZERO
				_t = 0.0
				_phase = 1
		1:
			if _t > 0.25 and _p0 == Vector3.ZERO:
				_p0 = _player.global_position
			if _t > 1.05:
				var moved := _player.global_position - _p0
				var along := Vector3(moved.x, 0, moved.z).dot(_down)
				var ok := along > 0.6
				print("[lava] %s drifted %.2f m downstream in 0.8 s with no input (pos %s)" % ["PASS" if ok else "FAIL", along, _player.global_position.snapped(Vector3.ONE * 0.1)])
				get_tree().quit(0 if ok else 1)
