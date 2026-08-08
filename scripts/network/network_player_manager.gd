extends Node
class_name NetworkPlayerManager

signal player_state_accepted(peer_id: int, state: Dictionary)
signal player_state_rejected(peer_id: int, reason: String)

const STATE_PROTOCOL: int = 1
const SEND_INTERVAL: float = 0.10
const MAX_WORLD_COORDINATE: float = 50000.0
const MAX_SNAPSHOT_STEP_DISTANCE: float = 6.0

var network_session: Node
var local_player: Node3D
var player_states: Dictionary = {}
var last_sequence_by_peer: Dictionary = {}
var local_sequence: int = 0
var send_elapsed: float = 0.0
var remote_proxies: Dictionary = {}

func _ready() -> void:
	add_to_group("network_player_manager")
	call_deferred("_install")

func _install() -> void:
	_resolve_session()
	local_player = _find_local_player()
	if network_session != null:
		if network_session.has_signal("peer_joined"):
			network_session.connect("peer_joined", Callable(self, "_on_peer_joined"))
		if network_session.has_signal("peer_left"):
			network_session.connect("peer_left", Callable(self, "_on_peer_left"))
		for peer_id_value in (network_session.get("peer_players") as Dictionary).keys():
			_on_peer_joined(int(peer_id_value), str(network_session.call("stable_player_id", int(peer_id_value))))

func _process(delta: float) -> void:
	_resolve_session()
	if network_session == null:
		return
	if local_player == null or not is_instance_valid(local_player):
		local_player = _find_local_player()
	_update_remote_proxies(delta)
	if local_player == null or network_session.get("connected") != true:
		return
	send_elapsed += delta
	if send_elapsed < SEND_INTERVAL:
		return
	send_elapsed = 0.0
	local_sequence += 1
	var peer_id: int = int(network_session.call("local_peer_id"))
	var state: Dictionary = build_player_state(peer_id, local_player, local_sequence)
	if network_session.call("is_server_authority") == true:
		var result: Dictionary = accept_player_state(peer_id, state)
		if result.get("ok", false) and str(network_session.get("session_mode")) == "host":
			_replicate_player_state.rpc(state)
	else:
		_submit_player_state.rpc_id(1, state)

func build_player_state(peer_id: int, player: Node3D, sequence: int) -> Dictionary:
	var player_id: String = "player:peer:%d" % max(1, peer_id)
	if network_session != null and network_session.has_method("stable_player_id"):
		player_id = str(network_session.call("stable_player_id", peer_id))
	var health: int = 0
	var health_value: Variant = player.get("health")
	if health_value != null:
		health = int(health_value)
	return {
		"protocol": STATE_PROTOCOL,
		"peer_id": peer_id,
		"player_id": player_id,
		"sequence": sequence,
		"position": player.global_position,
		"rotation_y": player.rotation.y,
		"health": health
	}

