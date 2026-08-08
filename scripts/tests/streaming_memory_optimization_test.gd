extends SceneTree

const WORLD_GRAPH_RUNTIME := preload("res://scripts/world/world_graph_runtime.gd")
const PROCEDURAL_WORLD_RUNTIME := preload("res://scripts/world/procedural_world_runtime.gd")

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	if not _test_world_graph_bounds():
		return
	if not _test_terrain_cache_bounds():
		return
	print("STREAMING_MEMORY_OPTIMIZATION_OK active_cap=7 subregion_cache=24 terrain_cache=96")
	quit(0)

func _test_world_graph_bounds() -> bool:
	var runtime := Node.new()
	runtime.set_script(WORLD_GRAPH_RUNTIME)
	runtime.call("rebuild_for_seed", 91082601, 96)
	var graph_value: Variant = runtime.get("graph")
	if not graph_value is Dictionary:
		_fail(runtime, null, "WorldGraphRuntime did not produce a graph")
		return false
	var nodes_value: Variant = (graph_value as Dictionary).get("nodes", [])
	if not nodes_value is Array or (nodes_value as Array).size() < 40:
		_fail(runtime, null, "Large graph did not contain enough regions for cache stress")
		return false

	var region_ids: Array[String] = []
	for value in nodes_value as Array:
		if value is Dictionary:
			var stable_id: String = str((value as Dictionary).get("stable_id", ""))
			if not stable_id.is_empty():
				region_ids.append(stable_id)
	region_ids.sort()

	var first_id: String = region_ids[0]
	var first_graph: Dictionary = runtime.call("subregion_graph", first_id) as Dictionary
	if first_graph.is_empty():
		_fail(runtime, null, "Could not generate baseline subregion graph")
		return false
	for index in range(1, 36):
		var generated: Dictionary = runtime.call("subregion_graph", region_ids[index]) as Dictionary
		if generated.is_empty():
			_fail(runtime, null, "Subregion generation failed during cache stress")
			return false
	var stats: Dictionary = runtime.call("streaming_stats") as Dictionary
	if int(stats.get("cached_subregions", 0)) > int(stats.get("subregion_cache_capacity", 0)):
		_fail(runtime, null, "Subregion cache exceeded its hard capacity")
		return false
	if int(stats.get("cached_subregions", 0)) != 24 or int(stats.get("subregion_cache_evictions", 0)) <= 0:
		_fail(runtime, null, "Subregion LRU cache did not evict under stress")
		return false
	var regenerated: Dictionary = runtime.call("subregion_graph", first_id) as Dictionary
	if regenerated != first_graph:
		_fail(runtime, null, "Evicted subregion graph did not regenerate deterministically")
		return false

	var region_root := Node3D.new()
	for stable_id in region_ids:
		runtime.call("load_region_for_test", stable_id, region_root)
	var loaded: Array[String] = runtime.call("loaded_region_ids") as Array[String]
	stats = runtime.call("streaming_stats") as Dictionary
	if loaded.size() != 7 or int(stats.get("active_regions", 0)) > int(stats.get("active_region_capacity", 0)):
		_fail(runtime, region_root, "Macro-region scene-tree cap was not enforced")
		return false

	runtime.free()
	region_root.free()
	return true

func _test_terrain_cache_bounds() -> bool:
	var runtime := Node.new()
	runtime.set_script(PROCEDURAL_WORLD_RUNTIME)
	for index in range(96):
		runtime.call("_store_chunk_data", "cache:%03d" % index, {"chunk_id": "chunk:%03d" % index, "generation_seed": index})
	var touched: Dictionary = runtime.call("_cached_chunk_data", "cache:000") as Dictionary
	if touched.is_empty():
		_fail(runtime, null, "Could not touch cached terrain data before LRU stress")
		return false
	for index in range(96, 120):
		runtime.call("_store_chunk_data", "cache:%03d" % index, {"chunk_id": "chunk:%03d" % index, "generation_seed": index})
	var stats: Dictionary = runtime.call("get_pool_stats") as Dictionary
	if int(stats.get("cached_chunk_data", 0)) != 96 or int(stats.get("chunk_cache_capacity", 0)) != 96:
		_fail(runtime, null, "Terrain generation cache did not stay at bounded capacity")
		return false
	if int(stats.get("chunk_cache_evictions", 0)) != 24:
		_fail(runtime, null, "Terrain cache eviction count was not deterministic")
		return false
	if (runtime.call("_cached_chunk_data", "cache:000") as Dictionary).is_empty():
		_fail(runtime, null, "Recently touched terrain cache entry was evicted too early")
		return false
	if not (runtime.call("_cached_chunk_data", "cache:001") as Dictionary).is_empty():
		_fail(runtime, null, "Old terrain cache entry survived expected LRU eviction")
		return false
	if int(stats.get("capacity", 0)) != 64:
		_fail(runtime, null, "Terrain chunk pool capacity changed unexpectedly")
		return false
	runtime.call("clear_generation_cache")
	stats = runtime.call("get_pool_stats") as Dictionary
	if int(stats.get("cached_chunk_data", -1)) != 0:
		_fail(runtime, null, "Terrain cache did not clear cleanly")
		return false
	runtime.free()
	return true

func _fail(runtime: Node, extra: Node, message: String) -> void:
	printerr("STREAMING_MEMORY_OPTIMIZATION_FAILED: %s" % message)
	if runtime != null and is_instance_valid(runtime):
		runtime.free()
	if extra != null and is_instance_valid(extra):
		extra.free()
	quit(1)
