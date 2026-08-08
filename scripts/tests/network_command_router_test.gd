extends SceneTree

const NETWORK_SESSION_SCRIPT := preload("res://scripts/network/network_session.gd")
const COMMAND_ROUTER_SCRIPT := preload("res://scripts/network/network_command_router.gd")

func _init() -> void:
	var root := Node.new()
	root.name = "NetworkTestRoot"
	get_root().add_child(root)

	var session := Node.new()
	session.set_script(NETWORK_SESSION_SCRIPT)
	session.name = "NetworkSession"
	root.add_child(session)
	session.call("register_peer_for_test", 1)
	session.call("register_peer_for_test", 4)

	var router := Node.new()
	router.set_script(COMMAND_ROUTER_SCRIPT)
	root.add_child(router)
	router.set("network_session", session)

	var command := {
		"protocol": 1,
		"sequence": 1,
		"action": "interact",
		"payload": {"target_id": "npc:elowen_wayfinder"}
	}
	var result: Dictionary = router.call("process_command", 4, command)
	if result.get("ok", false) != true or str(result.get("player_id", "")) != "player:peer:4":
		_fail("Valid peer command was not accepted with stable player authority")
		return
	var replay: Dictionary = router.call("process_command", 4, command)
	if str(replay.get("error", "")) != "stale_sequence":
		_fail("Replayed network command was not rejected")
		return
	var forbidden: Dictionary = router.call("process_command", 4, {
		"protocol": 1,
		"sequence": 2,
		"action": "set_world_state",
		"payload": {}
	})
	if str(forbidden.get("error", "")) != "action_not_allowed":
		_fail("Client world-state mutation escaped command whitelist")
		return
	var unknown: Dictionary = router.call("process_command", 99, {
		"protocol": 1,
		"sequence": 1,
		"action": "attack",
		"payload": {"target_id": "enemy:test"}
	})
	if str(unknown.get("error", "")) != "unknown_peer":
		_fail("Unknown peer command was not rejected")
		return
	var jump: Dictionary = router.call("process_command", 4, {
		"protocol": 1,
		"sequence": 9000,
		"action": "attack",
		"payload": {}
	})
	if str(jump.get("error", "")) != "sequence_jump":
		_fail("Abnormal command sequence jump was not rejected")
		return
	var next: Dictionary = router.call("process_command", 4, {
		"protocol": 1,
		"sequence": 2,
		"action": "attack",
		"payload": {"target_id": "enemy:test"}
	})
	if next.get("ok", false) != true:
		_fail("Valid command after rejected input was not accepted")
		return

	print("NETWORK_COMMAND_ROUTER_OK peer=%d sequence=%d" % [4, int(next.get("sequence", 0))])
	quit(0)

func _fail(message: String) -> void:
	printerr("NETWORK_COMMAND_ROUTER_FAILED: %s" % message)
	quit(1)
