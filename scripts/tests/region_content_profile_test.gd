extends SceneTree

const PROFILE_CATALOG := preload("res://scripts/world/region_content_profile_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

func _init() -> void:
	if not _validate_catalog_profiles():
		return
	if not _validate_graph_profiles():
		return
	print("REGION_CONTENT_PROFILE_OK")
	quit(0)

func _validate_catalog_profiles() -> bool:
	var biomes: Array[String] = PROFILE_CATALOG.known_biomes()
	if biomes.size() < 4:
		return _fail("Region content profile catalog is missing supported biomes")
	for biome_id in biomes:
		var heartland: Dictionary = PROFILE_CATALOG.build_profile(biome_id, "heartland", 0)
		var frontier: Dictionary = PROFILE_CATALOG.build_profile(biome_id, "frontier", 2)
		var wilds: Dictionary = PROFILE_CATALOG.build_profile(biome_id, "wilds", 5)
		for profile in [heartland, frontier, wilds]:
			if str(profile.get("profile_id", "")).is_empty():
				return _fail("Content profile has no stable profile ID")
			if str(profile.get("biome", "")) != biome_id:
				return _fail("Content profile lost biome identity")
			if int(profile.get("encounter_budget", 0)) <= 0 or int(profile.get("poi_budget", 0)) <= 0:
				return _fail("Content profile has an invalid generation budget")
			if int(profile.get("loot_tier", 0)) <= 0:
				return _fail("Content profile has an invalid loot tier")
			var danger: float = float(profile.get("danger", -1.0))
			var secret_chance: float = float(profile.get("secret_chance", -1.0))
			var settlement_affinity: float = float(profile.get("settlement_affinity", -1.0))
			if danger < 0.0 or danger > 1.0 or secret_chance < 0.0 or secret_chance > 1.0 or settlement_affinity < 0.0 or settlement_affinity > 1.0:
				return _fail("Content profile probability/intensity field is out of range")
		if float(frontier.get("danger", 0.0)) <= float(heartland.get("danger", 0.0)):
			return _fail("Frontier danger does not exceed heartland danger")
		if float(wilds.get("danger", 0.0)) <= float(frontier.get("danger", 0.0)):
			return _fail("Wilds danger does not exceed frontier danger")
		if int(wilds.get("loot_tier", 0)) <= int(heartland.get("loot_tier", 0)):
			return _fail("Wilds loot tier does not progress beyond heartland")
		if int(wilds.get("encounter_budget", 0)) <= int(heartland.get("encounter_budget", 0)):
			return _fail("Wilds encounter budget does not progress beyond heartland")

	var fallback: Dictionary = PROFILE_CATALOG.build_profile("unknown_biome", "unknown_band", -9)
	if str(fallback.get("biome", "")) != "green_highlands" or str(fallback.get("progression_band", "")) != "heartland" or int(fallback.get("graph_depth", -1)) != 0:
		return _fail("Content profile fallback is not deterministic and bounded")
	return true

func _validate_graph_profiles() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", 8242601)
	var graph: Dictionary = generator.call("generate_graph", 32)
	var duplicate: Dictionary = generator.call("generate_graph", 32)
	if var_to_str(graph) != var_to_str(duplicate):
		return _fail("Graph content profiles are not deterministic")
	var nodes_value: Variant = graph.get("nodes", null)
	if not nodes_value is Array:
		return _fail("Generated graph is missing nodes")
	var nodes: Array = nodes_value as Array
	if nodes.size() != 32:
		return _fail("Large graph profile test generated the wrong node count")
	var saw_frontier: bool = false
	var saw_wilds: bool = false
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Generated graph contains invalid node data")
		var node: Dictionary = node_value as Dictionary
		var profile_value: Variant = node.get("content_profile", null)
		if not profile_value is Dictionary:
			return _fail("Graph node is missing a content profile")
		var profile: Dictionary = profile_value as Dictionary
		if str(node.get("content_profile_id", "")) != str(profile.get("profile_id", "")):
			return _fail("Graph node content profile ID mismatch")
		if str(profile.get("biome", "")) != str(node.get("biome", "")):
			return _fail("Graph node content profile biome mismatch")
		if str(profile.get("progression_band", "")) != str(node.get("progression_band", "")):
			return _fail("Graph node content profile progression mismatch")
		if int(profile.get("graph_depth", -1)) != int(node.get("graph_depth", -2)):
			return _fail("Graph node content profile depth mismatch")
		if str(node.get("progression_band", "")) == "frontier":
			saw_frontier = true
		elif str(node.get("progression_band", "")) == "wilds":
			saw_wilds = true
	if not saw_frontier:
		return _fail("Large graph did not exercise frontier content profiles")
	if int(graph.get("max_graph_depth", 0)) >= 4 and not saw_wilds:
		return _fail("Large graph depth requires wilds content profiles")
	return true

func _fail(message: String) -> bool:
	printerr("REGION_CONTENT_PROFILE_FAILED: %s" % message)
	quit(1)
	return false
