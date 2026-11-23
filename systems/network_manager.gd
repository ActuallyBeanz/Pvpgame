extends Node
## Autoload: NetworkManager. Owns the ENet peer. Knows nothing about players or UI.

signal hosted
signal joined
signal join_failed(reason: String)
signal session_ended(reason: String)
signal peer_connected(id: int)
signal peer_disconnected(id: int)

var _join_attempt := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int) -> void: peer_connected.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: peer_disconnected.emit(id))
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int = -1) -> Error:
	var s := GameConfig.settings
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port if port > 0 else s.port, s.max_players - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	hosted.emit()
	return OK


func join(address: String, port: int = -1) -> Error:
	var s := GameConfig.settings
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port if port > 0 else s.port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_join_attempt += 1
	var attempt := _join_attempt
	get_tree().create_timer(s.join_timeout_sec).timeout.connect(func() -> void:
		if attempt == _join_attempt and is_connecting():
			_reset()
			join_failed.emit("Timed out reaching host."))
	return OK


## Leave the session (host closes it for everyone).
func leave(reason: String = "") -> void:
	_reset()
	session_ended.emit(reason)


func kick(id: int) -> void:
	if is_host():
		multiplayer.multiplayer_peer.disconnect_peer(id)


func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_connecting() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func _reset() -> void:
	_join_attempt += 1
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _on_connected() -> void:
	_join_attempt += 1
	joined.emit()


func _on_connection_failed() -> void:
	_reset()
	join_failed.emit("Could not reach host.")


func _on_server_disconnected() -> void:
	_reset()
	session_ended.emit("Disconnected from host.")
