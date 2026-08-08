extends SceneTree

const GATES := preload("res://scripts/progression/regional_progression_gate.gd")
const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")
const CONTENT_BUNDLE := preload("res://scripts/world/region_content_bundle.gd")

const TEST_SEED: int = 75082601
const TEST_NODE_COUNT: int = 256

func _init() -> void:
	if not _validate_band_gates():
		return
	if not _validate_content_rewards():
		return
	if not _validate_large_world_rewards():
		return
	print("REGIONAL_PROGRESSION_GATE_OK nodes=%d" % TEST_NODE_COUNT)
	quit(0)

func _validate_band_gates() -> bool:
	var magic: Dictionary = MAGIC.create_state("player:test")
	var heartland: Dictionary = {"stable_id": "region:test:heartland", "progression_band": "heartland", "biome": "green_highlands", "content_profile": {"danger": 0.3}, "graph_depth": 0}
	if not bool(GATES.evaluate_region(heartland, 1, magic).get("allowed", false)):
		return _fail("Heartland incorrectly blocks a level-one player")
	var frontier: Dictionary = {"stable_id": "region:test:frontier", "progression_band": "frontier", "biome": "blackwood", "content_profile": {"danger": 0.5}, "graph_depth": 2}
	if str(GATES.evaluate_region(frontier, 4, magic).get("reason", "")) != "level":
		return _fail("Frontier did not enforce its minimum player level")
	if not bool(GATES.evaluate_region(frontier, 5, magic).get("allowed", false)):
		return _fail("Frontier remained locked at its minimum player level")
	var wilds: Dictionary = {"stable_id": "region:test:wilds", "progression_band": "wilds", "biome": "frostmere", "content_profile": {"danger": 0.72}, "graph_depth": 5}
	if str(GATES.evaluate_region(wilds, 12, magic).get("reason", "")) != "school_rank":
		return _fail("Wilds did not require biome-aligned magic mastery")
	magic = MAGIC.grant_mastery(magic, "frost", 160, "magic_discovery:test:wilds")
	if not bool(GATES.evaluate_region(wilds, 12, magic).get("allowed", false)):
		return _fail("Wilds remained locked after satisfying school mastery")
	if str(GATES.evaluate_content(wilds, "dungeon", 10, magic).get("reason", "")) != "content_level":
		return _fail("Dungeon-specific level gate was not applied")
	if not bool(GATES.evaluate_content(wilds, "dungeon", 12, magic).get("allowed", false)):
		return _fail("Dungeon remained locked after satisfying content level")
	return true

func _validate_content_rewards() -> bool:
	var node: Dictionary = {"stable_id": "region:test:reward", "progression_band": "wilds", "biome": "ashen_fen", "graph_depth": 5, "content_profile": {"danger": 0.75}}
	var first: Dictionary = GATES.build_reward_event(node, "dungeon", "dungeon:test:cinder", 14, 3)
	var second: Dictionary = GATES.build_reward_event(node, "dungeon", "dungeon:test:cinder", 14, 3)
	if first.is_empty() or var_to_str(first) != var_to_str(second):
		return _fail("Regional reward event is empty or non-deterministic")
	if str(first.get("reward_id", "")) != "progression_reward:test:reward:dungeon:dungeon_test_cinder:3":
		return _fail("Regional reward stable ID changed")
	if int(first.get("xp", 0)) <= 140 or int(first.get("mastery_xp", 0)) <= 0:
		return _fail("Wilds dungeon reward did not scale XP/mastery")
	if str(first.get("school_id", "")) != "ember":
		return _fail("Regional reward did not map Ashen Fen to Ember mastery")
	var encounter: Dictionary = GATES.build_reward_event(node, "encounter", "encounter:test", 14, 4)
	if int(encounter.get("mastery_xp", -1)) != 0:
		return _fail("Ordinary encounter unexpectedly granted school mastery")
	if not GATES.build_reward_event(node, "unknown", "x", 14, 0).is_empty():
		return _fail("Unknown content type produced a progression reward")
	return true

func _validate_large_world_rewards() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var band_counts: Dictionary = {}
	var reward_ids: Dictionary = {}
	var total_estimated_xp: int = 0
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			return _fail("Progression gate received invalid graph node")
		var node: Dictionary = node_value as Dictionary
		var bundle: Dictionary = CONTENT_BUNDLE.compile_region(TEST_SEED, node)
		var band: String = str(node.get("progression_band", ""))
		band_counts[band] = int(band_counts.get(band, 0)) + 1
		var summary: Dictionary = GATES.reward_summary_for_bundle(node, bundle, int((GATES.BAND_RULES.get(band, {}) as Dictionary).get("recommended_level", 1)))
		if int(summary.get("content_count", 0)) <= 0 or int(summary.get("estimated_total_xp", 0)) <= 0:
			return _fail("Generated region lacks progression reward coverage")
		total_estimated_xp += int(summary.get("estimated_total_xp", 0))
		var entries: Array = bundle.get("encounters", []) as Array
		if not entries.is_empty():
			var content_id: String = str((entries[0] as Dictionary).get("stable_id", ""))
			var reward: Dictionary = GATES.build_reward_event(node, "encounter", content_id, 12, 0)
			var reward_id: String = str(reward.get("reward_id", ""))
			if reward_id.is_empty() or reward_ids.has(reward_id):
				return _fail("Regional progression reward IDs are missing or duplicated")
			reward_ids[reward_id] = true
	for band in ["heartland", "frontier", "wilds"]:
		if int(band_counts.get(band, 0)) <= 0:
			return _fail("Large-world progression gate missed band %s" % band)
	if total_estimated_xp < TEST_NODE_COUNT * 120:
		return _fail("Regional progression reward budget is unexpectedly sparse")
	return true

func _fail(message: String) -> bool:
	printerr("REGIONAL_PROGRESSION_GATE_FAILED: %s" % message)
	quit(1)
	return false
