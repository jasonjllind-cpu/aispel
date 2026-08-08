extends RefCounted
class_name WorldEventCatalog

const FORMAT_VERSION: int = 1

const EVENTS: Dictionary = {
	"road_pilgrims": {"biomes": ["green_highlands"], "period_days": 3, "duration_hours": 8, "min_depth": 0, "weight": 1.0, "tags": ["travel", "social"]},
	"moon_omens": {"biomes": ["green_highlands", "veilmoor"], "period_days": 5, "duration_hours": 6, "min_depth": 1, "weight": 0.8, "tags": ["moon", "mystic"]},
	"blackwood_hunt": {"biomes": ["blackwood"], "period_days": 4, "duration_hours": 10, "min_depth": 1, "weight": 1.0, "tags": ["forest", "hunt"]},
	"thorn_procession": {"biomes": ["blackwood"], "period_days": 7, "duration_hours": 7, "min_depth": 2, "weight": 0.65, "tags": ["cult", "ritual"]},
	"storm_front": {"biomes": ["windscar_highlands"], "period_days": 3, "duration_hours": 9, "min_depth": 1, "weight": 1.0, "tags": ["storm", "hazard"]},
	"stone_waking": {"biomes": ["windscar_highlands"], "period_days": 8, "duration_hours": 5, "min_depth": 3, "weight": 0.55, "tags": ["ancient", "guardian"]},
	"pale_procession": {"biomes": ["veilmoor"], "period_days": 4, "duration_hours": 8, "min_depth": 1, "weight": 1.0, "tags": ["undead", "ritual"]},
	"fen_fire": {"biomes": ["ashen_fen"], "period_days": 3, "duration_hours": 7, "min_depth": 1, "weight": 1.0, "tags": ["fen", "fire"]},
	"reaver_muster": {"biomes": ["ashen_fen"], "period_days": 6, "duration_hours": 10, "min_depth": 2, "weight": 0.75, "tags": ["raid", "combat"]},
	"whiteout": {"biomes": ["frostmere"], "period_days": 3, "duration_hours": 9, "min_depth": 1, "weight": 1.0, "tags": ["frost", "hazard"]},
	"ice_lanterns": {"biomes": ["frostmere"], "period_days": 6, "duration_hours": 6, "min_depth": 2, "weight": 0.7, "tags": ["frost", "mystic"]}
}

static func get_event(event_id: String) -> Dictionary:
	var value: Variant = EVENTS.get(event_id, {})
	if not value is Dictionary:
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["id"] = event_id
	return result

static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in EVENTS.keys():
		ids.append(str(key))
	ids.sort()
	return ids

static func validate_event(event: Dictionary) -> bool:
	return not str(event.get("id", "")).is_empty() \
		and event.get("biomes", []) is Array and not (event.get("biomes", []) as Array).is_empty() \
		and int(event.get("period_days", 0)) > 0 \
		and int(event.get("duration_hours", 0)) > 0 \
		and int(event.get("min_depth", -1)) >= 0 \
		and float(event.get("weight", 0.0)) > 0.0 \
		and event.get("tags", []) is Array and not (event.get("tags", []) as Array).is_empty()

static func build_region_schedule(world_seed: int, node: Dictionary) -> Dictionary:
	var stable_region_id: String = str(node.get("stable_id", ""))
	var biome_id: String = str(node.get("biome", "green_highlands"))
	var graph_depth: int = maxi(0, int(node.get("graph_depth", 0)))
	var candidates: Array[String] = []
	for event_id in get_ids():
		var event: Dictionary = get_event(event_id)
		if (event.get("biomes", []) as Array).has(biome_id) and graph_depth >= int(event.get("min_depth", 0)):
			candidates.append(event_id)
	if candidates.is_empty() or stable_region_id.is_empty():
		return {"format_version": FORMAT_VERSION, "region_id": stable_region_id, "entries": []}
	var profile: Dictionary = node.get("content_profile", {}) as Dictionary
	var danger: float = clampf(float(profile.get("danger", 0.3)), 0.0, 1.0)
	var target_count: int = 1 + (1 if graph_depth >= 3 and danger >= 0.5 and candidates.size() > 1 else 0)
	var seed_value: int = int(("%d:%s:world_events:v%d" % [world_seed, stable_region_id, FORMAT_VERSION]).hash() & 0x7fffffff)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shuffled: Array[String] = candidates.duplicate()
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temporary: String = shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = temporary
	var entries: Array[Dictionary] = []
	for slot_index in range(mini(target_count, shuffled.size())):
		var event_id: String = shuffled[slot_index]
		var event: Dictionary = get_event(event_id)
		var period_days: int = int(event.get("period_days", 1))
		var period_hours: int = period_days * 24
		var phase_hour: int = rng.randi_range(0, period_hours - 1)
		var stable_id: String = "world_event:%s:%s" % [stable_region_id.trim_prefix("region:"), event_id]
		entries.append({
			"stable_id": stable_id,
			"persistent_state_id": "state:%s" % stable_id,
			"event_id": event_id,
			"biome": biome_id,
			"period_days": period_days,
			"duration_hours": int(event.get("duration_hours", 1)),
			"phase_hour": phase_hour,
			"cycle_namespace": "%s:cycle" % stable_id,
			"tags": (event.get("tags", []) as Array).duplicate()
		})
	return {"format_version": FORMAT_VERSION, "seed": seed_value, "region_id": stable_region_id, "entries": entries}
