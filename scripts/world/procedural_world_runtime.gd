extends "res://scripts/world/procedural_world_system.gd"

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const RUNTIME_TERRAIN_CHUNK_SCRIPT := preload("res://scripts/world/terrain_chunk.gd")
const GENERATION_FORMAT_VERSION: int = 2
const DEFAULT_WORLD_SEED: int = 8242601
const MAX_POOLED_CHUNKS: int = 64
const MAX_CACHED_CHUNKS: int = 96

var chunk_pool: Array[Node3D] = []
var chunk_pool_root: Node3D
var pooled_reuses: int = 0
var chunk_cache_order: Array[String] = []
var chunk_cache_evictions: int = 0
var configured_world_seed: int = 0
var generation_epoch: int = 0
var rejected_chunks: int = 0
var fallback_chunks: int = 0

func _build_starting_valley_terrain() -> void:
	if world == null:
		return
	_ensure_generation_context()
	if world.has_node("GeneratedStartingValley"):
		return
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var reserved_slots: Array[Dictionary] = REGION_CATALOG.get_slots("starting_valley")
	var terrain_root := Node3D.new()
	terrain_root.name = "GeneratedStartingValley"
	terrain_root.set_meta("world_seed", configured_world_seed)
	terrain_root.set_meta("generation_epoch", generation_epoch)
	world.add_child(terrain_root)
	_build_chunks(terrain_root, "starting_valley", biome_id, REGION_CATALOG.get_center("starting_valley"), reserved_slots, -3, 3)

func _scan_runtime_regions() -> void:
	if world == null:
		return
	_ensure_generation_context()
	if not world.has_node("GeneratedStartingValley"):
		_build_starting_valley_terrain()
	var active_generated: int = 1 if world.has_node("GeneratedStartingValley") else 0
	var runtime_regions := world.get_node_or_null("RuntimeRegions") as Node3D
	if runtime_regions != null:
		for child in runtime_regions.get_children():
			if not child is Node3D:
				continue
			var region_node := child as Node3D
			var region_id: String = region_node.name.trim_prefix("Region_")
			if not REGION_CATALOG.has_region(region_id) or region_id == "starting_valley":
				continue
			if not region_node.has_node("GeneratedTerrain"):
				_build_region_terrain(region_node, region_id)
			if region_node.has_node("GeneratedTerrain"):
				active_generated += 1
	generated_region_count = active_generated
	_refresh_status()

func _build_region_terrain(region_node: Node3D, region_id: String) -> void:
	_ensure_generation_context()
	var biome_id: String = REGION_CATALOG.get_biome_id(region_id)
	var reserved_slots: Array[Dictionary] = REGION_CATALOG.get_slots(region_id)
	var terrain_root := Node3D.new()
	terrain_root.name = "GeneratedTerrain"
	terrain_root.set_meta("world_seed", configured_world_seed)
	terrain_root.set_meta("generation_epoch", generation_epoch)
	region_node.add_child(terrain_root)
	_build_chunks(terrain_root, region_id, biome_id, REGION_CATALOG.get_center(region_id), reserved_slots, -2, 2)

