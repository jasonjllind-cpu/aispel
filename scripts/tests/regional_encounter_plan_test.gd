extends SceneTree

const ENCOUNTERS := preload("res://scripts/world/encounter_archetype_catalog.gd")
const THEMES := preload("res://scripts/world/region_content_theme_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 61082601
const TEST_NODE_COUNT: int = 192

func _init() -> void:
	if not _validate_catalog_coverage():
		return
	if not _validate_graph_plans():
		return
	print("REGIONAL_ENCOUNTER_PLAN_OK archetypes=%d nodes=%d" % [ENCOUNTERS.get_ids().size(), TEST_NODE_COUNT])
	quit(0)

func _validate_catalog_coverage() -> bool:
	if ENCOUNTERS.get_ids().size() < 20:
		return _fail("Encounter expansion requires at least twenty reusable archetypes")
	for archetype_id in ENCOUNTERS.get_ids():
		if not ENCOUNTERS.validate_archetype(ENCOUNTERS.get_archetype(archetype_id)):
			return _fail("Encounter archetype %s failed validation" % archetype_id)
	for theme_id in THEMES.get_ids():
		var theme: Dictionary = THEMES.get_theme(theme_id)
		for encounter_value in theme.get("encounter_palette", []) as Array:
			var encounter_id: String = str(encounter_value)
			if not ENCOUNTERS.validate_archetype(ENCOUNTERS.get_archetype(encounter_id)):
				return _fail("Theme %s references missing encounter %s" % [theme_id, encounter_id])
	return true

func _validate_graph_plans() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var repeated: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	if var_to_str(graph) != var_to_str(repeated):
		return _fail("Graph changed while validating encounter plans")
	var stable_ids: Dictionary = {}
	var observed_biomes: Dictionary = {}
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			return _fail("Encounter plan source contains invalid node")
		var node: Dictionary = node_value as Dictionary
		var stable_region_id: String = str(node.get("stable_id", ""))
		var theme: Dictionary = node.get("content_theme", {}) as Dictionary
		var profile: Dictionary = node.get("content_profile", {}) as Dictionary
		var first: Dictionary = ENCOUNTERS.build_region_plan(TEST_SEED, stable_region_id, theme, profile)
		var second: Dictionary = ENCOUNTERS.build_region_plan(TEST_SEED, stable_region_id, theme, profile)
		if var_to_str(first) != var_to_str(second):
			return _fail("Encounter plan is not deterministic for %s" % stable_region_id)
		var entries: Array = first.get("entries", []) as Array
		if entries.size() != maxi(1, int(profile.get("encounter_budget", 1))):
			return _fail("Encounter budget mismatch for %s" % stable_region_id)
		if float(first.get("total_threat", 0.0)) <= 0.0:
			return _fail("Encounter threat summary is empty for %s" % stable_region_id)
		for entry_value in entries:
			if not entry_value is Dictionary:
				return _fail("Encounter plan contains invalid entry")
			var entry: Dictionary = entry_value as Dictionary
			var encounter_id: String = str(entry.get("stable_id", ""))
			if encounter_id.is_empty() or stable_ids.has(encounter_id):
				return _fail("Encounter plan IDs are missing or not globally stable")
			stable_ids[encounter_id] = true
			if int(entry.get("group_size", 0)) <= 0 or str(entry.get("persistent_state_id", "")).is_empty():
				return _fail("Encounter plan entry lacks scalable state metadata")
		observed_biomes[str(node.get("biome", ""))] = true
	for expanded_biome in ["ashen_fen", "frostmere"]:
		if not observed_biomes.has(expanded_biome):
			return _fail("Large graph missed expanded encounter biome %s" % expanded_biome)
	return true

func _fail(message: String) -> bool:
	printerr("REGIONAL_ENCOUNTER_PLAN_FAILED: %s" % message)
	quit(1)
	return false
