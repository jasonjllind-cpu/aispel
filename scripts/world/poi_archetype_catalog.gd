extends RefCounted
class_name PoiArchetypeCatalog

const FORMAT_VERSION: int = 1

const ARCHETYPES: Dictionary = {
	"lost_camp": {"category": "camp", "road_min": 10.0, "road_max": 24.0, "spacing": 22.0, "footprint": 7.0, "tags": ["road", "supplies"]},
	"wayside_ruin": {"category": "ruin", "road_min": 8.0, "road_max": 28.0, "spacing": 24.0, "footprint": 8.0, "tags": ["road", "ruins"]},
	"moon_hollow": {"category": "secret", "road_min": 18.0, "road_max": 38.0, "spacing": 26.0, "footprint": 6.0, "tags": ["moon", "secret"]},
	"standing_stones": {"category": "ritual", "road_min": 14.0, "road_max": 34.0, "spacing": 25.0, "footprint": 9.0, "tags": ["stones", "magic"]},
	"hermit_fire": {"category": "camp", "road_min": 18.0, "road_max": 36.0, "spacing": 22.0, "footprint": 5.0, "tags": ["hermit", "camp"]},
	"fallen_chapel": {"category": "ruin", "road_min": 12.0, "road_max": 34.0, "spacing": 28.0, "footprint": 10.0, "tags": ["chapel", "ruins"]},
	"root_cave": {"category": "cave", "road_min": 20.0, "road_max": 42.0, "spacing": 25.0, "footprint": 7.0, "tags": ["forest", "cave"]},
	"hunter_camp": {"category": "camp", "road_min": 12.0, "road_max": 30.0, "spacing": 22.0, "footprint": 6.0, "tags": ["hunter", "camp"]},
	"witch_stones": {"category": "ritual", "road_min": 20.0, "road_max": 42.0, "spacing": 27.0, "footprint": 8.0, "tags": ["witch", "secret"]},
	"broken_beacon": {"category": "ruin", "road_min": 8.0, "road_max": 26.0, "spacing": 28.0, "footprint": 10.0, "tags": ["beacon", "vista"]},
	"watch_camp": {"category": "camp", "road_min": 8.0, "road_max": 24.0, "spacing": 22.0, "footprint": 6.0, "tags": ["watch", "camp"]},
	"cliff_tomb": {"category": "tomb", "road_min": 20.0, "road_max": 44.0, "spacing": 27.0, "footprint": 8.0, "tags": ["tomb", "cliff"]},
	"giant_cairn": {"category": "monument", "road_min": 16.0, "road_max": 38.0, "spacing": 30.0, "footprint": 11.0, "tags": ["giant", "ancient"]},
	"wind_shelter": {"category": "shelter", "road_min": 10.0, "road_max": 28.0, "spacing": 20.0, "footprint": 5.0, "tags": ["wind", "shelter"]},
	"grave_circle": {"category": "grave", "road_min": 16.0, "road_max": 36.0, "spacing": 26.0, "footprint": 9.0, "tags": ["grave", "ritual"]},
	"drowned_crypt": {"category": "crypt", "road_min": 22.0, "road_max": 44.0, "spacing": 28.0, "footprint": 9.0, "tags": ["crypt", "moor"]},
	"funeral_camp": {"category": "camp", "road_min": 12.0, "road_max": 30.0, "spacing": 22.0, "footprint": 6.0, "tags": ["funeral", "camp"]},
	"bell_ruin": {"category": "ruin", "road_min": 15.0, "road_max": 36.0, "spacing": 26.0, "footprint": 9.0, "tags": ["bell", "ruins"]},
	"charred_watch": {"category": "ruin", "road_min": 9.0, "road_max": 28.0, "spacing": 27.0, "footprint": 9.0, "tags": ["ash", "watch"]},
	"sunk_kiln": {"category": "ruin", "road_min": 18.0, "road_max": 38.0, "spacing": 24.0, "footprint": 7.0, "tags": ["ash", "kiln"]},
	"ember_camp": {"category": "camp", "road_min": 10.0, "road_max": 28.0, "spacing": 21.0, "footprint": 6.0, "tags": ["fire", "camp"]},
	"witchfire_pool": {"category": "ritual", "road_min": 22.0, "road_max": 44.0, "spacing": 27.0, "footprint": 8.0, "tags": ["witch", "fire"]},
	"bone_pier": {"category": "ruin", "road_min": 18.0, "road_max": 40.0, "spacing": 25.0, "footprint": 8.0, "tags": ["bone", "fen"]},
	"frozen_waystone": {"category": "monument", "road_min": 8.0, "road_max": 28.0, "spacing": 26.0, "footprint": 8.0, "tags": ["frost", "road"]},
	"ice_tomb": {"category": "tomb", "road_min": 20.0, "road_max": 44.0, "spacing": 28.0, "footprint": 9.0, "tags": ["frost", "tomb"]},
	"snowbound_camp": {"category": "camp", "road_min": 10.0, "road_max": 30.0, "spacing": 22.0, "footprint": 6.0, "tags": ["frost", "camp"]},
	"frozen_boat": {"category": "wreck", "road_min": 22.0, "road_max": 46.0, "spacing": 27.0, "footprint": 9.0, "tags": ["lake", "wreck"]}
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
	return not str(archetype.get("id", "")).is_empty() \
		and not str(archetype.get("category", "")).is_empty() \
		and float(archetype.get("road_min", -1.0)) >= 0.0 \
		and float(archetype.get("road_max", 0.0)) > float(archetype.get("road_min", -1.0)) \
		and float(archetype.get("spacing", 0.0)) > 0.0 \
		and float(archetype.get("footprint", 0.0)) > 0.0 \
		and archetype.get("tags", []) is Array \
		and not (archetype.get("tags", []) as Array).is_empty()

static func build_region_plan(world_seed: int, stable_region_id: String, content_theme: Dictionary, content_profile: Dictionary, region_radius: float = 68.0) -> Dictionary:
	var palette_value: Variant = content_theme.get("poi_palette", [])
	if not palette_value is Array:
		return _empty_plan(stable_region_id)
	var palette: Array = palette_value as Array
	var candidates: Array[String] = []
	for value in palette:
		var archetype_id: String = str(value)
		if validate_archetype(get_archetype(archetype_id)):
			candidates.append(archetype_id)
	if candidates.is_empty():
		return _empty_plan(stable_region_id)
	var target_count: int = clampi(int(content_profile.get("poi_budget", 3)), 1, 7)
	var seed_value: int = int(("%d:%s:poi_plan:v%d" % [world_seed, stable_region_id, FORMAT_VERSION]).hash() & 0x7fffffff)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var entries: Array[Dictionary] = []
	for slot_index in range(target_count):
		var archetype_id: String = candidates[(slot_index + rng.randi_range(0, candidates.size() - 1)) % candidates.size()]
		var archetype: Dictionary = get_archetype(archetype_id)
		var road_min: float = float(archetype.get("road_min", 10.0))
		var road_max: float = minf(float(archetype.get("road_max", 36.0)), maxf(road_min + 1.0, region_radius - 8.0))
		var road_distance: float = rng.randf_range(road_min, road_max)
		var stable_id: String = "poi_plan:%s:%d:%s" % [stable_region_id.trim_prefix("region:"), slot_index, archetype_id]
		entries.append({
			"stable_id": stable_id,
			"persistent_state_id": "state:%s" % stable_id,
			"archetype_id": archetype_id,
			"category": str(archetype.get("category", "minor")),
			"preferred_road_distance": road_distance,
			"minimum_spacing": float(archetype.get("spacing", 20.0)),
			"reserved_footprint": float(archetype.get("footprint", 6.0)),
			"angle_hint": rng.randf_range(-PI, PI),
			"tags": (archetype.get("tags", []) as Array).duplicate()
		})
	return {
		"format_version": FORMAT_VERSION,
		"seed": seed_value,
		"region_id": stable_region_id,
		"entries": entries,
		"target_count": target_count
	}

static func _empty_plan(stable_region_id: String) -> Dictionary:
	return {"format_version": FORMAT_VERSION, "seed": 0, "region_id": stable_region_id, "entries": [], "target_count": 0}
