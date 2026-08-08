extends RefCounted
class_name LoreDiscoveryCatalog

const FORMAT_VERSION: int = 1

const RECORDS: Dictionary = {
	"first_road_oath": {"biomes": ["green_highlands"], "type": "inscription", "title": "The First Road Oath", "collection": "old_road", "weight": 1.0},
	"moon_shrine_verse": {"biomes": ["green_highlands"], "type": "shrine", "title": "Verse of the Moon Shrine", "collection": "moon_faith", "weight": 0.9},
	"valley_relic_record": {"biomes": ["green_highlands"], "type": "relic_record", "title": "Ledger of Valley Relics", "collection": "relics", "weight": 0.8},
	"blackwood_warning": {"biomes": ["blackwood"], "type": "inscription", "title": "Warning Beneath the Thorn", "collection": "blackwood", "weight": 1.0},
	"root_chapel_fragment": {"biomes": ["blackwood"], "type": "history_fragment", "title": "Fragment of the Root Chapel", "collection": "blackwood", "weight": 0.9},
	"witchwood_charm_record": {"biomes": ["blackwood"], "type": "relic_record", "title": "Record of the Witchwood Charm", "collection": "relics", "weight": 0.75},
	"windscar_beacon_marks": {"biomes": ["windscar_highlands"], "type": "inscription", "title": "Marks of the Windscar Beacon", "collection": "highlands", "weight": 1.0},
	"giants_step_account": {"biomes": ["windscar_highlands"], "type": "history_fragment", "title": "Account of the Giant's Step", "collection": "highlands", "weight": 0.9},
	"storm_glass_record": {"biomes": ["windscar_highlands"], "type": "relic_record", "title": "Record of Storm Glass", "collection": "relics", "weight": 0.75},
	"veilmoor_funeral_prayer": {"biomes": ["veilmoor"], "type": "shrine", "title": "Veilmoor Funeral Prayer", "collection": "veilmoor", "weight": 1.0},
	"drowned_bell_inscription": {"biomes": ["veilmoor"], "type": "inscription", "title": "Inscription of the Drowned Bell", "collection": "veilmoor", "weight": 0.9},
	"pale_procession_account": {"biomes": ["veilmoor"], "type": "history_fragment", "title": "Account of the Pale Procession", "collection": "veilmoor", "weight": 0.8},
	"cinder_watch_tablet": {"biomes": ["ashen_fen"], "type": "inscription", "title": "Tablet of the Cinder Watch", "collection": "ashen_fen", "weight": 1.0},
	"witchfire_litany": {"biomes": ["ashen_fen"], "type": "shrine", "title": "Witchfire Litany", "collection": "ashen_fen", "weight": 0.85},
	"ember_glass_record": {"biomes": ["ashen_fen"], "type": "relic_record", "title": "Record of Ember Glass", "collection": "relics", "weight": 0.8},
	"frostmere_waystone": {"biomes": ["frostmere"], "type": "inscription", "title": "Words of the Frostmere Waystone", "collection": "frostmere", "weight": 1.0},
	"icebound_pilgrim_page": {"biomes": ["frostmere"], "type": "history_fragment", "title": "Page of the Icebound Pilgrim", "collection": "frostmere", "weight": 0.9},
	"frost_glass_record": {"biomes": ["frostmere"], "type": "relic_record", "title": "Record of Frost Glass", "collection": "relics", "weight": 0.8}
}

static func get_record(record_id: String) -> Dictionary:
	var value: Variant = RECORDS.get(record_id, {})
	if not value is Dictionary:
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["id"] = record_id
	return result

static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in RECORDS.keys():
		ids.append(str(key))
	ids.sort()
	return ids

static func validate_record(record: Dictionary) -> bool:
	return not str(record.get("id", "")).is_empty() \
		and record.get("biomes", []) is Array and not (record.get("biomes", []) as Array).is_empty() \
		and ["shrine", "inscription", "relic_record", "history_fragment"].has(str(record.get("type", ""))) \
		and not str(record.get("title", "")).is_empty() \
		and not str(record.get("collection", "")).is_empty() \
		and float(record.get("weight", 0.0)) > 0.0

static func build_region_plan(world_seed: int, node: Dictionary) -> Dictionary:
	var stable_region_id: String = str(node.get("stable_id", ""))
	var biome_id: String = str(node.get("biome", "green_highlands"))
	var candidates: Array[String] = []
	for record_id in get_ids():
		if (get_record(record_id).get("biomes", []) as Array).has(biome_id):
			candidates.append(record_id)
	if candidates.is_empty() or stable_region_id.is_empty():
		return {"format_version": FORMAT_VERSION, "region_id": stable_region_id, "entries": []}
	var profile: Dictionary = node.get("content_profile", {}) as Dictionary
	var poi_budget: int = maxi(1, int(profile.get("poi_budget", 3)))
	var secret_chance: float = clampf(float(profile.get("secret_chance", 0.2)), 0.0, 0.85)
	var target_count: int = clampi(1 + (1 if poi_budget >= 4 else 0) + (1 if secret_chance >= 0.42 else 0), 1, candidates.size())
	var seed_value: int = int(("%d:%s:lore:v%d" % [world_seed, stable_region_id, FORMAT_VERSION]).hash() & 0x7fffffff)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var remaining: Array[String] = candidates.duplicate()
	var entries: Array[Dictionary] = []
	for slot_index in range(target_count):
		var total_weight: float = 0.0
		for record_id in remaining:
			total_weight += float(get_record(record_id).get("weight", 1.0))
		var roll: float = rng.randf_range(0.0, total_weight)
		var cursor: float = 0.0
		var selected_index: int = remaining.size() - 1
		for index in range(remaining.size()):
			cursor += float(get_record(remaining[index]).get("weight", 1.0))
			if roll <= cursor:
				selected_index = index
				break
		var record_id: String = remaining[selected_index]
		remaining.remove_at(selected_index)
		var record: Dictionary = get_record(record_id)
		var stable_id: String = "lore:%s:%s" % [stable_region_id.trim_prefix("region:"), record_id]
		entries.append({"stable_id": stable_id, "persistent_state_id": "state:%s" % stable_id, "record_id": record_id, "type": str(record.get("type", "")), "title": str(record.get("title", "")), "collection": str(record.get("collection", "")), "biome": biome_id})
	return {"format_version": FORMAT_VERSION, "seed": seed_value, "region_id": stable_region_id, "entries": entries}
