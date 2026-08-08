extends SceneTree

const NETWORK_SESSION_SCRIPT := preload("res://scripts/network/network_session.gd")
const PLAYER_MANAGER_SCRIPT := preload("res://scripts/network/network_player_manager.gd")

class MockPlayer:
	extends Node3D
	var health: int = 88

func _init() -> void:
	var root := Node3D.new()
	root.name = "NetworkPlayerTestRoot"
	get_root().add_child(root)

	var session := Node.new()
	session.set_script(NETWORK_SESSION_SCRIPT)
	session.name = "NetworkSession"
	root.add_child(session)
	session.call("register_peer_for_test", 1)
	session.call("register_peer_for_test", 4)

	var manager := Node.new()
	manager.set_script(PLAYER_MANAGER_SCRIPT)
	root.add_child(manager)
	manager.set("network_session", session)

	var player := MockPlayer.new()
	player.global_position = Vector3(12.0, 1.0, -7.0)
	player.rotation.y = 0.75
	root.add_child(player)

	var state: Dictionary = manager.call("build_player_state", 4, player, 1)
	if str(state.get("player_id", "")) != "player:peer:4" or int(state.get("health", 0)) != 88:
		_fail("Player snapshot did not preserve stable ownership metadata")
		return
	var accepted: Dictionary = manager.call("accept_player_state", 4, state)
	if accepted.get("ok", false) != true:
		_fail("Valid player state was rejected")
		return
	var stored: Dictionary = manager.call("state_for_peer", 4)
	if stored.get("position", Vector3.ZERO) != Vector3(12.0, 1.0, -7.0):
		_fail("Accepted player transform was not stored")
		return
	var stale: Dictionary = manager.call("accept_player_state", 4, state)
	if str(stale.get("error", "")) != "stale_sequence":
		_fail("Stale player snapshot was not rejected")
		return
	var spoofed: Dictionary = state.duplicate(true)
	spoofed["sequence"] = 2
	spoofed["player_id"] = "player:peer:99"
	var spoof_result: Dictionary = manager.call("accept_player_state", 4, spoofed)
	if str(spoof_result.get("error", "")) != "player_spoof":
		_fail("Player identity spoof was not rejected")
		return
	var out_of_bounds: Dictionary = state.duplicate(true)
	out_of_bounds["sequence"] = 2
	out_of_bounds["position"] = Vector3(999999.0, 1.0, 0.0)
	var bounds_result: Dictionary = manager.call("accept_player_state", 4, out_of_bounds)
	if str(bounds_result.get("error", "")) != "position_out_of_bounds":
		_fail("Out-of-bounds player state was not rejected")
		return
	var unknown: Dictionary = state.duplicate(true)
	unknown["peer_id"] = 9
	unknown["player_id"] = "player:peer:9"
	unknown["sequence"] = 1
	var unknown_result: Dictionary = manager.call("accept_player_state", 9, unknown)
	if str(unknown_result.get("error", "")) != "unknown_peer":
		_fail("Unknown peer player state was not rejected")
		return
	manager.call("remove_peer", 4)
	if not (manager.call("state_for_peer", 4) as Dictionary).is_empty():
		_fail("Disconnected peer state was not removed")
		return

	print("NETWORK_PLAYER_MANAGER_OK player=player:peer:4 sequence=1")
	quit(0)

func _fail(message: String) -> void:
	printerr("NETWORK_PLAYER_MANAGER_FAILED: %s" % message)
	quit(1)
