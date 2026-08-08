extends SceneTree

const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const NETWORK_SESSION_SCRIPT := preload("res://scripts/network/network_session.gd")

func _init() -> void:
	var world_state := Node.new()
	world_state.set_script(WORLD_STATE_SCRIPT)
	world_state.name = "NetworkWorldState"
	get_root().add_child(world_state)
	world_state.set("world_seed", 246810)
	world_state.set("current_region_id", "veilmoor")
	world_state.call("mark_region_discovered", "starting_valley")
	world_state.call("mark_region_discovered", "veilmoor")
	world_state.call("set_entity_state", "boss:hollow_king", {"dead": true})

	var session := Node.new()
	session.set_script(NETWORK_SESSION_SCRIPT)
	get_root().add_child(session)
	session.set("world_state", world_state)

	if str(session.call("stable_player_id", 7)) != "player:peer:7":
		_fail("Stable network player ID is invalid")
		return
	var host_record: Dictionary = session.call("register_peer_for_test", 1)
	var client_record: Dictionary = session.call("register_peer_for_test", 7)
	if str(host_record.get("player_id", "")) != "player:peer:1" or str(client_record.get("player_id", "")) != "player:peer:7":
		_fail("Peer registry did not use stable player IDs")
		return
	var peer_players: Dictionary = session.get("peer_players")
	if peer_players.size() != 2:
		_fail("Peer registry size mismatch")
		return

	var payload: Dictionary = session.call("build_bootstrap_payload")
	if int(payload.get("protocol", 0)) != 1 or int(payload.get("world_seed", 0)) != 246810:
		_fail("Server bootstrap metadata is invalid")
		return
	var snapshot_value: Variant = payload.get("world_state", {})
	if not snapshot_value is Dictionary:
		_fail("Server bootstrap world snapshot is missing")
		return
	var snapshot: Dictionary = snapshot_value as Dictionary
	if str(snapshot.get("current_region_id", "")) != "veilmoor":
		_fail("Server bootstrap did not include current region")
		return

	world_state.call("new_world", 999)
	session.set("peer_players", {})
	if session.call("apply_bootstrap_payload", payload) != true:
		_fail("Client rejected valid bootstrap payload")
		return
	if int(world_state.get("world_seed")) != 246810 or str(world_state.get("current_region_id")) != "veilmoor":
		_fail("Client bootstrap did not restore authoritative WorldState")
		return
	peer_players = session.get("peer_players")
	if peer_players.size() != 2 or not peer_players.has(7):
		_fail("Client bootstrap did not restore player registry")
		return
	if session.call("apply_bootstrap_payload", {"protocol": 999}) == true:
		_fail("Unsupported network protocol was accepted")
		return
	var removed: String = session.call("unregister_peer_for_test", 7)
	if removed != "player:peer:7" or (session.get("peer_players") as Dictionary).has(7):
		_fail("Peer disconnect did not remove stable player record")
		return

	print("NETWORK_SESSION_FOUNDATION_OK seed=%d peers=%d" % [
		int(world_state.get("world_seed")),
		(session.get("peer_players") as Dictionary).size()
	])
	quit(0)

func _fail(message: String) -> void:
	printerr("NETWORK_SESSION_FOUNDATION_FAILED: %s" % message)
	quit(1)
