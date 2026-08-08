extends Node
class_name NetworkCombatAuthority

signal attack_applied(peer_id: int, target_id: String, damage: int, target_health: int)
signal attack_rejected(peer_id: int, target_id: String, reason: String)

const MAX_ATTACK_DISTANCE: float = 4.2
const MIN_ATTACK_INTERVAL_MSEC: int = 320
const SERVER_ATTACK_DAMAGE: int = 16

var network_session: Node
var command_router: Node
var player_manager: Node
var world_state: Node
var world_replicator: Node
var last_attack_msec_by_peer: Dictionary = {}

func _ready() -> void:
	add_to_group("network_combat_authority")
	call_deferred("_install")

func _install() -> void:
	_resolve_dependencies()
	if command_router != null and command_router.has_signal("authoritative_command"):
		var callback := Callable(self, "_on_authoritative_command")
		if not command_router.is_connected("authoritative_command", callback):
			command_router.connect("authoritative_command", callback)
	if world_replicator != null and world_replicator.has_signal("delta_applied"):
		var delta_callback := Callable(self, "_on_world_delta_applied")
		if not world_replicator.is_connected("delta_applied", delta_callback):
			world_replicator.connect("delta_applied", delta_callback)

func _unhandled_input(event: InputEvent) -> void:
	_resolve_dependencies()
	if network_session == null or str(network_session.get("session_mode")) != "client":
		return
	if not event.is_action_pressed("attack"):
		return
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty() or not players[0] is Node3D:
		return
	var target_id: String = _nearest_attack_target_id(players[0] as Node3D)
	if not target_id.is_empty():
		request_local_attack(target_id)

func request_local_attack(target_id: String) -> Dictionary:
	_resolve_dependencies()
	if target_id.is_empty():
		return {"ok": false, "error": "missing_target"}
	if network_session == null or command_router == null:
		return {"ok": false, "error": "network_not_ready"}
	var peer_id: int = int(network_session.call("local_peer_id"))
	if str(network_session.get("session_mode")) == "singleplayer":
		return execute_attack(peer_id, target_id)
	if network_session.call("is_server_authority") == true:
		var sequence: int = int(command_router.get("last_sequence_by_peer").get(peer_id, 0)) + 1
		return command_router.call("process_command", peer_id, {
			"protocol": 1,
			"sequence": sequence,
			"action": "attack",
			"payload": {"target_id": target_id}
		})
	var local_sequence: int = int(command_router.get("local_sequence")) + 1
	command_router.set("local_sequence", local_sequence)
	command_router.rpc_id(1, "_submit_command", {
		"protocol": 1,
		"sequence": local_sequence,
		"action": "attack",
		"payload": {"target_id": target_id}
	})
	return {"ok": true, "submitted": true, "sequence": local_sequence}

func execute_attack(peer_id: int, target_id: String) -> Dictionary:
	_resolve_dependencies()
	if target_id.is_empty():
		return _reject(peer_id, target_id, "missing_target")
	var target: Node = _find_enemy(target_id)
	if target == null:
		return _reject(peer_id, target_id, "target_not_found")
	var player_position_value: Variant = _player_position(peer_id)
	if not player_position_value is Vector3:
		return _reject(peer_id, target_id, "player_state_missing")
	var player_position: Vector3 = player_position_value as Vector3
	if not target is Node3D:
		return _reject(peer_id, target_id, "target_not_spatial")
	var distance: float = player_position.distance_to((target as Node3D).global_position)
	if distance > MAX_ATTACK_DISTANCE:
		return _reject(peer_id, target_id, "target_out_of_range")
	var now_msec: int = Time.get_ticks_msec()
	var previous_msec: int = int(last_attack_msec_by_peer.get(peer_id, -MIN_ATTACK_INTERVAL_MSEC))
	if now_msec - previous_msec < MIN_ATTACK_INTERVAL_MSEC:
		return _reject(peer_id, target_id, "attack_cooldown")
	last_attack_msec_by_peer[peer_id] = now_msec
	if not target.has_method("receive_damage"):
		return _reject(peer_id, target_id, "target_not_damageable")
	target.call("receive_damage", SERVER_ATTACK_DAMAGE, null)
	var target_health: int = max(0, int(target.get("health")))
	var dead: bool = target.get("dead") == true or target_health <= 0
	if world_state != null and world_state.has_method("set_entity_state"):
		world_state.call("set_entity_state", target_id, {
			"dead": dead,
			"health": target_health
		})
	attack_applied.emit(peer_id, target_id, SERVER_ATTACK_DAMAGE, target_health)
	return {
		"ok": true,
		"peer_id": peer_id,
		"target_id": target_id,
		"damage": SERVER_ATTACK_DAMAGE,
		"target_health": target_health,
		"dead": dead
	}

func _nearest_attack_target_id(player: Node3D) -> String:
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best_id := ""
	var best_distance: float = MAX_ATTACK_DISTANCE
	for node in get_tree().get_nodes_in_group("enemy"):
		if not node is Node3D or not is_instance_valid(node):
			continue
		var stable_value: Variant = node.get("persistent_id")
		if stable_value == null or str(stable_value).is_empty():
			continue
		var offset: Vector3 = (node as Node3D).global_position - player.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= 0.01 or distance > best_distance:
			continue
		if forward.dot(offset.normalized()) < 0.20:
			continue
		best_distance = distance
		best_id = str(stable_value)
	return best_id

func _on_authoritative_command(peer_id: int, action: String, payload: Dictionary) -> void:
	if action != "attack":
		return
	execute_attack(peer_id, str(payload.get("target_id", "")))

func _on_world_delta_applied(_sequence: int, kind: String, stable_id: String) -> void:
	if kind != "entity" or world_state == null:
		return
	var target: Node = _find_enemy(stable_id)
	if target == null:
		return
	var state: Dictionary = world_state.call("get_entity_state", stable_id)
	if state.get("dead", false) == true:
		target.queue_free()
		return
	if state.has("health"):
		target.set("health", max(0, int(state.get("health", target.get("health")))))

func _player_position(peer_id: int) -> Variant:
	if player_manager != null and player_manager.has_method("state_for_peer"):
		var state: Dictionary = player_manager.call("state_for_peer", peer_id)
		var value: Variant = state.get("position", null)
		if value is Vector3:
			return value
	if network_session != null and peer_id == int(network_session.call("local_peer_id")):
		var players: Array[Node] = get_tree().get_nodes_in_group("player")
		if not players.is_empty() and players[0] is Node3D:
			return (players[0] as Node3D).global_position
	return null

func _find_enemy(stable_id: String) -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(node):
			continue
		var value: Variant = node.get("persistent_id")
		if value != null and str(value) == stable_id:
			return node
	return null

func _reject(peer_id: int, target_id: String, reason: String) -> Dictionary:
	attack_rejected.emit(peer_id, target_id, reason)
	return {"ok": false, "error": reason, "peer_id": peer_id, "target_id": target_id}

func _resolve_dependencies() -> void:
	if world_state == null:
		world_state = get_node_or_null("/root/WorldState")
	var parent := get_parent()
	if parent == null:
		return
	if not is_instance_valid(network_session):
		network_session = parent.get_node_or_null("NetworkSession")
	if not is_instance_valid(command_router):
		command_router = parent.get_node_or_null("NetworkCommandRouter")
	if not is_instance_valid(player_manager):
		player_manager = parent.get_node_or_null("NetworkPlayerManager")
	if not is_instance_valid(world_replicator):
		world_replicator = parent.get_node_or_null("NetworkWorldStateReplicator")
