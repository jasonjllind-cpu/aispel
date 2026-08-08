extends SceneTree

const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const REPLICATOR_SCRIPT := preload("res://scripts/network/network_world_state_replicator.gd")

func _init() -> void:
	var state := Node.new()
	state.set_script(WORLD_STATE_SCRIPT)
	state.name = "ReplicatedWorldState"
	get_root().add_child(state)

	var replicator := Node.new()
	replicator.set_script(REPLICATOR_SCRIPT)
	get_root().add_child(replicator)
	replicator.set("world_state", state)

	state.call("set_flag", "gate:test", true)
	var flag_delta: Dictionary = replicator.call("build_delta", "flag", "gate:test", 1)
	state.call("set_flag", "gate:test", false)
	var result: Dictionary = replicator.call("apply_delta", flag_delta)
	if result.get("ok", false) != true or state.call("get_flag", "gate:test", false) != true:
		_fail("Authoritative flag delta did not apply")
		return

	var entity_delta := {
		"protocol": 1,
		"sequence": 2,
		"kind": "entity",
		"stable_id": "boss:hollow_king",
		"payload": {"dead": true, "health": 0}
	}
	result = replicator.call("apply_delta", entity_delta)
	var boss_state: Dictionary = state.call("get_entity_state", "boss:hollow_king")
	if result.get("ok", false) != true or boss_state.get("dead", false) != true:
		_fail("Authoritative entity delta did not apply")
		return

	var discovery_delta := {
		"protocol": 1,
		"sequence": 3,
		"kind": "discovery",
		"stable_id": "veilmoor",
		"payload": true
	}
	if (replicator.call("apply_delta", discovery_delta) as Dictionary).get("ok", false) != true or state.call("is_region_discovered", "veilmoor") != true:
		_fail("Discovery delta did not apply")
		return

	var stale: Dictionary = replicator.call("apply_delta", discovery_delta)
	if str(stale.get("error", "")) != "stale_sequence":
		_fail("Stale WorldState delta was not rejected")
		return
	var forbidden: Dictionary = replicator.call("apply_delta", {
		"protocol": 1,
		"sequence": 4,
		"kind": "arbitrary_mutation",
		"stable_id": "world",
		"payload": {}
	})
	if str(forbidden.get("error", "")) != "kind_not_allowed":
		_fail("Unapproved WorldState delta kind was accepted")
		return
	var malformed: Dictionary = replicator.call("apply_delta", {
		"protocol": 1,
		"sequence": 4,
		"kind": "entity",
		"stable_id": "enemy:test",
		"payload": "not_a_dictionary"
	})
	if str(malformed.get("error", "")) != "invalid_entity_payload":
		_fail("Malformed entity delta was accepted")
		return

	print("NETWORK_WORLD_STATE_OK sequence=%d boss_dead=true" % int(replicator.get("last_received_sequence")))
	quit(0)

func _fail(message: String) -> void:
	printerr("NETWORK_WORLD_STATE_FAILED: %s" % message)
	quit(1)
