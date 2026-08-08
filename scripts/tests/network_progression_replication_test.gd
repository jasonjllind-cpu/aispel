extends SceneTree

const REPLICATOR := preload("res://scripts/network/network_progression_replicator.gd")
const PROGRESSION := preload("res://scripts/progression/player_progression_state.gd")
const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")
const BUILD := preload("res://scripts/progression/character_build_model.gd")

class MockSession:
	extends Node
	var records: Dictionary = {
		2: {"peer_id": 2, "player_id": "player:2", "state": "ready"},
		3: {"peer_id": 3, "player_id": "player:3", "state": "ready"}
	}
	func peer_record(peer_id: int) -> Dictionary:
		var value: Variant = records.get(peer_id, {})
		return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func _init() -> void:
	if not _validate_snapshot_and_deltas():
		return
	if not _validate_ownership_contracts():
		return
	if not _validate_replay_and_payload_rejection():
		return
	print("NETWORK_PROGRESSION_REPLICATION_OK")
	quit(0)

func _make_fixture(player_id: String) -> Dictionary:
	var progression: RefCounted = PROGRESSION.new()
	progression.call("configure", player_id)
	progression.call("grant_xp", int(progression.call("total_xp_required_for_level", 8)) + 17, "quest:test")
	var magic: Dictionary = MAGIC.create_state(player_id)
	magic = MAGIC.grant_mastery(magic, "moon", 400, "magic_discovery:test:moon")
	var build: Dictionary = BUILD.create_build(player_id)
	build = BUILD.assign_spell(build, 0, "moon_bolt", 8, magic)
	return {
		"progression": progression.call("to_dict") as Dictionary,
		"magic": magic,
		"build": build,
		"quests": ["quest:frontier_oath:frontier_arrival"]
	}

func _validate_snapshot_and_deltas() -> bool:
	var replicator: Node = REPLICATOR.new()
	var fixture: Dictionary = _make_fixture("player:2")
	var snapshot: Dictionary = replicator.call("build_player_snapshot", "player:2", fixture["progression"], fixture["magic"], fixture["build"], fixture["quests"])
	if snapshot.is_empty() or not bool(replicator.call("validate_snapshot", snapshot)):
		return _fail("Authoritative progression snapshot failed validation")
	var registration: Dictionary = replicator.call("register_authoritative_snapshot", snapshot)
	if registration.get("ok", false) != true or int(registration.get("revision", 0)) != 1:
		return _fail("Initial authoritative snapshot was not registered")

	var progression_state: RefCounted = PROGRESSION.new()
	if not bool(progression_state.call("load_dict", fixture["progression"])):
		return _fail("Progression fixture failed to restore")
	progression_state.call("grant_xp", 250, "dungeon:test")
	var progression_delta: Dictionary = replicator.call("build_delta", "player:2", "progression", progression_state.call("to_dict"))
	if progression_delta.is_empty() or int(progression_delta.get("revision", 0)) != 2:
		return _fail("Progression delta did not receive the next revision")
	if (replicator.call("apply_delta", progression_delta) as Dictionary).get("ok", false) != true:
		return _fail("Progression delta was rejected")

	var magic: Dictionary = MAGIC.grant_mastery(fixture["magic"], "frost", 170, "magic_discovery:test:frost")
	var magic_delta: Dictionary = replicator.call("build_delta", "player:2", "magic", magic)
	if (replicator.call("apply_delta", magic_delta) as Dictionary).get("ok", false) != true:
		return _fail("Magic delta was rejected")

	var quests: Array[String] = ["quest:frontier_oath:frontier_arrival", "quest:frontier_oath:frontier_warden"]
	var quest_delta: Dictionary = replicator.call("build_delta", "player:2", "quests", quests)
	if (replicator.call("apply_delta", quest_delta) as Dictionary).get("ok", false) != true:
		return _fail("Quest delta was rejected")

	var final_snapshot: Dictionary = replicator.call("player_snapshot", "player:2")
	if int(final_snapshot.get("revision", 0)) != 4:
		return _fail("Authoritative revision did not advance through all deltas")
	if (final_snapshot.get("completed_quests", []) as Array).size() != 2:
		return _fail("Quest state was not replicated")
	if int((final_snapshot.get("progression", {}) as Dictionary).get("lifetime_xp", 0)) <= int((fixture["progression"] as Dictionary).get("lifetime_xp", 0)):
		return _fail("Progression state did not advance after replication")
	return true

