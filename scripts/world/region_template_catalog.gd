extends RefCounted
class_name RegionTemplateCatalog

const TEMPLATES: Dictionary = {
	"green_frontier": {
		"id": "green_frontier",
		"display_name": "Green Frontier",
		"biome": "green_highlands",
		"weight": 1.25,
		"radius": 68.0,
		"poi_count": 3,
		"landmark_module": "roadside_ruin",
		"tags": ["open", "road", "ruins"]
	},
	"blackwood_depths": {
		"id": "blackwood_depths",
		"display_name": "Blackwood Depths",
		"biome": "blackwood",
		"weight": 1.00,
		"radius": 66.0,
		"poi_count": 4,
		"landmark_module": "forest_shrine",
		"tags": ["forest", "mist", "graves"]
	},
	"windscar_pass": {
		"id": "windscar_pass",
		"display_name": "Windscar Pass",
		"biome": "windscar_highlands",
		"weight": 0.90,
		"radius": 70.0,
		"poi_count": 3,
		"landmark_module": "broken_beacon",
		"tags": ["highland", "rocks", "vista"]
	},
	"veilmoor_reach": {
		"id": "veilmoor_reach",
		"display_name": "Veilmoor Reach",
		"biome": "veilmoor",
		"weight": 0.95,
		"radius": 67.0,
		"poi_count": 4,
		"landmark_module": "grave_circle",
		"tags": ["moor", "undead", "fog"]
	},
	"moonfall_grove": {
		"id": "moonfall_grove",
		"display_name": "Moonfall Grove",
		"biome": "green_highlands",
		"weight": 0.55,
		"radius": 65.0,
		"poi_count": 3,
		"landmark_module": "moon_obelisk",
		"tags": ["magic", "grove", "secret"]
	}
}

static func get_template(template_id: String) -> Dictionary:
	var value: Variant = TEMPLATES.get(template_id, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

static func get_ids() -> Array[String]:
	var result: Array[String] = []
	for key in TEMPLATES.keys():
		result.append(str(key))
	result.sort()
	return result

static func get_weight(template_id: String) -> float:
	return maxf(0.0, float(get_template(template_id).get("weight", 0.0)))

static func weighted_pick(rng: RandomNumberGenerator, allowed_biomes: Array[String] = []) -> String:
	var candidates: Array[String] = []
	var total_weight: float = 0.0
	for template_id in get_ids():
		var definition: Dictionary = get_template(template_id)
		var biome_id: String = str(definition.get("biome", "green_highlands"))
		if not allowed_biomes.is_empty() and not allowed_biomes.has(biome_id):
			continue
		var weight: float = maxf(0.0, float(definition.get("weight", 0.0)))
		if weight <= 0.0:
			continue
		candidates.append(template_id)
		total_weight += weight
	if candidates.is_empty() or total_weight <= 0.0:
		return "green_frontier"
	var roll: float = rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for template_id in candidates:
		cursor += get_weight(template_id)
		if roll <= cursor:
			return template_id
	return candidates[candidates.size() - 1]
