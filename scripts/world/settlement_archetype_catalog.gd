extends RefCounted
class_name SettlementArchetypeCatalog

const FORMAT_VERSION: int = 1

const ARCHETYPES: Dictionary = {
	"road_hamlet": {"biomes": ["green_highlands"], "weight": 1.2, "population_min": 18, "population_max": 42, "services": ["merchant", "rest", "rumors"]},
	"woodland_hold": {"biomes": ["blackwood"], "weight": 1.0, "population_min": 14, "population_max": 34, "services": ["merchant", "repair", "rest"]},
	"highland_outpost": {"biomes": ["windscar_highlands"], "weight": 1.0, "population_min": 12, "population_max": 30, "services": ["merchant", "repair", "rest"]},
	"moor_crossing": {"biomes": ["veilmoor"], "weight": 1.0, "population_min": 10, "population_max": 26, "services": ["merchant", "rest", "rumors"]},
	"ash_market": {"biomes": ["ashen_fen"], "weight": 1.0, "population_min": 16, "population_max": 38, "services": ["merchant", "repair", "rest", "rumors"]},
	"ember_refuge": {"biomes": ["ashen_fen"], "weight": 0.7, "population_min": 9, "population_max": 24, "services": ["healer", "rest", "shrine"]},
	"frostmere_lodge": {"biomes": ["frostmere"], "weight": 1.0, "population_min": 11, "population_max": 30, "services": ["merchant", "rest", "repair"]},
	"icebound_shrine": {"biomes": ["frostmere"], "weight": 0.55, "population_min": 6, "population_max": 18, "services": ["shrine", "healer", "rest"]}
}

static func get_archetype(archetype_id: String) -> Dictionary:
	var value: Variant = ARCHETYPES.get(archetype_id, {})
	if not value is Dictionary:
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["id"] = archetype_id
	return result

static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in ARCHETYPES.keys():
		ids.append(str(key))
	ids.sort()
	return ids

static func validate_archetype(archetype: Dictionary) -> bool:
	var biomes: Variant = archetype.get("biomes", [])
	var services: Variant = archetype.get("services", [])
	return not str(archetype.get("id", "")).is_empty() and biomes is Array and not (biomes as Array).is_empty() and services is Array and not (services as Array).is_empty() and float(archetype.get("weight", 0.0)) > 0.0 and int(archetype.get("population_min", 0)) > 0 and int(archetype.get("population_max", 0)) >= int(archetype.get("population_min", 0))

static func build_plan(world_seed: int, node: Dictionary) -> Dictionary:
	var stable_region_id: String = str(node.get("stable_id", ""))
	if str(node.get("distribution_role", "")) != "settlement" or stable_region_id.is_empty():
		return _empty_plan(stable_region_id)
	var biome_id: String = str(node.get("biome", "green_highlands"))
	var candidates: Array[String] = []
	var total_weight: float = 0.0
	for archetype_id in get_ids():
		var archetype: Dictionary = get_archetype(archetype_id)
		if not (archetype.get("biomes", []) as Array).has(biome_id):
			continue
		candidates.append(archetype_id)
		total_weight += float(archetype.get("weight", 1.0))
	if candidates.is_empty():
		return _empty_plan(stable_region_id)
	var seed_value: int = int(("%d:%s:settlement:v%d" % [world_seed, stable_region_id, FORMAT_VERSION]).hash() & 0x7fffffff)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var roll: float = rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	var selected_id: String = candidates.back()
	for archetype_id in candidates:
		cursor += float(get_archetype(archetype_id).get("weight", 1.0))
		if roll <= cursor:
			selected_id = archetype_id
			break
	var selected: Dictionary = get_archetype(selected_id)
	var population: int = rng.randi_range(int(selected.get("population_min", 1)), int(selected.get("population_max", 1)))
	var profile: Dictionary = node.get("content_profile", {}) as Dictionary
	var affinity: float = clampf(float(profile.get("settlement_affinity", 0.5)), 0.0, 1.0)
	population = maxi(1, roundi(float(population) * (0.8 + affinity * 0.4)))
	var services: Array = (selected.get("services", []) as Array).duplicate()
	services.sort()
	return {"format_version": FORMAT_VERSION, "seed": seed_value, "stable_id": "settlement:%s" % stable_region_id.trim_prefix("region:"), "persistent_state_id": "state:settlement:%s" % stable_region_id.trim_prefix("region:"), "region_id": stable_region_id, "archetype_id": selected_id, "biome": biome_id, "population": population, "services": services, "service_count": services.size()}

static func _empty_plan(stable_region_id: String) -> Dictionary:
	return {"format_version": FORMAT_VERSION, "seed": 0, "stable_id": "", "persistent_state_id": "", "region_id": stable_region_id, "archetype_id": "", "population": 0, "services": [], "service_count": 0}
