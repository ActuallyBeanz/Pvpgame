extends Node
## Autoload: Lobby. Server-authoritative player roster + session flow
## (menu -> waiting room -> match). Clients only *request* changes; the host
## validates them and broadcasts the full roster.

signal roster_changed
signal match_started
signal all_peers_loaded

enum State { IDLE, WAITING, IN_MATCH }

const MENU_SCENE := "res://ui/main_menu.tscn"
const WAITING_SCENE := "res://ui/waiting_room.tscn"

var state: State = State.IDLE
const DEFAULT_MODEL := "player.adventurer.knight"
const MODEL_PREFIX := "player.adventurer."

## peer_id (int) -> { "name": String, "color": int, "ready": bool, "model": String }
var players: Dictionary = {}
## What this machine wants to be. Sent to the host on join / when edited.
## Remembered between launches in profile_path (name, color, character model).
var local_profile := { "name": "Player%03d" % randi_range(1, 999), "color": 0, "model": DEFAULT_MODEL }
var profile_path := "user://profile.cfg"

var _last_message := ""
var _loaded_peers: Dictionary = {}
var _all_loaded_sent := false


func _ready() -> void:
	load_profile()
	NetworkManager.hosted.connect(_on_hosted)
	NetworkManager.joined.connect(_on_joined)
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.session_ended.connect(_on_session_ended)


# --- Public API ---------------------------------------------------------------

func is_waiting() -> bool:
	return state == State.WAITING


func is_in_match() -> bool:
	return state == State.IN_MATCH


func local_entry() -> Dictionary:
	return players.get(multiplayer.get_unique_id(), {})


## Called by the Waiting Room UI whenever the local player edits their profile.
func submit_profile(display_name: String, color: int, is_ready: bool) -> void:
	local_profile.name = display_name
	local_profile.color = color
	var model := local_model()
	if multiplayer.is_server():
		_apply_profile(1, display_name, color, is_ready, model)
	else:
		rpc_update_profile.rpc_id(1, display_name, color, is_ready, model)


func local_model() -> String:
	return str(local_profile.get("model", DEFAULT_MODEL))


## Character models you can pick (registered in data/registry/models.tres).
func character_models() -> PackedStringArray:
	return AssetRegistry.ids_with_prefix(MODEL_PREFIX)


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", str(local_profile.get("name", "")))
	cfg.set_value("profile", "color", int(local_profile.get("color", 0)))
	cfg.set_value("profile", "model", local_model())
	cfg.save(profile_path)


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(profile_path) != OK:
		return
	var n := str(cfg.get_value("profile", "name", local_profile.name))
	if not n.strip_edges().is_empty():
		local_profile.name = n
	local_profile.color = int(cfg.get_value("profile", "color", local_profile.color))
	local_profile.model = _valid_model(str(cfg.get_value("profile", "model", DEFAULT_MODEL)))


func can_start() -> bool:
	if not NetworkManager.is_host() or state != State.WAITING:
		return false
	var s := GameConfig.settings
	if players.size() < s.min_players_to_start:
		return false
	if s.require_all_ready:
		for id: int in players:
			if id != 1 and not players[id].ready:  # host readies by pressing Start
				return false
	return true


func start_match() -> void:
	if can_start():
		rpc_start_match.rpc()


## Every peer calls this once its match scene is ready (spawners exist).
func report_match_loaded() -> void:
	if multiplayer.is_server():
		_mark_loaded(1)
	else:
		rpc_match_loaded.rpc_id(1)


## UI helper: returns and clears the last disconnect/kick message.
func consume_message() -> String:
	var m := _last_message
	_last_message = ""
	return m


# --- RPCs: client -> server ------------------------------------------------------

@rpc("any_peer", "reliable")
func rpc_register(display_name: String, color: int, model: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if state != State.WAITING:
		NetworkManager.kick(id)
		return
	players[id] = _make_entry(id, display_name, color, false, model)
	_broadcast_roster()


@rpc("any_peer", "reliable")
func rpc_update_profile(display_name: String, color: int, is_ready: bool, model: String) -> void:
	if multiplayer.is_server():
		_apply_profile(multiplayer.get_remote_sender_id(), display_name, color, is_ready, model)


@rpc("any_peer", "reliable")
func rpc_match_loaded() -> void:
	if multiplayer.is_server():
		_mark_loaded(multiplayer.get_remote_sender_id())


# --- RPCs: server -> clients ------------------------------------------------------

@rpc("authority", "reliable")
func rpc_sync_roster(roster: Dictionary) -> void:
	players = roster
	roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func rpc_start_match() -> void:
	state = State.IN_MATCH
	_loaded_peers.clear()
	_all_loaded_sent = false
	match_started.emit()
	get_tree().change_scene_to_file(GameConfig.settings.match_scene)


# --- Internals ---------------------------------------------------------------------

func _valid_model(model: String) -> String:
	return model if model.begins_with(MODEL_PREFIX) and AssetRegistry.has_model(model) else DEFAULT_MODEL


func _make_entry(id: int, display_name: String, color: int, is_ready: bool, model: String) -> Dictionary:
	var s := GameConfig.settings
	var clean := display_name.strip_edges().left(s.name_max_length)
	if clean.is_empty():
		clean = "Player%d" % id
	return {
		"name": clean,
		"color": clampi(color, 0, maxi(s.player_colors.size() - 1, 0)),
		"ready": is_ready,
		"model": _valid_model(model),
	}


func _apply_profile(id: int, display_name: String, color: int, is_ready: bool, model: String) -> void:
	if state != State.WAITING or not players.has(id):
		return
	players[id] = _make_entry(id, display_name, color, is_ready, model)
	_broadcast_roster()


func _broadcast_roster() -> void:
	roster_changed.emit()
	rpc_sync_roster.rpc(players)


func _mark_loaded(id: int) -> void:
	_loaded_peers[id] = true
	_check_all_loaded()


func _check_all_loaded() -> void:
	if _all_loaded_sent or state != State.IN_MATCH:
		return
	for id: int in players:
		if not _loaded_peers.has(id):
			return
	_all_loaded_sent = true
	all_peers_loaded.emit()


func _on_hosted() -> void:
	players.clear()
	players[1] = _make_entry(1, local_profile.name, local_profile.color, false, local_model())
	state = State.WAITING
	roster_changed.emit()
	get_tree().change_scene_to_file(WAITING_SCENE)


func _on_joined() -> void:
	state = State.WAITING
	rpc_register.rpc_id(1, local_profile.name, local_profile.color, local_model())
	get_tree().change_scene_to_file(WAITING_SCENE)


func _on_peer_connected(id: int) -> void:
	# Late joining isn't supported yet: refuse peers once the match is running.
	if multiplayer.is_server() and state == State.IN_MATCH:
		NetworkManager.kick(id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not players.has(id):
		return
	players.erase(id)
	_loaded_peers.erase(id)
	_broadcast_roster()
	_check_all_loaded()


func _on_session_ended(reason: String) -> void:
	players.clear()
	state = State.IDLE
	_last_message = reason
	roster_changed.emit()
	get_tree().change_scene_to_file(MENU_SCENE)
