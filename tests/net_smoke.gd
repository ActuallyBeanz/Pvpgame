extends Node
## Headless smoke test: menu -> waiting room -> match with 2 peers.
## Run two terminals (Godot 4.7 console exe):
##   godot --headless res://tests/net_smoke.tscn -- host
##   godot --headless res://tests/net_smoke.tscn -- join
## Each prints PASS/FAIL and exits. Not part of the game.

const TIMEOUT_SEC := 25.0

var _role := "join"
var _elapsed := 0.0


func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		# Re-parent a copy under /root so it survives Lobby's scene changes.
		var driver: Node = get_script().new()
		driver.name = "SmokeDriver"
		get_tree().root.add_child.call_deferred(driver)
		return
	_role = "host" if "host" in OS.get_cmdline_user_args() else "join"
	Lobby.local_profile = { "name": "Smoke_" + _role, "color": 0 if _role == "host" else 2 }
	Lobby.roster_changed.connect(_on_roster)
	NetworkManager.join_failed.connect(func(r: String) -> void: _finish(false, "join failed: " + r))
	var err := NetworkManager.host() if _role == "host" else NetworkManager.join("127.0.0.1")
	if err != OK:
		_finish(false, "network error %s" % error_string(err))


func _on_roster() -> void:
	if not Lobby.is_waiting():
		return
	var me := Lobby.local_entry()
	if not me.is_empty() and not me.ready:
		Lobby.submit_profile(Lobby.local_profile.name, Lobby.local_profile.color, true)
	if _role == "host" and Lobby.players.size() >= 2 and Lobby.can_start():
		Lobby.start_match.call_deferred()


func _process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_elapsed += delta
	var scene := get_tree().current_scene
	if scene and scene.has_node("Players"):
		var bodies := scene.get_node("Players").get_children()
		if bodies.size() >= 2:
			var names := bodies.map(func(n: Node) -> String: return "%s=%s" % [n.name, n.get_node("NameTag").text])
			_finish(true, "players spawned: %s" % ", ".join(names))
			return
	if _elapsed > TIMEOUT_SEC:
		_finish(false, "timeout. state=%s roster=%s" % [Lobby.state, Lobby.players])


func _finish(ok: bool, msg: String) -> void:
	print("[%s] %s %s" % [_role, "PASS" if ok else "FAIL", msg])
	set_process(false)
	# Give the host a moment so the client also sees its spawns before we close.
	await get_tree().create_timer(1.5).timeout
	get_tree().quit(0 if ok else 1)
