extends Node
class_name NetworkWorldStateReplicator

signal delta_applied(sequence: int, kind: String, stable_id: String)
signal delta_rejected(sequence: int, reason: String)

const DELTA_PROTOCOL: int = 1
const ALLOWED_KINDS := {
	"flag": true,
	"entity": true,
	"discovery": true,
	"region": true,
	"world": true
}

var network_session: Node
var world_state: Node
var send_sequence: int = 0
var last_received_sequence: int = 0
var applying_remote_delta: bool = false

func _ready() -> void:
	add_to_group("network_world_state_replicator")
	call_deferred("_install")

func _install() -> void:
	_resolve_dependencies()
	if world_state != null and world_state.has_signal("state_changed"):
		var callback := Callable(self, "_on_world_state_changed")
		if not world_state.is_connected("state_changed", callback):
			world_state.connect("state_changed", callback)

func build_delta(kind: String, stable_id: String, sequence: int = -1) -> Dictionary:
	_resolve_dependencies()
	if world_state == null or not ALLOWED_KINDS.has(kind):
		return {}
	var payload: Variant = null
	match kind:
		"flag":
			payload = world_state.call("get_flag", stable_id, null)
		"entity":
			payload = world_state.call("get_entity_state", stable_id)
		"discovery":
			payload = world_state.call("is_region_discovered", stable_id) == true
		"region":
			payload = str(world_state.get("current_region_id"))
		"world":
			if stable_id == "reset" or stable_id == "restore":
				payload = world_state.call("snapshot")
			else:
				return {}
	var final_sequence: int = sequence
	if final_sequence < 0:
		send_sequence += 1
		final_sequence = send_sequence
	return {
		"protocol": DELTA_PROTOCOL,
		"sequence": final_sequence,
		"kind": kind,
		"stable_id": stable_id,
		"payload": payload
	}

func apply_delta(delta: Dictionary) -> Dictionary:
	_resolve_dependencies()
	var validation: Dictionary = validate_delta(delta)
	if validation.get("ok", false) != true:
		var rejected_sequence: int = int(delta.get("sequence", 0))
		delta_rejected.emit(rejected_sequence, str(validation.get("error", "invalid_delta")))
		return validation
	var sequence: int = int(delta.get("sequence", 0))
	var kind: String = str(delta.get("kind", ""))
	var stable_id: String = str(delta.get("stable_id", ""))
	var payload: Variant = delta.get("payload", null)
	applying_remote_delta = true
	match kind:
		"flag":
			world_state.call("set_flag", stable_id, payload)
		"entity":
			world_state.call("set_entity_state", stable_id, (payload as Dictionary).duplicate(true))
		"discovery":
			if payload == true:
				world_state.call("mark_region_discovered", stable_id)
		"region":
			world_state.call("set_current_region", str(payload))
		"world":
			world_state.call("restore_snapshot", (payload as Dictionary).duplicate(true))
	applying_remote_delta = false
	last_received_sequence = sequence
	delta_applied.emit(sequence, kind, stable_id)
	return {"ok": true, "sequence": sequence, "kind": kind, "stable_id": stable_id}

func validate_delta(delta: Dictionary) -> Dictionary:
	if int(delta.get("protocol", 0)) != DELTA_PROTOCOL:
		return {"ok": false, "error": "unsupported_protocol"}
	var sequence: int = int(delta.get("sequence", 0))
	if sequence <= 0:
		return {"ok": false, "error": "invalid_sequence"}
	if sequence <= last_received_sequence:
		return {"ok": false, "error": "stale_sequence"}
	var kind: String = str(delta.get("kind", ""))
	if not ALLOWED_KINDS.has(kind):
		return {"ok": false, "error": "kind_not_allowed"}
	var stable_id: String = str(delta.get("stable_id", ""))
	if stable_id.is_empty():
		return {"ok": false, "error": "missing_stable_id"}
	var payload: Variant = delta.get("payload", null)
	if kind == "entity" and not payload is Dictionary:
		return {"ok": false, "error": "invalid_entity_payload"}
	if kind == "discovery" and not payload is bool:
		return {"ok": false, "error": "invalid_discovery_payload"}
	if kind == "region" and not payload is String:
		return {"ok": false, "error": "invalid_region_payload"}
	if kind == "world" and not payload is Dictionary:
		return {"ok": false, "error": "invalid_world_payload"}
	return {"ok": true}

func reset_receive_sequence() -> void:
	last_received_sequence = 0

func _on_world_state_changed(kind: String, stable_id: String) -> void:
	if applying_remote_delta:
		return
	_resolve_dependencies()
	if network_session == null or network_session.call("is_server_authority") != true:
		return
	# Singleplayer uses the same authoritative state path but does not need RPC.
	if str(network_session.get("session_mode")) != "host":
		return
	var delta: Dictionary = build_delta(kind, stable_id)
	if delta.is_empty():
		return
	_broadcast_delta.rpc(delta)

func _resolve_dependencies() -> void:
	if world_state == null:
		world_state = get_node_or_null("/root/WorldState")
	if is_instance_valid(network_session):
		return
	var parent := get_parent()
	if parent != null:
		network_session = parent.get_node_or_null("NetworkSession")

@rpc("authority", "call_remote", "reliable")
func _broadcast_delta(delta: Dictionary) -> void:
	apply_delta(delta)