func _build_chunks(parent: Node3D, region_id: String, biome_id: String, region_center: Vector3, reserved_slots: Array[Dictionary], min_coord: int, max_coord_exclusive: int) -> void:
	if generator == null or not is_instance_valid(parent):
		return
	_ensure_generation_context()
	var expected_epoch: int = generation_epoch
	var expected_seed: int = configured_world_seed
	for chunk_z in range(min_coord, max_coord_exclusive):
		for chunk_x in range(min_coord, max_coord_exclusive):
			if expected_epoch != generation_epoch or expected_seed != configured_world_seed:
				return
			var coord := Vector2i(chunk_x, chunk_z)
			var cache_key: String = _cache_key(region_id, coord)
			var chunk_data: Dictionary = _cached_chunk_data(cache_key)
			if not chunk_data.is_empty() and not _valid_chunk_for_context(chunk_data, region_id, coord, expected_seed):
				_remove_cached_chunk(cache_key)
				rejected_chunks += 1
				chunk_data = {}

			if chunk_data.is_empty():
				var generated_value: Variant = generator.call("generate_chunk_data", region_id, biome_id, region_center, coord, reserved_slots)
				if generated_value is Dictionary:
					chunk_data = generated_value as Dictionary
				if not _valid_chunk_for_context(chunk_data, region_id, coord, expected_seed):
					rejected_chunks += 1
					push_error("World generation rejected chunk %s at epoch %d" % [cache_key, expected_epoch])
					continue
				_store_chunk_data(cache_key, chunk_data)

			if bool(chunk_data.get("fallback", false)):
				fallback_chunks += 1
			var chunk: Node3D = _acquire_chunk(parent)
			var build_result: Variant = chunk.call("build_from_data", chunk_data)
			if build_result != true:
				rejected_chunks += 1
				_recycle_rejected_chunk(chunk)

func _valid_chunk_for_context(chunk_data: Dictionary, region_id: String, coord: Vector2i, expected_seed: int) -> bool:
	if chunk_data.is_empty() or int(chunk_data.get("format_version", 0)) != GENERATION_FORMAT_VERSION:
		return false
	if int(chunk_data.get("world_seed", 0)) != expected_seed:
		return false
	if str(chunk_data.get("region_id", "")) != region_id:
		return false
	var coord_value: Variant = chunk_data.get("chunk_coord", null)
	if not coord_value is Vector2i or coord_value != coord:
		return false
	if str(chunk_data.get("data_signature", "")).is_empty():
		return false
	if generator == null or not generator.has_method("validate_chunk_data"):
		return false
	var validation_value: Variant = generator.call("validate_chunk_data", chunk_data)
	return validation_value is Dictionary and (validation_value as Dictionary).get("ok", false) == true

func _ensure_generation_context() -> void:
	if generator == null:
		return
	var current_seed: int = _normalized_seed(_world_seed())
	if configured_world_seed == current_seed:
		return
	var replacing_world: bool = configured_world_seed != 0
	configured_world_seed = current_seed
	generation_epoch += 1
	generator.call("configure", configured_world_seed)
	clear_generation_cache()
	if replacing_world:
		_clear_generated_terrain_roots()

func _clear_generated_terrain_roots() -> void:
	if world == null:
		return
	var starting_root := world.get_node_or_null("GeneratedStartingValley")
	if starting_root != null:
		starting_root.free()
	var runtime_regions := world.get_node_or_null("RuntimeRegions") as Node3D
	if runtime_regions != null:
		for child in runtime_regions.get_children():
			if child is Node3D:
				var terrain_root := (child as Node3D).get_node_or_null("GeneratedTerrain")
				if terrain_root != null:
					terrain_root.free()
	generated_region_count = 0

func _acquire_chunk(parent: Node3D) -> Node3D:
	_ensure_pool_root()
	var chunk: Node3D
	if not chunk_pool.is_empty():
		chunk = chunk_pool.pop_back()
		chunk.reparent(parent, false)
		pooled_reuses += 1
	else:
		chunk = Node3D.new()
		chunk.set_script(RUNTIME_TERRAIN_CHUNK_SCRIPT)
		parent.add_child(chunk)
	return chunk

func _recycle_rejected_chunk(chunk: Node3D) -> void:
	if not is_instance_valid(chunk):
		return
	_ensure_pool_root()
	chunk.call("prepare_for_pool")
	if chunk_pool.size() < MAX_POOLED_CHUNKS:
		chunk.reparent(chunk_pool_root, false)
		chunk_pool.append(chunk)
	else:
		chunk.free()

