extends RefCounted
class_name RegionContentThemeCatalog

const FORMAT_VERSION: int = 1

const THEMES: Dictionary = {
	"sunken_way": {
		"id": "sunken_way",
		"biome": "green_highlands",
		"weight": 1.0,
		"poi_palette": ["lost_camp", "wayside_ruin", "moon_hollow"],
		"encounter_palette": ["road_wardens", "relic_scavengers"],
		"loot_palette": ["ancient_coin", "moon_shard", "traveler_cache"],
		"landmark_palette": ["roadside_ruin", "moon_obelisk"],
		"tags": ["road", "ruins", "pilgrimage"]
	},
	"moonlit_heath": {
		"id": "moonlit_heath",
		"biome": "green_highlands",
		"weight": 0.8,
		"poi_palette": ["moon_hollow", "standing_stones", "hermit_fire"],
		"encounter_palette": ["moonbound_wolves", "wandering_warden"],
		"loot_palette": ["moon_shard", "herb_bundle", "old_relic"],
		"landmark_palette": ["moon_obelisk", "stone_circle"],
		"tags": ["moon", "open", "mystic"]
	},
	"thorn_chapel": {
		"id": "thorn_chapel",
		"biome": "blackwood",
		"weight": 1.0,
		"poi_palette": ["fallen_chapel", "root_cave", "hunter_camp"],
		"encounter_palette": ["blackwood_ambush", "thorn_cult"],
		"loot_palette": ["blackwood_relic", "ancient_coin", "grave_token"],
		"landmark_palette": ["forest_shrine", "fallen_chapel"],
		"tags": ["forest", "chapel", "cursed"]
	},
	"witchwood_hollows": {
		"id": "witchwood_hollows",
		"biome": "blackwood",
		"weight": 0.75,
		"poi_palette": ["witch_stones", "root_cave", "moon_hollow"],
		"encounter_palette": ["blackwood_stalkers", "restless_hunters"],
		"loot_palette": ["witch_charm", "moon_shard", "old_relic"],
		"landmark_palette": ["forest_shrine", "witch_stones"],
		"tags": ["forest", "witch", "secret"]
	},
	"storm_watch": {
		"id": "storm_watch",
		"biome": "windscar_highlands",
		"weight": 1.0,
		"poi_palette": ["broken_beacon", "watch_camp", "cliff_tomb"],
		"encounter_palette": ["highland_guardians", "storm_raiders"],
		"loot_palette": ["beacon_fragment", "ancient_coin", "storm_glass"],
		"landmark_palette": ["broken_beacon", "watchtower"],
		"tags": ["highland", "beacon", "storm"]
	},
	"giants_steps": {
		"id": "giants_steps",
		"biome": "windscar_highlands",
		"weight": 0.7,
		"poi_palette": ["giant_cairn", "cliff_tomb", "wind_shelter"],
		"encounter_palette": ["highland_guardians", "stonebound"],
		"loot_palette": ["giant_token", "storm_glass", "old_relic"],
		"landmark_palette": ["giant_cairn", "broken_beacon"],
		"tags": ["highland", "giant", "ancient"]
	},
	"pale_procession": {
		"id": "pale_procession",
		"biome": "veilmoor",
		"weight": 1.0,
		"poi_palette": ["grave_circle", "drowned_crypt", "funeral_camp"],
		"encounter_palette": ["restless_dead", "pale_wardens"],
		"loot_palette": ["grave_token", "moon_shard", "funeral_coin"],
		"landmark_palette": ["grave_circle", "pale_shrine"],
		"tags": ["moor", "graves", "undead"]
	},
	"drowned_bells": {
		"id": "drowned_bells",
		"biome": "veilmoor",
		"weight": 0.75,
		"poi_palette": ["drowned_crypt", "bell_ruin", "moon_hollow"],
		"encounter_palette": ["restless_dead", "bog_lurkers"],
		"loot_palette": ["bell_fragment", "grave_token", "old_relic"],
		"landmark_palette": ["pale_shrine", "bell_ruin"],
		"tags": ["moor", "bells", "fog"]
	},
	"cinder_march": {
		"id": "cinder_march",
		"biome": "ashen_fen",
		"weight": 1.0,
		"poi_palette": ["charred_watch", "sunk_kiln", "ember_camp"],
		"encounter_palette": ["fen_reavers", "cinder_hounds"],
		"loot_palette": ["ember_glass", "burnt_relic", "ancient_coin"],
		"landmark_palette": ["charred_watch", "ash_shrine"],
		"tags": ["fen", "ash", "fire", "ruins"]
	},
	"witchfire_bog": {
		"id": "witchfire_bog",
		"biome": "ashen_fen",
		"weight": 0.72,
		"poi_palette": ["witchfire_pool", "sunk_kiln", "bone_pier"],
		"encounter_palette": ["fen_reavers", "bog_witches"],
		"loot_palette": ["witch_ember", "grave_token", "old_relic"],
		"landmark_palette": ["ash_shrine", "bone_pier"],
		"tags": ["fen", "witch", "fire", "secret"]
	},
	"frozen_pilgrimage": {
		"id": "frozen_pilgrimage",
		"biome": "frostmere",
		"weight": 1.0,
		"poi_palette": ["frozen_waystone", "ice_tomb", "snowbound_camp"],
		"encounter_palette": ["frostbound", "white_wolves"],
		"loot_palette": ["frost_glass", "pilgrim_token", "old_relic"],
		"landmark_palette": ["frozen_waystone", "ice_tomb"],
		"tags": ["frost", "pilgrimage", "ancient", "open"]
	},
	"pale_lake": {
		"id": "pale_lake",
		"biome": "frostmere",
		"weight": 0.70,
		"poi_palette": ["ice_tomb", "frozen_boat", "wind_shelter"],
		"encounter_palette": ["frostbound", "lake_wraiths"],
		"loot_palette": ["frost_glass", "moon_shard", "drowned_relic"],
		"landmark_palette": ["frozen_waystone", "frozen_boat"],
		"tags": ["frost", "lake", "wraith", "vista"]
	}
}

