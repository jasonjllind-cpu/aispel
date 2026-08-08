extends SceneTree

const BUNDLE := preload("res://scripts/progression/player_progression_bundle.gd")
const QUESTS := preload("res://scripts/progression/quest_chain_catalog.gd")
const EQUIPMENT := preload("res://scripts/equipment/equipment_progression_catalog.gd")
const GATES := preload("res://scripts/progression/regional_progression_gate.gd")
const NETWORK := preload("res://scripts/network/network_progression_replicator.gd")

const TEST_SEED: int = 79082601
const ACTION_COUNT: int = 96
const MAX_RUNTIME_MS: int = 15000

func _init() -> void:
	var started_ms: int = Time.get_ticks_msec()
	if not _validate_full_journey():
		return
	if not _validate_reward_idempotency():
		return
	if not _validate_stress_round_trip():
		return
	var elapsed_ms: int = Time.get_ticks_msec() - started_ms
	if elapsed_ms > MAX_RUNTIME_MS:
		_fail("Progression integration exceeded runtime gate: %d ms" % elapsed_ms)
		return
	print("PROGRESSION_INTEGRATION_OK actions=%d elapsed_ms=%d" % [ACTION_COUNT, elapsed_ms])
	quit(0)

func _validate_full_journey() -> bool:
	var bundle: Dictionary = BUNDLE.create("player:test")
	if not BUNDLE.validate(bundle) or BUNDLE.player_level(bundle) != 1:
		return _fail("Fresh integrated progression bundle is invalid")

	var arrival: Dictionary = QUESTS.build_completion_event("frontier_oath", "frontier:arrival", 1)
	bundle = BUNDLE.apply_quest_completion(bundle, arrival)
	var moon_shrine: Dictionary = QUESTS.build_completion_event("frontier_oath", "frontier:moon_shrine", 2)
	bundle = BUNDLE.apply_quest_completion(bundle, moon_shrine)
	if not (bundle.get("completed_quests", []) as Array).has("quest:frontier_oath:frontier_moon_shrine"):
		return _fail("Quest completion did not enter integrated quest state")
	if not ((bundle.get("magic", {}) as Dictionary).get("unlocked_spells", []) as Array).has("moon_bolt"):
		return _fail("Quest reward did not unlock spell through integrated bundle")

	bundle = BUNDLE.apply_lore_discovery(bundle, "moon_shrine_verse")
	if not ((bundle.get("magic", {}) as Dictionary).get("discoveries", []) as Array).has("magic_discovery:lore:moon_shrine_verse"):
		return _fail("Lore discovery did not enter integrated magic state")

	var node: Dictionary = {
		"stable_id": "region:integration:frontier",
		"progression_band": "frontier",
		"biome": "green_highlands",
		"graph_depth": 3,
		"content_profile": {"danger": 0.58}
	}
	var sequence: int = 10
	while BUNDLE.player_level(bundle) < 6:
		var reward: Dictionary = GATES.build_reward_event(node, "dungeon", "dungeon:integration:%d" % sequence, maxi(5, BUNDLE.player_level(bundle)), sequence)
		bundle = BUNDLE.apply_progression_reward(bundle, reward)
		sequence += 1
		if sequence > 30:
			return _fail("Integrated reward path failed to reach equipment progression level")

	var weapon: Dictionary = EQUIPMENT.roll_item("equipment:moon_blade", BUNDLE.player_level(bundle), TEST_SEED, "quest:integration", 0)
	if weapon.is_empty():
		return _fail("Integrated equipment reward failed to roll")
	bundle = BUNDLE.equip_item(bundle, weapon)
	bundle = BUNDLE.assign_spell(bundle, 0, "moon_bolt")
	var build: Dictionary = bundle.get("build", {}) as Dictionary
	if str(((build.get("equipment", {}) as Dictionary).get("weapon", {}) as Dictionary).get("instance_id", "")).is_empty():
		return _fail("Integrated bundle lost equipped weapon")
	if str((build.get("spell_slots", []) as Array)[0]) != "moon_bolt":
		return _fail("Integrated bundle lost assigned spell")

	var stats: Dictionary = BUNDLE.derived_stats(bundle, {"might": 2, "vitality": 2, "focus": 2})
	if float(stats.get("damage", 0.0)) <= 20.0 or float(stats.get("magic_power", 0.0)) <= 8.0:
		return _fail("Integrated derived combat stats are unexpectedly weak/empty")

	var envelope: Dictionary = BUNDLE.save_envelope(bundle)
	var restored: Dictionary = BUNDLE.restore_envelope(envelope)
	if restored.is_empty() or var_to_str(restored) != var_to_str(bundle):
		return _fail("Integrated progression bundle changed across save round trip")

	var network: Node = NETWORK.new()
	var snapshot: Dictionary = BUNDLE.build_network_snapshot(restored, network)
	if snapshot.is_empty() or not bool(network.call("validate_snapshot", snapshot)):
		return _fail("Integrated progression bundle failed network snapshot validation")
	if (network.call("register_authoritative_snapshot", snapshot) as Dictionary).get("ok", false) != true:
		return _fail("Integrated progression network snapshot failed to register")
	var replicated: Dictionary = network.call("player_snapshot", "player:test") as Dictionary
	if var_to_str(replicated.get("build", {})) != var_to_str(restored.get("build", {})):
		return _fail("Network replication changed integrated build state")
	return true

