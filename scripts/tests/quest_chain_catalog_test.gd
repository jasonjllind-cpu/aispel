extends SceneTree

const QUESTS := preload("res://scripts/progression/quest_chain_catalog.gd")

func _init() -> void:
	if not _validate_catalog():
		return
	if not _validate_branching():
		return
	if not _validate_completion_events():
		return
	print("QUEST_CHAIN_CATALOG_OK chains=%d" % QUESTS.get_chain_ids().size())
	quit(0)

func _validate_catalog() -> bool:
	var validation: Dictionary = QUESTS.validate_all()
	if not bool(validation.get("valid", false)):
		return _fail("Quest graph validation failed: %s" % var_to_str(validation.get("errors", [])))
	if QUESTS.get_chain_ids().size() < 2:
		return _fail("Quest-chain progression requires multiple chains")
	var progression_ids: Dictionary = {}
	for chain_id in QUESTS.get_chain_ids():
		var chain: Dictionary = QUESTS.get_chain(chain_id)
		var nodes: Dictionary = chain.get("nodes", {}) as Dictionary
		if nodes.size() < 5:
			return _fail("Quest chain %s is too small to exercise branching" % chain_id)
		for node_id in nodes.keys():
			var node: Dictionary = QUESTS.get_node(chain_id, str(node_id))
			var progression_id: String = str(node.get("progression_id", ""))
			if progression_id.is_empty() or progression_ids.has(progression_id):
				return _fail("Quest progression IDs are missing or duplicated")
			progression_ids[progression_id] = true
	return true

func _validate_branching() -> bool:
	var first: Array[String] = QUESTS.available_nodes("frontier_oath", 1, [])
	if first != ["frontier:arrival"]:
		return _fail("Frontier quest entry gate is invalid")
	var after_arrival: Array[String] = QUESTS.available_nodes("frontier_oath", 2, ["frontier:arrival"])
	if after_arrival != ["frontier:scavenger", "frontier:warden"]:
		return _fail("Frontier branch did not expose both deterministic choices")
	var after_warden: Array[String] = QUESTS.available_nodes("frontier_oath", 3, ["frontier:arrival", "frontier:warden"])
	if not after_warden.has("frontier:moon_shrine"):
		return _fail("requires_any did not unlock the converging quest node")
	var too_low: Array[String] = QUESTS.available_nodes("blackwood_pact", 4, [])
	if not too_low.is_empty():
		return _fail("Quest level prerequisite was ignored")
	var blackwood_entry: Array[String] = QUESTS.available_nodes("blackwood_pact", 5, [])
	if blackwood_entry != ["blackwood:edge"]:
		return _fail("Blackwood chain entry was not unlocked at required level")
	return true

func _validate_completion_events() -> bool:
	var first: Dictionary = QUESTS.build_completion_event("frontier_oath", "frontier:moon_shrine", 17)
	var second: Dictionary = QUESTS.build_completion_event("frontier_oath", "frontier:moon_shrine", 17)
	if first.is_empty() or var_to_str(first) != var_to_str(second):
		return _fail("Quest completion event is missing or non-deterministic")
	if str(first.get("event_id", "")) != "quest_complete:frontier_oath:frontier_moon_shrine:17":
		return _fail("Quest completion event stable ID changed")
	if str(first.get("progression_id", "")) != "quest:frontier_oath:frontier_moon_shrine":
		return _fail("Quest progression ID contract changed")
	var rewards: Array = first.get("reward_ids", []) as Array
	if not rewards.has("spell:moon_bolt") or not rewards.has("xp:240"):
		return _fail("Quest completion rewards are missing")
	if not QUESTS.build_completion_event("frontier_oath", "missing", 0).is_empty():
		return _fail("Unknown quest node was accepted")
	return true

func _fail(message: String) -> bool:
	printerr("QUEST_CHAIN_CATALOG_FAILED: %s" % message)
	quit(1)
	return false
