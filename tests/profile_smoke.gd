extends Node
## Character picker + remembered profile: the main menu lists every adventurer, picking
## one saves it, it loads back on the next launch, and hosting spawns you as it.
## Uses user://profile_test.cfg so it never touches your real saved profile. PASS/FAIL.
##   godot --headless res://tests/profile_smoke.tscn

const PICK := "player.adventurer.rogue"

var _fails: PackedStringArray = []
var _t := 0.0
var _hosted := false


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Lobby.profile_path = "user://profile_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Lobby.profile_path))
	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	var ids: PackedStringArray = menu._model_ids
	print("[profile] menu lists %d characters: %s" % [menu.model_option.item_count, ", ".join(ids)])
	if menu.model_option.item_count != 5:
		_fail("expected 5 adventurers in the picker")
	var i := ids.find(PICK)
	menu.model_option.select(i)
	menu._on_model_selected(i)
	await get_tree().process_frame
	var shown: Node = menu.model_spot.get_child(menu.model_spot.get_child_count() - 1)
	print("[profile] picked %s, preview shows %s, saved file: %s" % [Lobby.local_model(), shown.name, FileAccess.file_exists(Lobby.profile_path)])
	if Lobby.local_model() != PICK or not FileAccess.file_exists(Lobby.profile_path):
		_fail("pick not saved")
	menu.queue_free()
	# "next launch": wipe memory, load from disk
	Lobby.local_profile = { "name": "Fresh", "color": 0, "model": Lobby.DEFAULT_MODEL }
	Lobby.load_profile()
	print("[profile] after reload: model %s" % Lobby.local_model())
	if Lobby.local_model() != PICK:
		_fail("choice not remembered")
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()
	_hosted = true


func _physics_process(delta: float) -> void:
	if get_tree().current_scene == self or not _hosted:
		return
	_t += delta
	var scene := get_tree().current_scene
	if scene and scene.has_node("Players/1"):
		var p: Node = scene.get_node("Players/1")
		var model: Node = p.model_root.get_child(0)
		print("[profile] spawned as %s (model node %s), roster says %s" % [p.model_id, model.name, Lobby.players[1].model])
		if p.model_id != PICK or Lobby.players[1].model != PICK:
			_fail("spawned with the wrong character")
		_finish()
	elif _t > 10.0:
		_fail("never spawned")
		_finish()


func _fail(msg: String) -> void:
	print("[profile] problem: " + msg)
	_fails.append(msg)


func _finish() -> void:
	var ok := _fails.is_empty()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Lobby.profile_path))
	print("[profile] %s %s" % ["PASS" if ok else "FAIL", "character pick remembered + used" if ok else ", ".join(_fails)])
	set_physics_process(false)
	get_tree().quit(0 if ok else 1)
