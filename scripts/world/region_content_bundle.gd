extends RefCounted
class_name RegionContentBundle

const FORMAT_VERSION: int = 1
const ENCOUNTERS := preload("res://scripts/world/encounter_archetype_catalog.gd")
const LOOT := preload("res://scripts/world/regional_loot_catalog.gd")
const POIS := preload("res://scripts/world/poi_archetype_catalog.gd")
const SETTLEMENTS := preload("res://scripts/world/settlement_archetype_catalog.gd")
const DUNGEONS := preload("res://scripts/dungeon/regional_dungeon_catalog.gd")
const EVENTS := preload("res://scripts/world/world_event_catalog.gd")
const LORE := preload("res://scripts/world/lore_discovery_catalog.gd")
const DENSITY := preload("res://scripts/world/content_density_balancer.gd")

static func compile_region(world_seed: int, node: Dictionary) -> Dictionary:
	var stable_region_id: String = str(node.get("stable_id", ""))
	var theme: Dictionary = node.get("content_theme", {}) as Dictionary
	var profile: Dictionary = node.get("content_profile", {}) as Dictionary
	var density: Dictionary = DENSITY.balance(node)
	var encounter_plan: Dictionary = ENCOUNTERS.build_region_plan(world_seed, stable_region_id, theme, profile)
	var loot_plan: Dictionary = LOOT.build_region_plan(world_seed, stable_region_id, theme, profile)
	var poi_plan: Dictionary = POIS.build_region_plan(world_seed, stable_region_id, theme, profile, float(node.get("radius", 68.0)))
	var event_plan: Dictionary = EVENTS.build_region_schedule(world_seed, node)
	var lore_plan: Dictionary = LORE.build_region_plan(world_seed, node)
	var settlement_plan: Dictionary = SETTLEMENTS.build_plan(world_seed, node)
	var dungeon_plan: Dictionary = DUNGEONS.build_region_plan(world_seed, node)
	var encounters: Array[Dictionary] = _limited_entries(encounter_plan.get("entries", []) as Array, int(density.get("encounter_slots", 1)))
	var loot: Array[Dictionary] = _limited_entries(loot_plan.get("entries", []) as Array, int(density.get("loot_slots", 2)))
	var pois: Array[Dictionary] = _limited_entries(poi_plan.get("entries", []) as Array, int(density.get("poi_slots", 1)))
	var world_events: Array[Dictionary] = _limited_entries(event_plan.get("entries", []) as Array, int(density.get("event_slots", 1)))
	var lore: Array[Dictionary] = _limited_entries(lore_plan.get("entries", []) as Array, int(density.get("lore_slots", 1)))
	return {
		"format_version": FORMAT_VERSION,
		"bundle_id": "content_bundle:%s" % stable_region_id.trim_prefix("region:"),
		"region_id": stable_region_id,
		"biome": str(node.get("biome", "green_highlands")),
		"progression_band": str(node.get("progression_band", "heartland")),
		"density_budget": density,
		"encounters": encounters,
		"loot": loot,
		"pois": pois,
		"world_events": world_events,
		"lore": lore,
		"settlement": settlement_plan,
		"dungeon": dungeon_plan,
		"counts": {
			"encounters": encounters.size(),
			"loot": loot.size(),
			"pois": pois.size(),
			"world_events": world_events.size(),
			"lore": lore.size(),
			"settlement": 1 if not str(settlement_plan.get("stable_id", "")).is_empty() else 0,
			"dungeon": 1 if bool(dungeon_plan.get("enabled", false)) else 0
		}
	}

static func validate_bundle(bundle: Dictionary) -> bool:
	if str(bundle.get("bundle_id", "")).is_empty() or str(bundle.get("region_id", "")).is_empty():
		return false
	var density: Dictionary = bundle.get("density_budget", {}) as Dictionary
	if not DENSITY.validate_budget(density):
		return false
	var limits: Dictionary = {
		"encounters": int(density.get("encounter_slots", 0)),
		"loot": int(density.get("loot_slots", 0)),
		"pois": int(density.get("poi_slots", 0)),
		"world_events": int(density.get("event_slots", 0)),
		"lore": int(density.get("lore_slots", 0))
	}
	var seen: Dictionary = {}
	for key in ["encounters", "loot", "pois", "world_events", "lore"]:
		var entries: Array = bundle.get(key, []) as Array
		if entries.size() > int(limits.get(key, 0)):
			return false
		for entry_value in entries:
			if not entry_value is Dictionary:
				return false
			var entry: Dictionary = entry_value as Dictionary
			if not _register_entry(entry, seen):
				return false
	var settlement: Dictionary = bundle.get("settlement", {}) as Dictionary
	if not str(settlement.get("stable_id", "")).is_empty() and not _register_entry(settlement, seen):
		return false
	var dungeon: Dictionary = bundle.get("dungeon", {}) as Dictionary
	if bool(dungeon.get("enabled", false)) and not _register_entry(dungeon, seen):
		return false
	return true

static func persistent_ids(bundle: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in ["encounters", "loot", "pois", "world_events", "lore"]:
		for entry_value in bundle.get(key, []) as Array:
			if entry_value is Dictionary:
				result.append(str((entry_value as Dictionary).get("persistent_state_id", "")))
	for key in ["settlement", "dungeon"]:
		var entry_value: Variant = bundle.get(key, {})
		if entry_value is Dictionary:
			var persistent_id: String = str((entry_value as Dictionary).get("persistent_state_id", ""))
			if not persistent_id.is_empty():
				result.append(persistent_id)
	result.sort()
	return result

static func _limited_entries(source: Array, max_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count: int = mini(maxi(0, max_count), source.size())
	for index in range(count):
		var value: Variant = source[index]
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result

static func _register_entry(entry: Dictionary, seen: Dictionary) -> bool:
	var stable_id: String = str(entry.get("stable_id", ""))
	var persistent_id: String = str(entry.get("persistent_state_id", ""))
	if stable_id.is_empty() or persistent_id.is_empty() or seen.has(stable_id) or seen.has(persistent_id):
		return false
	seen[stable_id] = true
	seen[persistent_id] = true
	return true