func release_region_terrain(region_id: String) -> int:
	if world == null or region_id.is_empty() or region_id == "starting_valley":
		return 0
	var runtime_regions := world.get_node_or_null("RuntimeRegions") as Node3D
	if runtime_regions == null:
		return 0
	var region_node := runtime_regions.get_node_or_null("Region_%s" % region_id) as Node3D
	if region_node == null:
		return 0
	var terrain_root := region_node.get_node_or_null("GeneratedTerrain") as Node3D
	if terrain_root == null:
		return 0
	_ensure_pool_root()
	var released: int = 0
	for child in terrain_root.get_children():
		if not child is Node3D:
			continue
		var chunk := child as Node3D
		if not chunk.is_in_group("generated_terrain_chunk"):
			continue
		if chunk_pool.size() >= MAX_POOLED_CHUNKS:
			chunk.free()
			continue
		chunk.call("prepare_for_pool")
		chunk.reparent(chunk_pool_root, false)
		chunk_pool.append(chunk)
		released += 1
	return released

func clear_generation_cache() -> void:
	chunk_data_cache.clear()
	chunk_cache_order.clear()
	chunk_cache_evictions = 0

func get_chunk_data(region_id: String, chunk_coord: Vector2i) -> Dictionary:
	var value: Variant = chunk_data_cache.get(_cache_key(region_id, chunk_coord), {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func _cache_key(region_id: String, coord: Vector2i) -> String:
	var seed_value: int = configured_world_seed if configured_world_seed > 0 else _normalized_seed(_world_seed())
	return "v%d:%d:%s:%d:%d" % [GENERATION_FORMAT_VERSION, seed_value, region_id, coord.x, coord.y]

func _cached_chunk_data(cache_key: String) -> Dictionary:
	var value: Variant = chunk_data_cache.get(cache_key)
	if not value is Dictionary:
		return {}
	_touch_chunk_cache(cache_key)
	return (value as Dictionary).duplicate(true)

func _store_chunk_data(cache_key: String, chunk_data: Dictionary) -> void:
	if cache_key.is_empty() or chunk_data.is_empty():
		return
	if not chunk_data_cache.has(cache_key):
		while chunk_data_cache.size() >= MAX_CACHED_CHUNKS and not chunk_cache_order.is_empty():
			var evicted_key: String = chunk_cache_order.pop_front()
			if chunk_data_cache.erase(evicted_key):
				chunk_cache_evictions += 1
	chunk_data_cache[cache_key] = chunk_data.duplicate(true)
	_touch_chunk_cache(cache_key)

func _remove_cached_chunk(cache_key: String) -> void:
	chunk_data_cache.erase(cache_key)
	chunk_cache_order.erase(cache_key)

func _touch_chunk_cache(cache_key: String) -> void:
	chunk_cache_order.erase(cache_key)
	chunk_cache_order.append(cache_key)

func _ensure_pool_root() -> void:
	if is_instance_valid(chunk_pool_root):
		return
	chunk_pool_root = Node3D.new()
	chunk_pool_root.name = "TerrainChunkPool"
	chunk_pool_root.visible = false
	if world != null:
		world.add_child(chunk_pool_root)
	else:
		add_child(chunk_pool_root)

func _normalized_seed(seed_value: int) -> int:
	var normalized: int = int(seed_value & 0x7fffffff)
	return normalized if normalized > 0 else DEFAULT_WORLD_SEED

func get_pool_stats() -> Dictionary:
	return {
		"available": chunk_pool.size(),
		"capacity": MAX_POOLED_CHUNKS,
		"reuses": pooled_reuses,
		"cached_chunk_data": chunk_data_cache.size(),
		"chunk_cache_capacity": MAX_CACHED_CHUNKS,
		"chunk_cache_evictions": chunk_cache_evictions,
		"configured_world_seed": configured_world_seed,
		"generation_epoch": generation_epoch,
		"rejected_chunks": rejected_chunks,
		"fallback_chunks": fallback_chunks
	}
