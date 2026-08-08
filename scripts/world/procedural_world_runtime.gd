extends "res://scripts/world/procedural_world_system.gd"

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const RUNTIME_TERRAIN_CHUNK_SCRIPT := preload("res://scripts/world/terrain_chunk.gd")
const MAX_POOLED_CHUNKS: int = 64
const MAX_CACHED_CHUNKS: int = 96

var chunk_pool: Array[Node3D] = []
var chunk_pool_root: Node3D
var pooled_reuses: int = 0
var chunk_cache_order: Array[String] = []
var chunk_cache_evictions: int = 0

func _build_starting_valley_terrain() -> void:
	if world == null or world.has_node("GeneratedStartingValley"):
		return
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var reserved_slots: Array[Dictionary] = REGION_CATALOG.get_slots("starting_valley")
	var terrain_root := Node3D.new()
	terrain_root.name = "GeneratedStartingValley"
	world.add_child(terrain_root)
	_build_chunks(terrain_root, "starting_valley", biome_id, REGION_CATALOG.get_center("starting_valley"), reserved_slots, -3, 3)

func _scan_runtime_regions() -> void:
	if world == null:
		return
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
	var biome_id: String = REGION_CATALOG.get_biome_id(region_id)
	var reserved_slots: Array[Dictionary] = REGION_CATALOG.get_slots(region_id)
	var terrain_root := Node3D.new()
	terrain_root.name = "GeneratedTerrain"
	region_node.add_child(terrain_root)
	_build_chunks(terrain_root, region_id, biome_id, REGION_CATALOG.get_center(region_id), reserved_slots, -2, 2)

func _build_chunks(parent: Node3D, region_id: String, biome_id: String, region_center: Vector3, reserved_slots: Array[Dictionary], min_coord: int, max_coord_exclusive: int) -> void:
	for chunk_z in range(min_coord, max_coord_exclusive):
		for chunk_x in range(min_coord, max_coord_exclusive):
			var coord := Vector2i(chunk_x, chunk_z)
			var cache_key: String = "%d:%s:%d:%d" % [_world_seed(), region_id, chunk_x, chunk_z]
			var chunk_data: Dictionary = _cached_chunk_data(cache_key)
			if chunk_data.is_empty():
				chunk_data = generator.call("generate_chunk_data", region_id, biome_id, region_center, coord, reserved_slots)
				_store_chunk_data(cache_key, chunk_data)

			var chunk: Node3D = _acquire_chunk(parent)
			chunk.call("build_from_data", chunk_data)

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
			chunk.queue_free()
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

func get_pool_stats() -> Dictionary:
	return {
		"available": chunk_pool.size(),
		"capacity": MAX_POOLED_CHUNKS,
		"reuses": pooled_reuses,
		"cached_chunk_data": chunk_data_cache.size(),
		"chunk_cache_capacity": MAX_CACHED_CHUNKS,
		"chunk_cache_evictions": chunk_cache_evictions
	}