static func get_theme(theme_id: String) -> Dictionary:
	var value: Variant = THEMES.get(theme_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in THEMES.keys():
		ids.append(str(key))
	ids.sort()
	return ids

static func get_ids_for_biome(biome_id: String) -> Array[String]:
	var ids: Array[String] = []
	for theme_id in get_ids():
		if str(get_theme(theme_id).get("biome", "")) == biome_id:
			ids.append(theme_id)
	return ids

static func select_theme(world_seed: int, stable_region_id: String, biome_id: String, progression_band: String) -> Dictionary:
	var candidates: Array[String] = get_ids_for_biome(biome_id)
	if candidates.is_empty():
		candidates = get_ids_for_biome("green_highlands")
	if candidates.is_empty():
		return {}
	var total_weight: float = 0.0
	for theme_id in candidates:
		total_weight += maxf(0.0, float(get_theme(theme_id).get("weight", 1.0)))
	if total_weight <= 0.0:
		return get_theme(candidates[0])
	var seed_value: int = int(("%d:%s:%s:content_theme:v%d" % [world_seed, stable_region_id, progression_band, FORMAT_VERSION]).hash() & 0x7fffffff)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var roll: float = rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for theme_id in candidates:
		cursor += maxf(0.0, float(get_theme(theme_id).get("weight", 1.0)))
		if roll <= cursor:
			return get_theme(theme_id)
	return get_theme(candidates.back())

static func validate_theme(theme: Dictionary) -> bool:
	if str(theme.get("id", "")).is_empty() or str(theme.get("biome", "")).is_empty():
		return false
	for key in ["poi_palette", "encounter_palette", "loot_palette", "landmark_palette", "tags"]:
		var value: Variant = theme.get(key, [])
		if not value is Array or (value as Array).is_empty():
			return false
	return true
