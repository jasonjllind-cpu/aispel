extends SceneTree

const SETTLEMENTS := preload("res://scripts/world/settlement_archetype_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 64082601
const TEST_NODE_COUNT: int = 240

func _init() -> void:
	if not _validate_catalog():
		return
	if not _validate_graph_settlements():
		return
	print("SETTLEMENT_ARCHETYPE_PLAN_OK archetypes=%d nodes=%d" % [SETTLEMENTS.get_ids().size(), TEST_NODE_COUNT])
	quit(0)

func _validate_catalog() -> bool:
	if SETTLEMENTS.get_ids().size() < 8:
		return _fail("Settlement expansion requires at least eight archetypes")
	var covered_biomes: Dictionary = {}
	for archetype_id in SETTLEMENTS.get_ids():
		var archetype: Dictionary = SETTLEMENTS.get_archetype(archetype_id)
		if not SETTLEMENTS.validate_archetype(archetype):
			return _fail("Settlement archetype %s failed validation" % archetype_id)
		for biome_value in archetype.get("biomes", []) as Array:
			covered_biomes[str(biome_value)] = true
	for biome_id in ["green_highlands", "blackwood", "windscar_highlands", "veilmoor", "ashen_fen", "frostmere"]:
		if not covered_biomes.has(biome_id):
			return _fail("Settlement catalog does not cover biome %s" % biome_id)
	return true

func _validate_graph_settlements() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var settlement_count: int = 0
	var stable_ids: Dictionary = {}
	var service_types: Dictionary = {}
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		if str(node.get("distribution_role", "")) != "settlement":
			continue
		settlement_count += 1
		var first: Dictionary = SETTLEMENTS.build_plan(TEST_SEED, node)
		var second: Dictionary = SETTLEMENTS.build_plan(TEST_SEED, node)
		if var_to_str(first) != var_to_str(second):
			return _fail("Settlement plan is not deterministic")
		var stable_id: String = str(first.get("stable_id", ""))
		if stable_id.is_empty() or stable_ids.has(stable_id):
			return _fail("Settlement stable IDs are missing or duplicated")
		stable_ids[stable_id] = true
		if str(first.get("persistent_state_id", "")).is_empty() or int(first.get("population", 0)) <= 0:
			return _fail("Settlement lacks persistence or population metadata")
		var archetype: Dictionary = SETTLEMENTS.get_archetype(str(first.get("archetype_id", "")))
		if not (archetype.get("biomes", []) as Array).has(str(node.get("biome", ""))):
			return _fail("Settlement archetype does not match region biome")
		var services: Array = first.get("services", []) as Array
		if services.is_empty() or int(first.get("service_count", -1)) != services.size():
			return _fail("Settlement service profile is invalid")
		for service_value in services:
			service_types[str(service_value)] = true
	if settlement_count != int(graph.get("settlement_count", -1)) or settlement_count < 10:
		return _fail("Large graph did not produce the expected scalable settlement population")
	if service_types.size() < 5:
		return _fail("Settlement plans did not expose enough service variety")
	return true

func _fail(message: String) -> bool:
	printerr("SETTLEMENT_ARCHETYPE_PLAN_FAILED: %s" % message)
	quit(1)
	return false
