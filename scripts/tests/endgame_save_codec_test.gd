extends SceneTree

const CODEC := preload("res://scripts/progression/endgame_save_codec.gd")
const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const ACCESS := preload("res://scripts/progression/endgame_region_access.gd")
const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")
const CHOICES := preload("res://scripts/progression/endgame_choice_consequences.gd")

func _init() -> void:
	var generator: RefCounted = GRAPH.new()
	generator.call("configure", 87082601)
	var graph: Dictionary = generator.call("generate_graph", 64) as Dictionary
	var plan: Dictionary = RELICS.build_plan(graph, ACCESS.build_access_plan(graph))
	var snapshot: Dictionary = {
		"completed_campaign": ["campaign:frontier_oath", "campaign:blackwood_pact", "campaign:convergence"],
		"world_milestones": ["world_milestone:windscar_beacon"],
		"boss_state": BOSSES.empty_state(),
		"relic_plan": plan,
		"relic_state": RELICS.create_state(plan),
		"choice_state": CHOICES.create_state("world:test"),
		"postgame_profile": {}
	}
	if not CODEC.validate_snapshot(snapshot):
		_fail("Baseline endgame snapshot is invalid")
		return
	var encoded: Dictionary = CODEC.encode(snapshot, 12)
	if not CODEC.validate(encoded):
		_fail("Current endgame save payload is invalid")
		return
	if var_to_str(CODEC.decode(encoded)) != var_to_str(snapshot):
		_fail("Current endgame save did not roundtrip")
		return

	var legacy: Dictionary = CODEC.build_legacy_v1(snapshot, 7)
	var migrated: Dictionary = CODEC.migrate(legacy)
	if not CODEC.validate(migrated):
		_fail("Legacy endgame save did not migrate to current version")
		return
	var migrated_snapshot: Dictionary = CODEC.decode(migrated)
	if var_to_str(migrated_snapshot) != var_to_str(snapshot):
		_fail("Legacy migration changed shared endgame state")
		return

	var corrupted: Dictionary = encoded.duplicate(true)
	var corrupted_snapshot: Dictionary = (corrupted.get("snapshot", {}) as Dictionary).duplicate(true)
	corrupted_snapshot["completed_campaign"] = ["campaign:does_not_exist"]
	corrupted["snapshot"] = corrupted_snapshot
	if CODEC.validate(corrupted):
		_fail("Corrupted payload passed checksum/state validation")
		return
	var recovered: Dictionary = CODEC.recover(corrupted, snapshot, 13)
	if not CODEC.validate(recovered) or recovered.get("recovered", false) != true:
		_fail("Corrupted endgame payload was not recovered from trusted baseline")
		return
	if str(recovered.get("recovery_reason", "")) != "checksum_mismatch":
		_fail("Corruption recovery did not report checksum mismatch")
		return
	if var_to_str(CODEC.decode(recovered)) != var_to_str(snapshot):
		_fail("Recovery altered trusted deterministic baseline")
		return

	var unsupported: Dictionary = {"version": 99, "payload": "future"}
	var unsupported_recovery: Dictionary = CODEC.recover(unsupported, snapshot, 14)
	if not CODEC.validate(unsupported_recovery) or str(unsupported_recovery.get("recovery_reason", "")) != "unsupported_version":
		_fail("Unsupported save version did not use explicit recovery path")
		return
	if not CODEC.recover({}, {}, 15).is_empty():
		_fail("Recovery accepted an invalid baseline snapshot")
		return

	print("ENDGAME_SAVE_CODEC_OK version=%d migrated=%d recovered=%s" % [CODEC.CURRENT_VERSION, int(migrated.get("version", 0)), str(recovered.get("recovery_reason", ""))])
	quit(0)

func _fail(message: String) -> void:
	printerr("ENDGAME_SAVE_CODEC_FAILED: %s" % message)
	quit(1)
