extends Node
class_name NetworkEnemyManager

signal enemy_state_applied(stable_id: String, state: Dictionary)

const ENEMY_PROTOCOL: int = 1
const SEND_INTERVAL: float = 0.12
const MAX_BATCH_SIZE: int = 128

var network_session: Node
var send_elapsed: float = 0.0
var send_sequence: int = 0
var last_received_sequence: int = 0

func _ready() -> void:
	add_to_group("network_enemy_manager")
	call_deferred("_resolve_session")

func _process(delta: float) -> void:
	_resolve_session()
	if network_session == null or network_session.get("connected") != true:
		return
	if network_session.call("is_server_authority") != true or str(network_session.get("session_mode")) != "host":
		return
	send_elapsed += delta
	if send_elapsed < SEND_INTERVAL:
		return
	send_elapsed = 0.0
	var batch: Dictionary = build_enemy_batch()
	if not (batch.get("states", []) as Array).is_empty():
		_replicate_enemy_batch.rpc(batch)

func build_enemy_batch() -> Dictionary:
	send_sequence += 1
	var states: Array[Dictionary] = []
	var tree: SceneTree = get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group("enemy"):
			if states.size() >= MAX_BATCH_SIZE:
				break
			if not node is Node3D or not is_instance_valid(node):
				continue
			var state: Dictionary = build_enemy_state(node as Node3D)
			if not state.is_empty():
				states.append(state)
	return {
		"protocol": ENEMY_PROTOCOL,
		"sequence": send_sequence,
		"states": states
	}

func build_enemy_state(enemy: Node3D) -> Dictionary:
	var persistent_value: Variant = enemy.get("persistent_id")
	if persistent_value == null:
		return {}
	var stable_id: String = str(persistent_value)
	if stable_id.is_empty():
		return {}
	return {
		"id": stable_id,
		"position": enemy.global_position,
		"rotation_y": enemy.rotation.y,
		"health": max(0, int(enemy.get("health"))),
		"dead": enemy.get("dead") == true
	}

func apply_enemy_batch(batch: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_enemy_batch(batch)
	if validation.get("ok", false) != true:
		return validation
	var sequence: int = int(batch.get("sequence", 0))
	var states: Array = batch.get("states", []) as Array
	var applied: int = 0
	for value in states:
		if not value is Dictionary:
			continue
		var state: Dictionary = value as Dictionary
		var stable_id: String = str(state.get("id", ""))
		var enemy: Node = _find_enemy(stable_id)
		if enemy == null:
			continue
		if state.get("dead", false) == true:
			enemy.queue_free()
		else:
			var position_value: Variant = state.get("position", null)
			if position_value is Vector3 and enemy is Node3D:
				(enemy as Node3D).global_position = position_value as Vector3
				(enemy as Node3D).rotation.y = float(state.get("rotation_y", (enemy as Node3D).rotation.y))
			enemy.set("health", max(0, int(state.get("health", enemy.get("health")))))
		enemy_state_applied.emit(stable_id, state.duplicate(true))
		applied += 1
	last_received_sequence = sequence
	return {"ok": true, "sequence": sequence, "applied": applied}

func validate_enemy_batch(batch: Dictionary) -> Dictionary:
	if int(batch.get("protocol", 0)) != ENEMY_PROTOCOL:
		return {"ok": false, "error": "unsupported_protocol"}
	var sequence: int = int(batch.get("sequence", 0))
	if sequence <= 0:
		return {"ok": false, "error": "invalid_sequence"}
	if sequence <= last_received_sequence:
		return {"ok": false, "error": "stale_sequence"}
	var states_value: Variant = batch.get("states", null)
	if not states_value is Array:
		return {"ok": false, "error": "invalid_states"}
	if (states_value as Array).size() > MAX_BATCH_SIZE:
		return {"ok": false, "error": "batch_too_large"}
	for value in states_value as Array:
		if not value is Dictionary:
			return {"ok": false, "error": "invalid_enemy_state"}
		var state: Dictionary = value as Dictionary
		if str(state.get("id", "")).is_empty() or not state.get("position", null) is Vector3:
			return {"ok": false, "error": "invalid_enemy_state"}
	return {"ok": true}

func is_client_replica() -> bool:
	_resolve_session()
	return network_session != null and str(network_session.get("session_mode")) == "client"

func _find_enemy(stable_id: String) -> Node:
	if stable_id.is_empty() or get_tree() == null:
		return null
	for node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(node):
			continue
		var persistent_value: Variant = node.get("persistent_id")
		if persistent_value != null and str(persistent_value) == stable_id:
			return node
	return null

func _resolve_session() -> void:
	if is_instance_valid(network_session):
		return
	var parent := get_parent()
	if parent != null:
		network_session = parent.get_node_or_null("NetworkSession")

@rpc("authority", "call_remote", "unreliable_ordered")
func _replicate_enemy_batch(batch: Dictionary) -> void:
	apply_enemy_batch(batch)
