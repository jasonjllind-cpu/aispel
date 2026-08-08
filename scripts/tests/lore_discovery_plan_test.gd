extends SceneTree

const LORE := preload("res://scripts/world/lore_discovery_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 67082601
const TEST_NODE_COUNT: int = 240

func _init() -> void:
	if not _validate_catalog():
		return
	if not _validate_plans():
		return
	print("LORE_DISCOVERY_PLAN_OK records=%d nodes=%d" % [LORE.get_ids().size(), TEST_NODE_COUNT])
	quit(0)

func _validate_catalog() -> bool:
	if LORE.get_ids().size() < 18:
		return _fail("Lore expansion requires at least eighteen records")
	var covered_biomes: Dictionary = {}
	var types: Dictionary = {}
	for record_id in LORE.get_ids():
		var record: Dictionary = LORE.get_record(record_id)
		if not LORE.validate_record(record):
			return _fail("Lore record %s failed validation" % record_id)
		types[str(record.get("type", ""))] = true
		for biome_value in record.get("biomes", []) as Array:
			covered_biomes[str(biome_value)] = true
	if types.size() != 4:
		return _fail("Lore catalog does not cover all discovery types")
	for biome_id in ["green_highlands", "blackwood", "windscar_highlands", "veilmoor", "ashen_fen", "frostmere"]:
		if not covered_biomes.has(biome_id):
			return _fail("Lore catalog does not cover biome %s" % biome_id)
	return true

func _validate_plans() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var stable_ids: Dictionary = {}
	var collections: Dictionary = {}
	var total_records: int = 0
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		var first: Dictionary = LORE.build_region_plan(TEST_SEED, node)
		var second: Dictionary = LORE.build_region_plan(TEST_SEED, node)
		if var_to_str(first) != var_to_str(second):
			return _fail("Lore discovery plan is not deterministic")
		for entry_value in first.get("entries", []) as Array:
			if not entry_value is Dictionary:
				return _fail("Lore plan contains invalid entry")
			var entry: Dictionary = entry_value as Dictionary
			total_records += 1
			var stable_id: String = str(entry.get("stable_id", ""))
			if stable_id.is_empty() or stable_ids.has(stable_id):
				return _fail("Lore stable IDs are missing or duplicated")
			stable_ids[stable_id] = true
			if str(entry.get("persistent_state_id", "")).is_empty() or str(entry.get("title", "")).is_empty():
				return _fail("Lore discovery lacks persistence or presentation metadata")
			var record: Dictionary = LORE.get_record(str(entry.get("record_id", "")))
			if not (record.get("biomes", []) as Array).has(str(node.get("biome", ""))):
				return _fail("Lore discovery does not match region biome")
			collections[str(entry.get("collection", ""))] = true
	if total_records < TEST_NODE_COUNT:
		return _fail("Lore discovery did not cover the macro world")
	if collections.size() < 7:
		return _fail("Lore plans did not expose enough collection variety")
	return true

func _fail(message: String) -> bool:
	printerr("LORE_DISCOVERY_PLAN_FAILED: %s" % message)
	quit(1)
	return false
