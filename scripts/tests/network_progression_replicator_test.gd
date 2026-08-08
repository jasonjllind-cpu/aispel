extends SceneTree

const REPLICATOR := preload("res://scripts/network/network_progression_replicator.gd")
const PROGRESSION := preload("res://scripts/progression/player_progression_state.gd")
const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")
const BUILD := preload("res://scripts/progression/character_build_model.gd")
const EQUIPMENT := preload("res://scripts/equipment/equipment_progression_catalog.gd")

func _init() -> void:
	var replicator: Node = REPLICATOR.new()
	root.add_child(replicator)
	if not _validate_snapshots(replicator):
		return
	if not _validate_ordered_deltas(replicator):
		return
	if not _validate_rejection_paths(replicator):
		return
	print("NETWORK_PROGRESSION_REPLICATOR_OK")
	quit(0)

func _fixture(player_id: String) -> Dictionary:
	var progression: RefCounted = PROGRESSION.new()
	progression.call("configure", player_id)
	progression.call("grant_xp", int(progression.call("total_xp_required_for_level", 12)), "quest:test")
	var magic: Dictionary = MAGIC.create_state(player_id)
	magic = MAGIC.grant_mastery(magic, "moon", 400, "magic_discovery:test:moon")
	var build: Dictionary = BUILD.create_build(player_id)
	var weapon: Dictionary = EQUIPMENT.roll_item("equipment:moon_blade", 12, 77082601, "network:test", 0)
	build = BUILD.equip(build, weapon, 12)
	build = BUILD.assign_spell(build, 0, "moon_bolt", 12, magic)
	var quests: Array[String] = ["quest:frontier_oath:moon_path"]
	return {
		"progression": progression.call("to_dict"),
		"magic": magic,
		"build": build,
		"quests": quests
	}

func _validate_snapshots(replicator: Node) -> bool:
	var player_id: String = "player:net:test"
	var fixture: Dictionary = _fixture(player_id)
	var progression: Dictionary = (fixture.get("progression", {}) as Dictionary)
	var magic: Dictionary = (fixture.get("magic", {}) as Dictionary)
	var build: Dictionary = (fixture.get("build", {}) as Dictionary)
	var quests: Array[String] = []
	for quest_id in fixture.get("quests", []) as Array:
		quests.append(str(quest_id))
	var snapshot: Dictionary = replicator.call("build_player_snapshot", player_id, progression, magic, build, quests, 1)
	if snapshot.is_empty() or not bool(replicator.call("validate_snapshot", snapshot)):
		return _fail("Valid authoritative snapshot failed validation")
	var result: Dictionary = replicator.call("register_authoritative_snapshot", snapshot)
	if result.get("ok", false) != true:
		return _fail("Valid authoritative snapshot was rejected")
	var stored: Dictionary = replicator.call("player_snapshot", player_id)
	if int(stored.get("revision", 0)) != 1 or str(stored.get("player_id", "")) != player_id:
		return _fail("Authoritative snapshot was not stored with stable identity/revision")
	var stale: Dictionary = replicator.call("register_authoritative_snapshot", snapshot)
	if str(stale.get("error", "")) != "stale_revision":
		return _fail("Duplicate/stale authoritative snapshot was accepted")
	return true

func _validate_ordered_deltas(replicator: Node) -> bool:
	var player_id: String = "player:net:test"
	var fixture: Dictionary = _fixture(player_id)
	var progression: Dictionary = (fixture.get("progression", {}) as Dictionary).duplicate(true)
	var progression_delta: Dictionary = replicator.call("build_delta", player_id, "progression", progression, 2)
	var applied: Dictionary = replicator.call("apply_delta", progression_delta)
	if applied.get("ok", false) != true or int(applied.get("revision", 0)) != 2:
		return _fail("Ordered progression delta was not applied")
	var magic: Dictionary = (fixture.get("magic", {}) as Dictionary).duplicate(true)
	magic = MAGIC.grant_mastery(magic, "frost", 160, "magic_discovery:test:frost")
	var magic_delta: Dictionary = replicator.call("build_delta", player_id, "magic", magic, 3)
	var magic_result: Dictionary = replicator.call("apply_delta", magic_delta)
	if magic_result.get("ok", false) != true:
		return _fail("Magic delta was not applied")
	var quests: Array[String] = ["quest:frontier_oath:moon_path", "quest:blackwood_pact:root"]
	var quest_delta: Dictionary = replicator.call("build_delta", player_id, "quests", quests, 4)
	var quest_result: Dictionary = replicator.call("apply_delta", quest_delta)
	if quest_result.get("ok", false) != true:
		return _fail("Quest-state delta was not applied")
	var final_snapshot: Dictionary = replicator.call("player_snapshot", player_id)
	if int(final_snapshot.get("revision", 0)) != 4 or (final_snapshot.get("completed_quests", []) as Array).size() != 2:
		return _fail("Replicated state did not converge to latest revision")
	return true

func _validate_rejection_paths(replicator: Node) -> bool:
	var player_id: String = "player:net:test"
	var current: Dictionary = replicator.call("player_snapshot", player_id)
	var stale: Dictionary = replicator.call("build_delta", player_id, "build", current.get("build", {}), 3)
	var stale_result: Dictionary = replicator.call("apply_delta", stale)
	if str(stale_result.get("error", "")) != "stale_revision":
		return _fail("Out-of-order delta was accepted")
	var bad_owner_fixture: Dictionary = _fixture("player:other")
	var bad_progression: Dictionary = bad_owner_fixture.get("progression", {}) as Dictionary
	var bad_magic: Dictionary = bad_owner_fixture.get("magic", {}) as Dictionary
	var bad_build: Dictionary = bad_owner_fixture.get("build", {}) as Dictionary
	var empty_quests: Array[String] = []
	var invalid_owner: Dictionary = replicator.call("build_player_snapshot", player_id, bad_progression, bad_magic, bad_build, empty_quests, 5)
	if not invalid_owner.is_empty():
		return _fail("Cross-player snapshot ownership mismatch was accepted")
	var bad_quests: Array[String] = ["quest:duplicate", "quest:duplicate"]
	if not (replicator.call("build_delta", player_id, "quests", bad_quests, 5) as Dictionary).is_empty():
		return _fail("Duplicate quest IDs were accepted in replication payload")
	if not (replicator.call("build_delta", player_id, "inventory", {}, 5) as Dictionary).is_empty():
		return _fail("Unsupported replication kind was accepted")
	var action: Dictionary = replicator.call("validate_client_action", 2, "equip", {"player_id": player_id, "instance_id": "item:test"})
	if str(action.get("error", "")) != "network_session_missing":
		return _fail("Client action bypassed authority/session validation")
	return true

func _fail(message: String) -> bool:
	printerr("NETWORK_PROGRESSION_REPLICATOR_FAILED: %s" % message)
	quit(1)
	return false
