extends Node
## Two-peer check that Reactive props stay in sync:
## the CLIENT shatters ice Yard_5 (2 blunt hits) and lights crate Yard_1 with a fire hit;
## both peers must see Yard_5 gone and Yard_1 burning.
##   godot --headless res://tests/net_reactions_smoke.tscn -- host
##   godot --headless res://tests/net_reactions_smoke.tscn -- join

const TIMEOUT_SEC := 30.0

var _role := "join"
var _elapsed := 0.0
var _sent := false


func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		var driver: Node = get_script().new()
		driver.name = "SmokeDriver"
		get_tree().root.add_child.call_deferred(driver)
		return
	_role = "host" if "host" in OS.get_cmdline_user_args() else "join"
	Lobby.local_profile = { "name": "Net_" + _role, "color": 0 if _role == "host" else 2 }
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
	if _elapsed > TIMEOUT_SEC:
		_finish(false, "timeout (sent=%s)" % _sent)
		return
	var scene := get_tree().current_scene
	if scene == null or not scene.has_node("Players") or scene.get_node("Players").get_child_count() < 2:
		return
	if _role == "join" and not _sent:
		_sent = true
		var ice: Node = scene.get_node("Props/Yard_5/Reactive")
		ice.receive_hit(WorldRules.make_hit(6.0, "blunt"), false)
		ice.receive_hit(WorldRules.make_hit(6.0, "blunt"), false)
		scene.get_node("Props/Yard_1/Reactive").receive_hit(WorldRules.make_hit(0.0, "", "fire"), false)
		print("[net-react] client sent hits")
	var crate := scene.get_node_or_null("Props/Yard_1/Reactive")
	var ice := scene.get_node_or_null("Props/Yard_5")
	if (ice == null or not ice.visible) and crate and crate.burning:
		_finish(true, "%s sees ice shattered + crate burning" % _role)


func _finish(ok: bool, msg: String) -> void:
	print("[net-react] %s %s" % ["PASS" if ok else "FAIL", msg])
	set_process(false)
	# give the host a moment so the client's last packets aren't cut off
	get_tree().create_timer(1.0 if _role == "host" else 0.2).timeout.connect(func() -> void:
		get_tree().quit(0 if ok else 1))
