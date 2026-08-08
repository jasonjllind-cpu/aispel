extends Node
class_name NetworkSession

signal session_started(mode: String)
signal session_stopped()
signal peer_joined(peer_id: int, player_id: String)
signal peer_left(peer_id: int, player_id: String)
signal bootstrap_received(world_seed: int)

const DEFAULT_PORT: int = 27144
const DEFAULT_MAX_PLAYERS: int = 4
const MIN_PLAYERS: int = 1
const MAX_PLAYERS: int = 4

var world_state: Node
var session_mode: String = "singleplayer"
var listen_port: int = DEFAULT_PORT
var max_players: int = DEFAULT_MAX_PLAYERS
var peer_players: Dictionary = {}
var connected: bool = false

func _ready() -> void:
	add_to_group("network_session")
	world_state = get_node_or_null("/root/WorldState")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func start_singleplayer() -> Dictionary:
	stop_session()
	session_mode = "singleplayer"
	connected = true
	_register_peer(1)
	session_started.emit(session_mode)
	return {"ok": true, "mode": session_mode, "peer_id": 1}

func host_game(port: int = DEFAULT_PORT, requested_max_players: int = DEFAULT_MAX_PLAYERS) -> Dictionary:
	stop_session()
	listen_port = clampi(port, 1, 65535)
	max_players = clampi(requested_max_players, MIN_PLAYERS, MAX_PLAYERS)
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(listen_port, max_players - 1)
	if error != OK:
		return {"ok": false, "error": "host_failed", "code": error}
	multiplayer.multiplayer_peer = peer
	session_mode = "host"
	connected = true
	_register_peer(multiplayer.get_unique_id())
	session_started.emit(session_mode)
	return {
		"ok": true,
		"mode": session_mode,
		"peer_id": multiplayer.get_unique_id(),
		"port": listen_port,
		"max_players": max_players
	}

func join_game(address: String, port: int = DEFAULT_PORT) -> Dictionary:
	stop_session()
	var host: String = address.strip_edges()
	if host.is_empty():
		host = "127.0.0.1"
	listen_port = clampi(port, 1, 65535)
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(host, listen_port)
	if error != OK:
		return {"ok": false, "error": "join_failed", "code": error}
	multiplayer.multiplayer_peer = peer
	session_mode = "client"
	connected = false
	session_started.emit(session_mode)
	return {"ok": true, "mode": session_mode, "address": host, "port": listen_port}

func stop_session() -> void:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer_players.clear()
	connected = false
	session_mode = "singleplayer"
	session_stopped.emit()

func is_server_authority() -> bool:
	return session_mode == "singleplayer" or multiplayer.is_server()

func local_peer_id() -> int:
	if session_mode == "singleplayer":
		return 1
	return multiplayer.get_unique_id()

func stable_player_id(peer_id: int) -> String:
	return "player:peer:%d" % max(1, peer_id)

func register_peer_for_test(peer_id: int) -> Dictionary:
	return _register_peer(peer_id)

func unregister_peer_for_test(peer_id: int) -> String:
	return _unregister_peer(peer_id)

func peer_record(peer_id: int) -> Dictionary:
	var value: Variant = peer_players.get(peer_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func build_bootstrap_payload() -> Dictionary:
	var snapshot: Dictionary = {}
	var seed: int = 0
	if world_state != null:
		seed = int(world_state.get("world_seed"))
		if world_state.has_method("snapshot"):
			var snapshot_value: Variant = world_state.call("snapshot")
			if snapshot_value is Dictionary:
				snapshot = (snapshot_value as Dictionary).duplicate(true)
	return {
		"protocol": 1,
		"world_seed": seed,
		"world_state": snapshot,
		"players": peer_players.duplicate(true)
	}

func apply_bootstrap_payload(payload: Dictionary) -> bool:
	if int(payload.get("protocol", 0)) != 1:
		return false
	if world_state == null:
		world_state = get_node_or_null("/root/WorldState")
	var snapshot_value: Variant = payload.get("world_state", {})
	if world_state != null and world_state.has_method("restore_snapshot") and snapshot_value is Dictionary:
		world_state.call("restore_snapshot", snapshot_value as Dictionary)
	var players_value: Variant = payload.get("players", {})
	peer_players = (players_value as Dictionary).duplicate(true) if players_value is Dictionary else {}
	bootstrap_received.emit(int(payload.get("world_seed", 0)))
	return true

func _register_peer(peer_id: int) -> Dictionary:
	var safe_peer_id: int = max(1, peer_id)
	var record := {
		"peer_id": safe_peer_id,
		"player_id": stable_player_id(safe_peer_id),
		"authority_peer_id": safe_peer_id,
		"connected": true
	}
	peer_players[safe_peer_id] = record
	peer_joined.emit(safe_peer_id, str(record["player_id"]))
	return record.duplicate(true)

func _unregister_peer(peer_id: int) -> String:
	var record: Dictionary = peer_record(peer_id)
	var player_id: String = str(record.get("player_id", stable_player_id(peer_id)))
	peer_players.erase(peer_id)
	peer_left.emit(peer_id, player_id)
	return player_id

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_register_peer(peer_id)
	_send_bootstrap.rpc_id(peer_id, build_bootstrap_payload())

func _on_peer_disconnected(peer_id: int) -> void:
	_unregister_peer(peer_id)

func _on_connected_to_server() -> void:
	connected = true
	_register_peer(multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	connected = false

func _on_server_disconnected() -> void:
	peer_players.clear()
	connected = false

@rpc("authority", "call_remote", "reliable")
func _send_bootstrap(payload: Dictionary) -> void:
	apply_bootstrap_payload(payload)
