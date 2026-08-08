extends SceneTree

const BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")
const BIOME_MAP := preload("res://scripts/world/biome_map.gd")
const TEMPLATE_CATALOG := preload("res://scripts/world/region_template_catalog.gd")
const PROFILE_CATALOG := preload("res://scripts/world/region_content_profile_catalog.gd")
const THEME_CATALOG := preload("res://scripts/world/region_content_theme_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 6082601
const TEST_NODE_COUNT: int = 384
const EXPANDED_BIOMES: Array[String] = ["ashen_fen", "frostmere"]

func _init() -> void:
	if not _validate_biome_data():
		return
	if not _validate_climate_mapping():
		return
	if not _validate_content_layers():
		return
	if not _validate_macro_graph_expansion():
		return
	print("WORLD_CONTENT_EXPANSION_OK biomes=%d nodes=%d" % [BIOME_CATALOG.get_ids().size(), TEST_NODE_COUNT])
	quit(0)

func _validate_biome_data() -> bool:
	var ids: Array[String] = BIOME_CATALOG.get_ids()
	if ids.size() < 6:
		return _fail("World expansion requires at least six biome identities")
	for biome_id in EXPANDED_BIOMES:
		if not BIOME_CATALOG.has_biome(biome_id):
			return _fail("Missing expanded biome %s" % biome_id)
		var biome: Dictionary = BIOME_CATALOG.get_biome(biome_id)
		for key in ["display_name", "ground_color", "road_color", "tree_density", "rock_density", "encounter_profile"]:
			if not biome.has(key):
				return _fail("Biome %s is missing %s" % [biome_id, key])
	return true

func _validate_climate_mapping() -> bool:
	var biome_map: RefCounted = BIOME_MAP.new()
	biome_map.call("configure", TEST_SEED)
	if str(biome_map.call("_climate_biome", 0.18, 0.45)) != "frostmere":
		return _fail("Cold climate does not map to Frostmere")
	if str(biome_map.call("_climate_biome", 0.82, 0.72)) != "ashen_fen":
		return _fail("Hot wet climate does not map to Ashen Fen")
	var frost_transition: String = str(biome_map.call("_alternate_biome", "frostmere", 0.22, 0.42))
	var fen_transition: String = str(biome_map.call("_alternate_biome", "ashen_fen", 0.76, 0.54))
	if frost_transition == "frostmere" or fen_transition == "ashen_fen":
		return _fail("Expanded biomes do not expose transition neighbours")
	return true

func _validate_content_layers() -> bool:
	for biome_id in EXPANDED_BIOMES:
		var rng := RandomNumberGenerator.new()
		rng.seed = TEST_SEED
		var template_id: String = TEMPLATE_CATALOG.weighted_pick(rng, [biome_id])
		var template: Dictionary = TEMPLATE_CATALOG.get_template(template_id)
		if str(template.get("biome", "")) != biome_id:
			return _fail("No region template is available for %s" % biome_id)
		var profile: Dictionary = PROFILE_CATALOG.build_profile(biome_id, "frontier", 3)
		if str(profile.get("biome", "")) != biome_id or int(profile.get("encounter_budget", 0)) <= 0:
			return _fail("Content profile did not preserve %s" % biome_id)
		var themes: Array[String] = THEME_CATALOG.get_ids_for_biome(biome_id)
		if themes.size() < 2:
			return _fail("Biome %s needs at least two deterministic themes" % biome_id)
		for theme_id in themes:
			if not THEME_CATALOG.validate_theme(THEME_CATALOG.get_theme(theme_id)):
				return _fail("Expanded theme %s failed validation" % theme_id)
		var first: Dictionary = THEME_CATALOG.select_theme(TEST_SEED, "region:test:%s" % biome_id, biome_id, "frontier")
		var second: Dictionary = THEME_CATALOG.select_theme(TEST_SEED, "region:test:%s" % biome_id, biome_id, "frontier")
		if var_to_str(first) != var_to_str(second):
			return _fail("Theme selection is not deterministic for %s" % biome_id)
	return true

func _validate_macro_graph_expansion() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var first: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var second: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	if var_to_str(first) != var_to_str(second):
		return _fail("Expanded macro graph is not deterministic")
	var observed: Dictionary = {}
	for node_value in first.get("nodes", []) as Array:
		if node_value is Dictionary:
			observed[str((node_value as Dictionary).get("biome", ""))] = true
	for biome_id in EXPANDED_BIOMES:
		if not observed.has(biome_id):
			return _fail("Macro graph did not distribute expanded biome %s" % biome_id)
	return true

func _fail(message: String) -> bool:
	printerr("WORLD_CONTENT_EXPANSION_FAILED: %s" % message)
	quit(1)
	return false
