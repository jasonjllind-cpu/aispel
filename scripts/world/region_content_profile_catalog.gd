extends RefCounted
class_name RegionContentProfileCatalog

const PROFILE_FORMAT_VERSION: int = 1

const BIOME_BASES: Dictionary = {
	"green_highlands": {
		"encounter_profile": "warden_patrol",
		"encounter_budget": 2,
		"poi_budget": 3,
		"loot_tier": 1,
		"danger": 0.30,
		"secret_chance": 0.18,
		"settlement_affinity": 0.70
	},
	"blackwood": {
		"encounter_profile": "blackwood_ambush",
		"encounter_budget": 3,
		"poi_budget": 4,
		"loot_tier": 1,
		"danger": 0.46,
		"secret_chance": 0.30,
		"settlement_affinity": 0.30
	},
	"windscar_highlands": {
		"encounter_profile": "highland_guardians",
		"encounter_budget": 3,
		"poi_budget": 3,
		"loot_tier": 1,
		"danger": 0.42,
		"secret_chance": 0.22,
		"settlement_affinity": 0.38
	},
	"veilmoor": {
		"encounter_profile": "restless_dead",
		"encounter_budget": 3,
		"poi_budget": 4,
		"loot_tier": 1,
		"danger": 0.52,
		"secret_chance": 0.34,
		"settlement_affinity": 0.18
	}
}

const PROGRESSION_MODIFIERS: Dictionary = {
	"heartland": {
		"encounter_bonus": 0,
		"poi_bonus": 0,
		"loot_bonus": 0,
		"danger_bonus": 0.00,
		"secret_bonus": 0.00
	},
	"frontier": {
		"encounter_bonus": 1,
		"poi_bonus": 1,
		"loot_bonus": 1,
		"danger_bonus": 0.16,
		"secret_bonus": 0.08
	},
	"wilds": {
		"encounter_bonus": 2,
		"poi_bonus": 1,
		"loot_bonus": 2,
		"danger_bonus": 0.30,
		"secret_bonus": 0.15
	}
}

static func build_profile(biome_id: String, progression_band: String, graph_depth: int) -> Dictionary:
	var resolved_biome: String = biome_id if BIOME_BASES.has(biome_id) else "green_highlands"
	var resolved_band: String = progression_band if PROGRESSION_MODIFIERS.has(progression_band) else "heartland"
	var base: Dictionary = (BIOME_BASES[resolved_biome] as Dictionary).duplicate(true)
	var modifier: Dictionary = PROGRESSION_MODIFIERS[resolved_band] as Dictionary
	var depth: int = maxi(0, graph_depth)
	var depth_step: int = mini(4, depth)
	var encounter_budget: int = int(base.get("encounter_budget", 2)) + int(modifier.get("encounter_bonus", 0)) + floori(float(depth_step) / 2.0)
	var poi_budget: int = int(base.get("poi_budget", 3)) + int(modifier.get("poi_bonus", 0))
	var loot_tier: int = int(base.get("loot_tier", 1)) + int(modifier.get("loot_bonus", 0)) + floori(float(depth_step) / 3.0)
	var danger: float = clampf(float(base.get("danger", 0.30)) + float(modifier.get("danger_bonus", 0.0)) + float(depth_step) * 0.035, 0.0, 1.0)
	var secret_chance: float = clampf(float(base.get("secret_chance", 0.18)) + float(modifier.get("secret_bonus", 0.0)) + float(depth_step) * 0.015, 0.0, 0.85)
	return {
		"format_version": PROFILE_FORMAT_VERSION,
		"profile_id": "%s:%s:d%d" % [resolved_biome, resolved_band, depth],
		"biome": resolved_biome,
		"progression_band": resolved_band,
		"graph_depth": depth,
		"encounter_profile": str(base.get("encounter_profile", "warden_patrol")),
		"encounter_budget": encounter_budget,
		"poi_budget": poi_budget,
		"loot_tier": loot_tier,
		"danger": danger,
		"secret_chance": secret_chance,
		"settlement_affinity": clampf(float(base.get("settlement_affinity", 0.5)) - float(depth_step) * 0.04, 0.05, 0.95)
	}

static func known_biomes() -> Array[String]:
	var result: Array[String] = []
	for key in BIOME_BASES.keys():
		result.append(str(key))
	result.sort()
	return result