func accept_player_state(peer_id: int, state: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_player_state(peer_id, state)
	if validation.get("ok", false) != true:
		player_state_rejected.emit(peer_id, str(validation.get("error", "invalid_state")))
		return validation
	var sequence: int = int(state.get("sequence", 0))
	last_sequence_by_peer[peer_id] = sequence
	var copy: Dictionary = state.duplicate(true)
	player_states[peer_id] = copy
	player_state_accepted.emit(peer_id, copy.duplicate(true))
	_ensure_remote_proxy(peer_id)
	return {"ok": true, "peer_id": peer_id, "sequence": sequence}

func validate_player_state(peer_id: int, state: Dictionary) -> Dictionary:
	_resolve_session()
	if peer_id <= 0:
		return {"ok": false, "error": "invalid_peer"}
	if network_session == null:
		return {"ok": false, "error": "network_session_missing"}
	var record: Dictionary = network_session.call("peer_record", peer_id)
	if record.is_empty():
		return {"ok": false, "error": "unknown_peer"}
	if int(state.get("protocol", 0)) != STATE_PROTOCOL:
		return {"ok": false, "error": "unsupported_protocol"}
	if int(state.get("peer_id", 0)) != peer_id:
		return {"ok": false, "error": "peer_spoof"}
	var expected_player_id: String = str(record.get("player_id", network_session.call("stable_player_id", peer_id)))
	if str(state.get("player_id", "")) != expected_player_id:
		return {"ok": false, "error": "player_spoof"}
	var sequence: int = int(state.get("sequence", 0))
	var previous: int = int(last_sequence_by_peer.get(peer_id, 0))
	if sequence <= previous:
		return {"ok": false, "error": "stale_sequence"}
	var position_value: Variant = state.get("position", null)
	if not position_value is Vector3:
		return {"ok": false, "error": "invalid_position"}
	var position: Vector3 = position_value as Vector3
	if abs(position.x) > MAX_WORLD_COORDINATE or abs(position.y) > MAX_WORLD_COORDINATE or abs(position.z) > MAX_WORLD_COORDINATE:
		return {"ok": false, "error": "position_out_of_bounds"}
	var previous_state_value: Variant = player_states.get(peer_id, {})
	if previous_state_value is Dictionary and not (previous_state_value as Dictionary).is_empty():
		var previous_position_value: Variant = (previous_state_value as Dictionary).get("position", null)
		if previous_position_value is Vector3:
			var step_distance: float = (previous_position_value as Vector3).distance_to(position)
			if step_distance > MAX_SNAPSHOT_STEP_DISTANCE:
				return {"ok": false, "error": "movement_step_too_large"}
	return {"ok": true}

func state_for_peer(peer_id: int) -> Dictionary:
	var value: Variant = player_states.get(peer_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func remove_peer(peer_id: int) -> void:
	player_states.erase(peer_id)
	last_sequence_by_peer.erase(peer_id)
	var proxy_value: Variant = remote_proxies.get(peer_id)
	if proxy_value is Node and is_instance_valid(proxy_value):
		(proxy_value as Node).queue_free()
	remote_proxies.erase(peer_id)

func _resolve_session() -> void:
	if is_instance_valid(network_session):
		return
	var parent := get_parent()
	if parent != null:
		network_session = parent.get_node_or_null("NetworkSession")

func _find_local_player() -> Node3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var players: Array[Node] = tree.get_nodes_in_group("player")
	if players.is_empty() or not players[0] is Node3D:
		return null
	return players[0] as Node3D

func _local_peer_id() -> int:
	if network_session == null:
		return -1
	return int(network_session.call("local_peer_id"))

func _ensure_remote_proxy(peer_id: int) -> void:
	if peer_id == _local_peer_id() or DisplayServer.get_name() == "headless":
		return
	if remote_proxies.has(peer_id) and is_instance_valid(remote_proxies[peer_id]):
		return
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var proxy := Node3D.new()
	proxy.name = "RemotePlayer_%d" % peer_id
	proxy.set_meta("stable_id", "player:peer:%d" % peer_id)
	proxy.add_to_group("remote_player")
	_build_remote_visual(proxy)
	parent.add_child(proxy)
	remote_proxies[peer_id] = proxy

func _build_remote_visual(proxy: Node3D) -> void:
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.75, 0.95, 0.46)
	torso.mesh = torso_mesh
	torso.position.y = 1.23
	torso.material_override = _material(Color("433b62"))
	proxy.add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.27
	head_mesh.height = 0.54
	head_mesh.radial_segments = 8
	head_mesh.rings = 4
	head.mesh = head_mesh
	head.position.y = 1.92
	head.material_override = _material(Color("b69a82"))
	proxy.add_child(head)

func _update_remote_proxies(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for peer_id_value in remote_proxies.keys():
		var peer_id: int = int(peer_id_value)
		var proxy_value: Variant = remote_proxies.get(peer_id)
		if not proxy_value is Node3D or not is_instance_valid(proxy_value):
			continue
		var state: Dictionary = state_for_peer(peer_id)
		if state.is_empty():
			continue
		var position_value: Variant = state.get("position", null)
		if not position_value is Vector3:
			continue
		var proxy := proxy_value as Node3D
		var target: Vector3 = position_value as Vector3
		proxy.global_position = proxy.global_position.lerp(target, clampf(delta * 12.0, 0.0, 1.0))
		proxy.rotation.y = lerp_angle(proxy.rotation.y, float(state.get("rotation_y", 0.0)), clampf(delta * 12.0, 0.0, 1.0))

func _on_peer_joined(peer_id: int, _player_id: String) -> void:
	_ensure_remote_proxy(peer_id)

func _on_peer_left(peer_id: int, _player_id: String) -> void:
	remove_peer(peer_id)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_player_state(state: Dictionary) -> void:
	_resolve_session()
	if network_session == null or network_session.call("is_server_authority") != true:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	var result: Dictionary = accept_player_state(sender_id, state)
	if result.get("ok", false):
		_replicate_player_state.rpc(state)

@rpc("authority", "call_remote", "unreliable_ordered")
func _replicate_player_state(state: Dictionary) -> void:
	var peer_id: int = int(state.get("peer_id", 0))
	if peer_id <= 0 or peer_id == _local_peer_id():
		return
	# The server has already validated this snapshot. Clients keep only the
	# newest sequence so late/unordered packets cannot rewind remote players.
	var sequence: int = int(state.get("sequence", 0))
	if sequence <= int(last_sequence_by_peer.get(peer_id, 0)):
		return
	last_sequence_by_peer[peer_id] = sequence
	player_states[peer_id] = state.duplicate(true)
	_ensure_remote_proxy(peer_id)
