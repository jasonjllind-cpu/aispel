extends Node

signal world_reset(seed: int)
signal world_restored(seed: int)
signal state_changed(kind: String, stable_id: String)

const DEFAULT_WORLD_SEED: int = 8242601
const SNAPSHOT_VERSION: int = 2

var world_seed: int = DEFAULT_WORLD_SEED
var current_region_id: String = "starting_valley"
var discovered_regions: Dictionary = {}
var world_flags: Dictionary = {}
var entity_states: Dictionary = {}
var _skip_next_autosave_restore: bool = false

func _ready() -> void:
	_apply_command_line_seed()

func new_world(seed_value: int = DEFAULT_WORLD_SEED) -> void:
	world_seed = sanitize_seed(seed_value)
	current_region_id = "starting_valley"
	discovered_regions.clear()
	world_flags.clear()
	entity_states.clear()
	world_reset.emit(world_seed)
	state_changed.emit("world", "reset")

func preserve_new_world_on_scene_reload() -> void:
	_skip_next_autosave_restore = true

func consume_autosave_restore_skip() -> bool:
	if not _skip_next_autosave_restore:
		return false
	_skip_next_autosave_restore = false
	return true

func sanitize_seed(seed_value: int) -> int:
	if seed_value == 0:
		return DEFAULT_WORLD_SEED
	return abs(seed_value)

func stable_seed(scope_id: String) -> int:
	var combined: String = "%d:%s" % [world_seed, scope_id]
	return int(combined.hash() & 0x7fffffff)

func generation_seed(region_id: String, layer_id: String, chunk_x: int = 0, chunk_z: int = 0) -> int:
	return stable_seed("generation:%s:%s:%d:%d" % [region_id, layer_id, chunk_x, chunk_z])

func seed_namespace(region_id: String, layer_id: String) -> String:
	return "%d:%s:%s" % [world_seed, region_id, layer_id]

func set_current_region(region_id: String) -> void:
	if region_id.is_empty() or current_region_id == region_id:
		return
	current_region_id = region_id
	state_changed.emit("region", region_id)

func mark_region_discovered(region_id: String) -> void:
	if region_id.is_empty() or is_region_discovered(region_id):
		return
	discovered_regions[region_id] = true
	state_changed.emit("discovery", region_id)

func is_region_discovered(region_id: String) -> bool:
	return discovered_regions.has(region_id) and discovered_regions.get(region_id, false) == true

func set_flag(flag_id: String, value: Variant = true) -> void:
	if flag_id.is_empty():
		return
	if world_flags.has(flag_id) and world_flags[flag_id] == value:
		return
	world_flags[flag_id] = value
	state_changed.emit("flag", flag_id)

func get_flag(flag_id: String, default_value: Variant = false) -> Variant:
	return world_flags.get(flag_id, default_value)

func set_entity_state(entity_id: String, state: Dictionary) -> void:
	if entity_id.is_empty():
		return
	var new_state: Dictionary = state.duplicate(true)
	if entity_states.has(entity_id) and entity_states[entity_id] == new_state:
		return
	entity_states[entity_id] = new_state
	state_changed.emit("entity", entity_id)

func get_entity_state(entity_id: String) -> Dictionary:
	var state: Variant = entity_states.get(entity_id, {})
	if state is Dictionary:
		return (state as Dictionary).duplicate(true)
	return {}

func snapshot() -> Dictionary:
	return {
		"version": SNAPSHOT_VERSION,
		"world_seed": world_seed,
		"current_region_id": current_region_id,
		"discovered_regions": discovered_regions.duplicate(true),
		"world_flags": world_flags.duplicate(true),
		"entity_states": entity_states.duplicate(true)
	}

func restore_snapshot(data: Dictionary) -> void:
	world_seed = sanitize_seed(int(data.get("world_seed", DEFAULT_WORLD_SEED)))
	current_region_id = str(data.get("current_region_id", "starting_valley"))
	discovered_regions = _dictionary_copy(data.get("discovered_regions", {}))
	world_flags = _dictionary_copy(data.get("world_flags", {}))
	entity_states = _dictionary_copy(data.get("entity_states", {}))
	world_restored.emit(world_seed)
	state_changed.emit("world", "restore")

func _apply_command_line_seed() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--world-seed="):
			var value_text: String = argument.trim_prefix("--world-seed=").strip_edges()
			if value_text.is_valid_int():
				world_seed = sanitize_seed(int(value_text))
			return

func _dictionary_copy(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
