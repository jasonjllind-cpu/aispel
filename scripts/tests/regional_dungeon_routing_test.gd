extends SceneTree

const DUNGEONS := preload("res://scripts/dungeon/regional_dungeon_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 65082601
const TEST_NODE_COUNT: int = 320

func _init() -> void:
	if not _validate_catalog():
		return
	if not _validate_graph_routing():
		return
	print("REGIONAL_DUNGEON_ROUTING_OK themes=%d nodes=%d" % [DUNGEONS.get_ids().size(), TEST_NODE_COUNT])
	quit(0)

func _validate_catalog() -> bool:
	if DUNGEONS.get_ids().size() < 6:
		return _fail("Regional dungeon routing requires at least six dungeon themes")
	var covered_biomes: Dictionary = {}
	for theme_id in DUNGEONS.get_ids():
		var theme: Dictionary = DUNGEONS.get_theme(theme_id)
		if not DUNGEONS.validate_theme(theme):
			return _fail("Dungeon theme %s failed validation" % theme_id)
		for biome_value in theme.get("biomes", []) as Array:
			covered_biomes[str(biome_value)] = true
	for biome_id in ["green_highlands", "blackwood", "windscar_highlands", "veilmoor", "ashen_fen", "frostmere"]:
		if not covered_biomes.has(biome_id):
			return _fail("Dungeon themes do not cover biome %s" % biome_id)
	return true

func _validate_graph_routing() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var enabled_count: int = 0
	var stable_ids: Dictionary = {}
	var observed_themes: Dictionary = {}
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		var first: Dictionary = DUNGEONS.build_region_plan(TEST_SEED, node)
		var second: Dictionary = DUNGEONS.build_region_plan(TEST_SEED, node)
		if var_to_str(first) != var_to_str(second):
			return _fail("Dungeon routing is not deterministic")
		if not bool(first.get("enabled", false)):
			continue
		enabled_count += 1
		var stable_id: String = str(first.get("stable_id", ""))
		if stable_id.is_empty() or stable_ids.has(stable_id):
			return _fail("Dungeon routing IDs are missing or duplicated")
		stable_ids[stable_id] = true
		if str(first.get("persistent_state_id", "")).is_empty() or str(first.get("entrance_family", "")).is_empty() or str(first.get("room_family", "")).is_empty():
			return _fail("Dungeon routing lacks persistence or family metadata")
		var theme: Dictionary = DUNGEONS.get_theme(str(first.get("theme_id", "")))
		if not (theme.get("biomes", []) as Array).has(str(node.get("biome", ""))):
			return _fail("Dungeon theme does not match source biome")
		if int(first.get("graph_depth", -1)) < int(theme.get("min_depth", 0)):
			return _fail("Dungeon route violated minimum graph depth")
		observed_themes[str(first.get("theme_id", ""))] = true
	if enabled_count < 24:
		return _fail("Large graph generated too few regional dungeon entrances")
	if observed_themes.size() < 5:
		return _fail("Large graph did not expose enough dungeon-theme variety")
	return true

func _fail(message: String) -> bool:
	printerr("REGIONAL_DUNGEON_ROUTING_FAILED: %s" % message)
	quit(1)
	return false