func _validate_ownership_contracts() -> bool:
	var replicator: Node = REPLICATOR.new()
	var session := MockSession.new()
	replicator.set("network_session", session)
	var equip_ok: Dictionary = replicator.call("validate_client_action", 2, "equip", {"player_id": "player:2", "instance_id": "item:test"})
	if equip_ok.get("ok", false) != true:
		return _fail("Owned equip request was rejected")
	var spoofed: Dictionary = replicator.call("validate_client_action", 2, "equip", {"player_id": "player:3", "instance_id": "item:test"})
	if str(spoofed.get("error", "")) != "ownership_mismatch":
		return _fail("Progression authority accepted a spoofed player identity")
	var spell_ok: Dictionary = replicator.call("validate_client_action", 2, "assign_spell", {"player_id": "player:2", "slot_index": 1, "spell_id": "moon_bolt"})
	if spell_ok.get("ok", false) != true:
		return _fail("Valid spell-loadout request was rejected")
	var bad_spell: Dictionary = replicator.call("validate_client_action", 2, "assign_spell", {"player_id": "player:2", "slot_index": 0, "spell_id": "not_a_spell"})
	if str(bad_spell.get("error", "")) != "unknown_spell":
		return _fail("Unknown spell escaped authoritative validation")
	var quest_ok: Dictionary = replicator.call("validate_client_action", 3, "quest_choice", {"player_id": "player:3", "progression_id": "quest:blackwood_pact:blackwood_edge"})
	if quest_ok.get("ok", false) != true:
		return _fail("Owned quest-choice request was rejected")
	var forbidden: Dictionary = replicator.call("validate_client_action", 2, "grant_xp", {"player_id": "player:2", "xp": 999999})
	if str(forbidden.get("error", "")) != "action_not_allowed":
		return _fail("Client was allowed to submit authoritative XP changes")
	return true

func _validate_replay_and_payload_rejection() -> bool:
	var replicator: Node = REPLICATOR.new()
	var fixture: Dictionary = _make_fixture("player:2")
	var snapshot: Dictionary = replicator.call("build_player_snapshot", "player:2", fixture["progression"], fixture["magic"], fixture["build"], fixture["quests"], 7)
	if (replicator.call("register_authoritative_snapshot", snapshot) as Dictionary).get("ok", false) != true:
		return _fail("Replay fixture snapshot failed to register")
	var stale: Dictionary = replicator.call("build_delta", "player:2", "quests", fixture["quests"], 7)
	if str((replicator.call("apply_delta", stale) as Dictionary).get("error", "")) != "stale_revision":
		return _fail("Replay/stale revision was not rejected")
	var wrong_owner_progression: Dictionary = (fixture["progression"] as Dictionary).duplicate(true)
	wrong_owner_progression["player_id"] = "player:3"
	var invalid: Dictionary = replicator.call("build_delta", "player:2", "progression", wrong_owner_progression, 8)
	if not invalid.is_empty():
		return _fail("Cross-player progression payload produced a network delta")
	var duplicate_quests: Array[String] = ["quest:test:a", "quest:test:a"]
	if not (replicator.call("build_delta", "player:2", "quests", duplicate_quests, 8) as Dictionary).is_empty():
		return _fail("Duplicate quest state produced a network delta")
	var unsupported: Dictionary = {"protocol": 99, "player_id": "player:2", "revision": 8, "kind": "quests", "payload": []}
	if str((replicator.call("validate_delta", unsupported) as Dictionary).get("error", "")) != "unsupported_protocol":
		return _fail("Unsupported progression protocol was accepted")
	return true

func _fail(message: String) -> bool:
	printerr("NETWORK_PROGRESSION_REPLICATION_FAILED: %s" % message)
	quit(1)
	return false
