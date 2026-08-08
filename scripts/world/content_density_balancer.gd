extends RefCounted
class_name ContentDensityBalancer

const FORMAT_VERSION: int = 1

const BAND_LIMITS: Dictionary = {
	"heartland": {"encounters": 4, "pois": 4, "loot": 4, "lore": 2, "events": 1},
	"frontier": {"encounters": 5, "pois": 5, "loot": 5, "lore": 2, "events": 2},
	"wilds": {"encounters": 6, "pois": 5, "loot": 6, "lore": 3, "events": 2}
}

const BIOME_DENSITY: Dictionary = {
	"green_highlands": 0.96,
	"blackwood": 1.08,
	"windscar_highlands": 0.92,
	"veilmoor": 1.05,
	"ashen_fen": 1.07,
	"frostmere": 0.94
}

static func balance(node: Dictionary) -> Dictionary:
	var profile: Dictionary = node.get("content_profile", {}) as Dictionary
	var band: String = str(node.get("progression_band", profile.get("progression_band", "heartland")))
	if not BAND_LIMITS.has(band):
		band = "heartland"
	var limits: Dictionary = BAND_LIMITS[band] as Dictionary
	var biome: String = str(node.get("biome", "green_highlands"))
	var scalar: float = float(BIOME_DENSITY.get(biome, 1.0))
	var danger: float = clampf(float(profile.get("danger", 0.3)), 0.0, 1.0)
	var secret: float = clampf(float(profile.get("secret_chance", 0.2)), 0.0, 0.85)
	var encounter_slots: int = clampi(roundi(float(int(profile.get("encounter_budget", 2))) * scalar), 1, int(limits.get("encounters", 4)))
	var poi_slots: int = clampi(roundi(float(int(profile.get("poi_budget", 3))) * scalar), 1, int(limits.get("pois", 4)))
	var loot_slots: int = clampi(1 + int(profile.get("loot_tier", 1)) + floori(float(poi_slots) / 2.0), 2, int(limits.get("loot", 4)))
	var lore_slots: int = clampi(1 + (1 if secret >= 0.34 else 0) + (1 if band == "wilds" and secret >= 0.48 else 0), 1, int(limits.get("lore", 2)))
	var event_slots: int = clampi(1 + (1 if band != "heartland" and danger >= 0.52 else 0), 1, int(limits.get("events", 1)))
	var weighted_total: float = float(encounter_slots) * 1.4 + float(poi_slots) * 1.15 + float(loot_slots) * 0.65 + float(lore_slots) * 0.45 + float(event_slots) * 0.80
	return {
		"format_version": FORMAT_VERSION,
		"region_id": str(node.get("stable_id", "")),
		"biome": biome,
		"progression_band": band,
		"encounter_slots": encounter_slots,
		"poi_slots": poi_slots,
		"loot_slots": loot_slots,
		"lore_slots": lore_slots,
		"event_slots": event_slots,
		"density_score": weighted_total,
		"limits": limits.duplicate(true)
	}

static func validate_budget(budget: Dictionary) -> bool:
	var band: String = str(budget.get("progression_band", ""))
	if not BAND_LIMITS.has(band):
		return false
	var limits: Dictionary = BAND_LIMITS[band] as Dictionary
	for pair in [["encounter_slots", "encounters"], ["poi_slots", "pois"], ["loot_slots", "loot"], ["lore_slots", "lore"], ["event_slots", "events"]]:
		var slot_key: String = str(pair[0])
		var limit_key: String = str(pair[1])
		var value: int = int(budget.get(slot_key, 0))
		if value <= 0 or value > int(limits.get(limit_key, 0)):
			return false
	return float(budget.get("density_score", 0.0)) > 0.0
