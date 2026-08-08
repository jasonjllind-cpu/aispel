extends Node

const DEFAULT_WORLD_SEED: int = 8242601

var world_seed: int = DEFAULT_WORLD_SEED
var current_region_id: String = "starting_valley"
var discovered_regions: Dictionary = {}
var world_flags: Dictionary = {}
var entity_states: Dictionary = {}

func new_world(seed_value: int = DEFAULT_WORLD_SEED) -> void:
	world_seed = seed_value if seed_value != 0 else DEFAULT_WORLD_SEED
	current_region_id = "starting_valley"
	discovered_regions.clear()
	world_flags.clear()
	entity_states.clear()

func stable_seed(scope_id: String) -> int:
	var combined: String = "%d:%s" % [world_seed, scope_id]
	return int(combined.hash() & 0x7fffffff)

func mark_region_discovered(region_id: String) -> void:
	discovered_regions[region_id] = true

func is_region_discovered(region_id: String) -> bool:
	return bool(discovered_regions.get(region_id, false))

func set_flag(flag_id: String, value: Variant = true) -> void:
	world_flags[flag_id] = value

func get_flag(flag_id: String, default_value: Variant = false) -> Variant:
	return world_flags.get(flag_id, default_value)

func set_entity_state(entity_id: String, state: Dictionary) -> void:
	entity_states[entity_id] = state.duplicate(true)

func get_entity_state(entity_id: String) -> Dictionary:
	var state: Variant = entity_states.get(entity_id, {})
	if state is Dictionary:
		return (state as Dictionary).duplicate(true)
	return {}

func snapshot() -> Dictionary:
	return {
		"version": 1,
		"world_seed": world_seed,
		"current_region_id": current_region_id,
		"discovered_regions": discovered_regions.duplicate(true),
		"world_flags": world_flags.duplicate(true),
		"entity_states": entity_states.duplicate(true)
	}

func restore_snapshot(data: Dictionary) -> void:
	world_seed = int(data.get("world_seed", DEFAULT_WORLD_SEED))
	current_region_id = str(data.get("current_region_id", "starting_valley"))
	discovered_regions = _dictionary_copy(data.get("discovered_regions", {}))
	world_flags = _dictionary_copy(data.get("world_flags", {}))
	entity_states = _dictionary_copy(data.get("entity_states", {}))

func _dictionary_copy(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
