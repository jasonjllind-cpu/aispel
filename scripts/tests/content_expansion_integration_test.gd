extends SceneTree

const BUNDLE := preload("res://scripts/world/region_content_bundle.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 69082601
const TEST_NODE_COUNT: int = 512
const MAX_RUNTIME_MS: int = 30000

func _init() -> void:
	var started_ms: int = Time.get_ticks_msec()
	if not _validate_integration():
		return
	var elapsed_ms: int = Time.get_ticks_msec() - started_ms
	if elapsed_ms > MAX_RUNTIME_MS:
		_fail("Integrated content generation exceeded runtime gate: %d ms" % elapsed_ms)
		return
	print("CONTENT_EXPANSION_INTEGRATION_OK nodes=%d elapsed_ms=%d" % [TEST_NODE_COUNT, elapsed_ms])
	quit(0)

func _validate_integration() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var repeated_graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	if var_to_str(graph) != var_to_str(repeated_graph):
		return _fail("Macro graph changed during content integration gate")
	var nodes: Array = graph.get("nodes", []) as Array
	if nodes.size() != TEST_NODE_COUNT:
		return _fail("Integration gate received the wrong node count")
	var global_persistent_ids: Dictionary = {}
	var biomes: Dictionary = {}
	var bands: Dictionary = {}
	var total_content: int = 0
	var settlement_count: int = 0
	var dungeon_count: int = 0
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Integration gate encountered invalid node")
		var node: Dictionary = node_value as Dictionary
		var first: Dictionary = BUNDLE.compile_region(TEST_SEED, node)
		var second: Dictionary = BUNDLE.compile_region(TEST_SEED, node)
		if var_to_str(first) != var_to_str(second):
			return _fail("Region content bundle is not deterministic")
		if not BUNDLE.validate_bundle(first):
			return _fail("Region content bundle failed structural validation")
		if str(first.get("region_id", "")) != str(node.get("stable_id", "")):
			return _fail("Region content bundle lost its source region identity")
		biomes[str(first.get("biome", ""))] = true
		bands[str(first.get("progression_band", ""))] = true
		var counts: Dictionary = first.get("counts", {}) as Dictionary
		for key in ["encounters", "loot", "pois", "world_events", "lore"]:
			total_content += int(counts.get(key, 0))
		settlement_count += int(counts.get("settlement", 0))
		dungeon_count += int(counts.get("dungeon", 0))
		for persistent_id in BUNDLE.persistent_ids(first):
			if persistent_id.is_empty() or global_persistent_ids.has(persistent_id):
				return _fail("Integrated content persistence IDs are missing or duplicated globally")
			global_persistent_ids[persistent_id] = true
		var settlement: Dictionary = first.get("settlement", {}) as Dictionary
		if str(node.get("distribution_role", "")) == "settlement" and str(settlement.get("stable_id", "")).is_empty():
			return _fail("Distributed settlement region did not compile a settlement plan")
	for biome_id in ["green_highlands", "blackwood", "windscar_highlands", "veilmoor", "ashen_fen", "frostmere"]:
		if not biomes.has(biome_id):
			return _fail("Integration gate missed biome %s" % biome_id)
	for band in ["heartland", "frontier", "wilds"]:
		if not bands.has(band):
			return _fail("Integration gate missed progression band %s" % band)
	if total_content < TEST_NODE_COUNT * 6:
		return _fail("Integrated regions are unexpectedly content-sparse")
	if settlement_count != int(graph.get("settlement_count", -1)):
		return _fail("Settlement integration diverged from world distribution")
	if dungeon_count < 40:
		return _fail("Integrated world generated too few regional dungeons")
	if global_persistent_ids.size() <= total_content:
		return _fail("Integrated state namespace did not include settlement/dungeon persistence")
	return true

func _fail(message: String) -> bool:
	printerr("CONTENT_EXPANSION_INTEGRATION_FAILED: %s" % message)
	quit(1)
	return false
