extends SceneTree

const POIS := preload("res://scripts/world/poi_archetype_catalog.gd")
const THEMES := preload("res://scripts/world/region_content_theme_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 63082601
const TEST_NODE_COUNT: int = 192

func _init() -> void:
	if not _validate_catalog_coverage():
		return
	if not _validate_graph_plans():
		return
	print("POI_ARCHETYPE_PLAN_OK archetypes=%d nodes=%d" % [POIS.get_ids().size(), TEST_NODE_COUNT])
	quit(0)

func _validate_catalog_coverage() -> bool:
	if POIS.get_ids().size() < 27:
		return _fail("POI expansion requires at least twenty-seven reusable archetypes")
	for archetype_id in POIS.get_ids():
		if not POIS.validate_archetype(POIS.get_archetype(archetype_id)):
			return _fail("POI archetype %s failed validation" % archetype_id)
	for theme_id in THEMES.get_ids():
		var theme: Dictionary = THEMES.get_theme(theme_id)
		for poi_value in theme.get("poi_palette", []) as Array:
			var poi_id: String = str(poi_value)
			if not POIS.validate_archetype(POIS.get_archetype(poi_id)):
				return _fail("Theme %s references missing POI %s" % [theme_id, poi_id])
	return true

func _validate_graph_plans() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var stable_ids: Dictionary = {}
	var categories: Dictionary = {}
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			return _fail("POI plan source contains invalid node")
		var node: Dictionary = node_value as Dictionary
		var stable_region_id: String = str(node.get("stable_id", ""))
		var theme: Dictionary = node.get("content_theme", {}) as Dictionary
		var profile: Dictionary = node.get("content_profile", {}) as Dictionary
		var radius: float = float(node.get("radius", 68.0))
		var first: Dictionary = POIS.build_region_plan(TEST_SEED, stable_region_id, theme, profile, radius)
		var second: Dictionary = POIS.build_region_plan(TEST_SEED, stable_region_id, theme, profile, radius)
		if var_to_str(first) != var_to_str(second):
			return _fail("POI plan is not deterministic for %s" % stable_region_id)
		var entries: Array = first.get("entries", []) as Array
		if entries.size() != clampi(int(profile.get("poi_budget", 3)), 1, 7):
			return _fail("POI budget mismatch for %s" % stable_region_id)
		for entry_value in entries:
			if not entry_value is Dictionary:
				return _fail("POI plan contains invalid entry")
			var entry: Dictionary = entry_value as Dictionary
			var stable_id: String = str(entry.get("stable_id", ""))
			if stable_id.is_empty() or stable_ids.has(stable_id):
				return _fail("POI stable IDs are missing or duplicated")
			stable_ids[stable_id] = true
			if str(entry.get("persistent_state_id", "")).is_empty():
				return _fail("POI plan entry lacks persistence metadata")
			var archetype: Dictionary = POIS.get_archetype(str(entry.get("archetype_id", "")))
			var road_distance: float = float(entry.get("preferred_road_distance", -1.0))
			if road_distance < float(archetype.get("road_min", 0.0)) - 0.001 or road_distance > minf(float(archetype.get("road_max", 999.0)), maxf(float(archetype.get("road_min", 0.0)) + 1.0, radius - 8.0)) + 0.001:
				return _fail("POI road-distance hint violates archetype placement rules")
			if float(entry.get("minimum_spacing", 0.0)) <= 0.0 or float(entry.get("reserved_footprint", 0.0)) <= 0.0:
				return _fail("POI plan lacks scalable spacing/footprint constraints")
			categories[str(entry.get("category", ""))] = true
	if categories.size() < 6:
		return _fail("Large graph did not expose enough POI category variety")
	return true

func _fail(message: String) -> bool:
	printerr("POI_ARCHETYPE_PLAN_FAILED: %s" % message)
	quit(1)
	return false