func _validate_reward_idempotency() -> bool:
	var bundle: Dictionary = BUNDLE.create("player:idempotent")
	var node: Dictionary = {"stable_id": "region:test:idempotent", "progression_band": "heartland", "biome": "green_highlands", "graph_depth": 0, "content_profile": {"danger": 0.3}}
	var reward: Dictionary = GATES.build_reward_event(node, "encounter", "encounter:test", 1, 1)
	bundle = BUNDLE.apply_progression_reward(bundle, reward)
	var once: String = var_to_str(bundle)
	bundle = BUNDLE.apply_progression_reward(bundle, reward)
	if var_to_str(bundle) != once:
		return _fail("Duplicate regional reward was applied twice")
	var quest: Dictionary = QUESTS.build_completion_event("frontier_oath", "frontier:arrival", 1)
	bundle = BUNDLE.apply_quest_completion(bundle, quest)
	var quest_once: String = var_to_str(bundle)
	bundle = BUNDLE.apply_quest_completion(bundle, quest)
	if var_to_str(bundle) != quest_once:
		return _fail("Duplicate quest completion was applied twice")
	return true

func _validate_stress_round_trip() -> bool:
	var bundle: Dictionary = BUNDLE.create("player:stress")
	var node: Dictionary = {"stable_id": "region:stress:heartland", "progression_band": "heartland", "biome": "green_highlands", "graph_depth": 1, "content_profile": {"danger": 0.42}}
	for index in range(ACTION_COUNT):
		var reward: Dictionary = GATES.build_reward_event(node, "encounter", "encounter:stress:%d" % index, maxi(1, BUNDLE.player_level(bundle)), index)
		bundle = BUNDLE.apply_progression_reward(bundle, reward)
		if index % 16 == 0:
			var envelope: Dictionary = BUNDLE.save_envelope(bundle)
			bundle = BUNDLE.restore_envelope(envelope)
			if bundle.is_empty():
				return _fail("Stress progression bundle failed intermediate save restore")
	if not BUNDLE.validate(bundle):
		return _fail("Stress progression bundle failed final validation")
	if (bundle.get("applied_reward_ids", []) as Array).size() != ACTION_COUNT:
		return _fail("Stress progression lost reward idempotency history")
	var final_envelope: Dictionary = BUNDLE.save_envelope(bundle)
	var final_restore: Dictionary = BUNDLE.restore_envelope(final_envelope)
	if var_to_str(final_restore) != var_to_str(bundle):
		return _fail("Stress progression changed after final save round trip")
	var network: Node = NETWORK.new()
	var snapshot: Dictionary = BUNDLE.build_network_snapshot(bundle, network)
	if snapshot.is_empty() or not bool(network.call("validate_snapshot", snapshot)):
		return _fail("Stress progression failed final network snapshot")
	return true

func _fail(message: String) -> bool:
	printerr("PROGRESSION_INTEGRATION_FAILED: %s" % message)
	quit(1)
	return false
