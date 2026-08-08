extends SceneTree

const LOOT := preload("res://scripts/world/regional_loot_catalog.gd")
const THEMES := preload("res://scripts/world/region_content_theme_catalog.gd")
const PROFILES := preload("res://scripts/world/region_content_profile_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 62082601
const TEST_NODE_COUNT: int = 192

func _init() -> void:
	if not _validate_catalog_coverage():
		return
	if not _validate_progression_scaling():
		return
	if not _validate_graph_plans():
		return
	print("REGIONAL_LOOT_PLAN_OK items=%d nodes=%d" % [LOOT.get_ids().size(), TEST_NODE_COUNT])
	quit(0)

func _validate_catalog_coverage() -> bool:
	if LOOT.get_ids().size() < 19:
		return _fail("Regional loot expansion requires at least nineteen reusable rewards")
	for item_id in LOOT.get_ids():
		if not LOOT.validate_item(LOOT.get_item(item_id)):
			return _fail("Loot item %s failed validation" % item_id)
	for theme_id in THEMES.get_ids():
		var theme: Dictionary = THEMES.get_theme(theme_id)
		for loot_value in theme.get("loot_palette", []) as Array:
			var item_id: String = str(loot_value)
			if not LOOT.validate_item(LOOT.get_item(item_id)):
				return _fail("Theme %s references missing loot %s" % [theme_id, item_id])
	return true

func _validate_progression_scaling() -> bool:
	var theme: Dictionary = THEMES.get_theme("witchfire_bog")
	var heartland: Dictionary = PROFILES.build_profile("ashen_fen", "heartland", 0)
	var wilds: Dictionary = PROFILES.build_profile("ashen_fen", "wilds", 5)
	var low_plan: Dictionary = LOOT.build_region_plan(TEST_SEED, "region:loot:scale", theme, heartland)
	var high_plan: Dictionary = LOOT.build_region_plan(TEST_SEED, "region:loot:scale", theme, wilds)
	if int(high_plan.get("loot_tier", 0)) <= int(low_plan.get("loot_tier", 0)):
		return _fail("Loot tier does not scale with progression")
	if (high_plan.get("entries", []) as Array).size() < (low_plan.get("entries", []) as Array).size():
		return _fail("Higher progression reduced regional reward count")
	if int(high_plan.get("total_value", 0)) <= int(low_plan.get("total_value", 0)):
		return _fail("Higher progression did not increase reward value")
	var high_has_epic: bool = false
	for entry_value in high_plan.get("entries", []) as Array:
		if entry_value is Dictionary and str((entry_value as Dictionary).get("rarity", "")) == "epic":
			high_has_epic = true
			break
	if not high_has_epic:
		return _fail("Tier-three loot plan did not expose its epic reward band")
	return true

func _validate_graph_plans() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var stable_ids: Dictionary = {}
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			return _fail("Loot plan source contains invalid node")
		var node: Dictionary = node_value as Dictionary
		var stable_region_id: String = str(node.get("stable_id", ""))
		var theme: Dictionary = node.get("content_theme", {}) as Dictionary
		var profile: Dictionary = node.get("content_profile", {}) as Dictionary
		var first: Dictionary = LOOT.build_region_plan(TEST_SEED, stable_region_id, theme, profile)
		var second: Dictionary = LOOT.build_region_plan(TEST_SEED, stable_region_id, theme, profile)
		if var_to_str(first) != var_to_str(second):
			return _fail("Loot plan is not deterministic for %s" % stable_region_id)
		var entries: Array = first.get("entries", []) as Array
		if entries.is_empty() or int(first.get("total_value", 0)) <= 0:
			return _fail("Loot plan is empty for %s" % stable_region_id)
		for entry_value in entries:
			if not entry_value is Dictionary:
				return _fail("Loot plan contains invalid entry")
			var entry: Dictionary = entry_value as Dictionary
			var stable_id: String = str(entry.get("stable_id", ""))
			if stable_id.is_empty() or stable_ids.has(stable_id):
				return _fail("Loot plan IDs are missing or not globally stable")
			stable_ids[stable_id] = true
			if str(entry.get("persistent_state_id", "")).is_empty() or int(entry.get("amount", 0)) <= 0 or int(entry.get("value", 0)) <= 0:
				return _fail("Loot entry lacks scalable persistence/value metadata")
			if not LOOT.RARITY_ORDER.has(str(entry.get("rarity", ""))):
				return _fail("Loot entry has invalid rarity")
	return true

func _fail(message: String) -> bool:
	printerr("REGIONAL_LOOT_PLAN_FAILED: %s" % message)
	quit(1)
	return false
