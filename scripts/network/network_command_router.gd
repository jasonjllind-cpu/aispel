extends Node
class_name NetworkCommandRouter

signal authoritative_command(peer_id: int, player_id: String, action: String, payload: Dictionary)
signal command_rejected(peer_id: int, action: String, reason: String)

const COMMAND_PROTOCOL: int = 1
const MAX_SEQUENCE_JUMP: int = 4096
const ALLOWED_ACTIONS := {
	"interact": true,
	"attack": true,
	"equip": true,
	"enter_dungeon": true,
	"exit_dungeon": true
}

var network_session: Node
var last_sequence_by_peer: Dictionary = {}
var local_sequence: int = 0

func _ready() -> void:
	add_to_group("network_command_router")
	call_deferred("_resolve_session")

func _resolve_session() -> void:
	if is_instance_valid(network_session):
		return
	var parent := get_parent()
	if parent != null:
		network_session = parent.get_node_or_null("NetworkSession")

func make_command(action: String, payload: Dictionary = {}) -> Dictionary:
	local_sequence += 1
	return {
		"protocol": COMMAND_PROTOCOL,
		"sequence": local_sequence,
		"action": action,
		"payload": payload.duplicate(true)
	}

func send_command(action: String, payload: Dictionary = {}) -> Dictionary:
	_resolve_session()
	var command: Dictionary = make_command(action, payload)
	if network_session == null:
		return {"ok": false, "error": "network_session_missing"}
	if network_session.call("is_server_authority") == true:
		return process_command(int(network_session.call("local_peer_id")), command)
	_submit_command.rpc_id(1, command)
	return {"ok": true, "queued": true, "sequence": int(command["sequence"])}

func process_command(peer_id: int, command: Dictionary) -> Dictionary:
	_resolve_session()
	var validation: Dictionary = validate_command(peer_id, command)
	if validation.get("ok", false) != true:
		command_rejected.emit(peer_id, str(command.get("action", "")), str(validation.get("error", "invalid_command")))
		return validation
	var sequence: int = int(command.get("sequence", 0))
	last_sequence_by_peer[peer_id] = sequence
	var record: Dictionary = network_session.call("peer_record", peer_id) if network_session != null else {}
	var player_id: String = str(record.get("player_id", "player:peer:%d" % peer_id))
	var action: String = str(command.get("action", ""))
	var payload_value: Variant = command.get("payload", {})
	var payload: Dictionary = (payload_value as Dictionary).duplicate(true) if payload_value is Dictionary else {}
	authoritative_command.emit(peer_id, player_id, action, payload)
	return {"ok": true, "peer_id": peer_id, "player_id": player_id, "sequence": sequence, "action": action}

func validate_command(peer_id: int, command: Dictionary) -> Dictionary:
	if peer_id <= 0:
		return {"ok": false, "error": "invalid_peer"}
	if int(command.get("protocol", 0)) != COMMAND_PROTOCOL:
		return {"ok": false, "error": "unsupported_protocol"}
	var action: String = str(command.get("action", ""))
	if not ALLOWED_ACTIONS.has(action):
		return {"ok": false, "error": "action_not_allowed"}
	var payload_value: Variant = command.get("payload", {})
	if not payload_value is Dictionary:
		return {"ok": false, "error": "invalid_payload"}
	var sequence: int = int(command.get("sequence", 0))
	var previous: int = int(last_sequence_by_peer.get(peer_id, 0))
	if sequence <= previous:
		return {"ok": false, "error": "stale_sequence"}
	if previous > 0 and sequence - previous > MAX_SEQUENCE_JUMP:
		return {"ok": false, "error": "sequence_jump"}
	if network_session != null:
		var record: Dictionary = network_session.call("peer_record", peer_id)
		if record.is_empty():
			return {"ok": false, "error": "unknown_peer"}
	return {"ok": true}

func clear_peer(peer_id: int) -> void:
	last_sequence_by_peer.erase(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _submit_command(command: Dictionary) -> void:
	_resolve_session()
	if network_session == null or network_session.call("is_server_authority") != true:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	process_command(sender_id, command)
