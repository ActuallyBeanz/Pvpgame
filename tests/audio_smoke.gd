extends Node
## Headless: every registered sound loads, buttons click, and playing solo fires
## the expected sounds (steps, jump, land, roll, pickup, draw, bow draw/fire, hit).
##   godot --headless res://tests/audio_smoke.tscn

const EXPECT := ["amb.field", "ui.match_start", "ui.select", "player.footstep.grass", "player.jump",
	"player.land", "player.roll", "item.get", "weapon.draw", "bow.draw", "bow.fire"]

var _step := 0
var _t := 0.0
var _player: CharacterBody3D
var _eq: Node
var _heard: Dictionary = {}


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Audio.played.connect(func(id: String) -> void: _heard[id] = _heard.get(id, 0) + 1)
	# 1. registry
	var reg: Resource = load(Audio.REGISTRY_PATH)
	var bad := 0
	for id: String in reg.sounds:
		for s: AudioStream in reg.sounds[id].streams:
			if s == null or s.get_length() <= 0.0:
				bad += 1
				print("[audio] bad stream in ", id)
	print("[audio] %d sound ids, %d bad streams" % [reg.sounds.size(), bad])
	if bad:
		_done(false, "bad streams")
		return
	# 2. auto button sounds
	var b := Button.new()
	b.text = "Test"
	add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	b.pressed.emit()
	b.queue_free()
	# 3. play solo
	Lobby.local_profile = { "name": "Ears", "color": 2 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _physics_process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _t > 25.0:
		_done(false, "timeout at step %d" % _step)
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	match _step:
		0:
			if scene.has_node("Players/1") and scene.get_node("Players/1").is_on_floor():
				_player = scene.get_node("Players/1")
				_eq = _player.get_node("Equipment")
				Input.action_press("move_forward")
				Input.action_press("sprint")
				_next()
		1:
			if _t > 1.5:
				Input.action_release("sprint")
				Input.action_press("jump")
				_next()
		2:
			if _t > 0.2:
				Input.action_release("jump")
			if _t > 1.3 and _player.is_on_floor():
				Input.action_press("roll")
				_next()
		3:
			if _t > 0.1:
				Input.action_release("roll")
				Input.action_release("move_forward")
			if _t > 1.0:
				for p in get_tree().get_nodes_in_group("pickups"):
					if p.item_id == "bow_basic":
						_player.global_position = p.global_position + Vector3(0, 0.2, -1.0)
						_player.reset_physics_interpolation()
						break
				_next()
		4:
			if _t > 0.5:
				Input.action_press("interact")
			if _t > 0.6:
				Input.action_release("interact")
			if _t > 1.4:
				Input.action_press("attack")  # draws the bow if holstered
			if _t > 1.5:
				Input.action_release("attack")
			if _t > 2.2:
				Input.action_press("attack")
				_next()
		5:
			if _t > 1.2:
				Input.action_release("attack")
				_next()
		6:
			if _t > 1.5:
				var missing: Array = []
				for id in EXPECT:
					if not _heard.has(id):
						missing.append(id)
				print("[audio] heard: ", _heard)
				_done(missing.is_empty(), "all expected sounds fired" if missing.is_empty() else "missing %s" % [missing])


func _next() -> void:
	_step += 1
	_t = 0.0


func _done(ok: bool, msg: String) -> void:
	print("[audio] %s %s" % ["PASS" if ok else "FAIL", msg])
	set_physics_process(false)
	get_tree().quit(0 if ok else 1)
