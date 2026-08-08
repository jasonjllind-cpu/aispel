extends SceneTree

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const JOB_QUEUE_SCRIPT := preload("res://scripts/world/generation_job_queue.gd")
const PROCEDURAL_WORLD_RUNTIME_SCRIPT := preload("res://scripts/world/procedural_world_runtime.gd")
const TERRAIN_CHUNK_SCRIPT := preload("res://scripts/world/terrain_chunk.gd")

var callback_count: int = 0

func _init() -> void:
	var failed := false
	failed = not _test_region_catalog() or failed
	failed = not _test_job_queue() or failed
	failed = not _test_chunk_pool() or failed
	if failed:
		printerr("WORLD_RUNTIME_FOUNDATION_FAILED")
		quit(1)
		return
	print("WORLD_RUNTIME_FOUNDATION_OK regions=%d" % REGION_CATALOG.get_region_ids().size())
	quit(0)

func _test_region_catalog() -> bool:
	var ids: Array[String] = REGION_CATALOG.get_region_ids()
	var expected: Array[String] = ["blackwood", "starting_valley", "veilmoor", "windscar_highlands"]
	if ids != expected:
		printerr("RegionCatalog IDs differ: %s" % [ids])
		return false
	for region_id in ids:
		var region: Dictionary = REGION_CATALOG.get_region(region_id)
		if str(region.get("id", "")) != region_id:
			printerr("RegionCatalog ID mismatch for %s" % region_id)
			return false
		if str(region.get("biome", "")).is_empty():
			printerr("RegionCatalog biome missing for %s" % region_id)
			return false
	return true

func _test_job_queue() -> bool:
	var queue: RefCounted = JOB_QUEUE_SCRIPT.new()
	var accepted: bool = bool(queue.call("enqueue", "foundation:test", Callable(self, "_foundation_callback")))
	if not accepted:
		printerr("Generation queue rejected valid job")
		return false
	if bool(queue.call("enqueue", "foundation:test", Callable(self, "_foundation_callback"))):
		printerr("Generation queue accepted duplicate job")
		return false
	var processed: int = int(queue.call("process_budget", 1, 10.0))
	if processed != 1 or callback_count != 1 or int(queue.call("pending_count")) != 0:
		printerr("Generation queue processing mismatch")
		return false
	return true

func _foundation_callback() -> void:
	callback_count += 1

func _test_chunk_pool() -> bool:
	var world := Node3D.new()
	world.name = "TestWorld"
	get_root().add_child(world)

	var runtime_regions := Node3D.new()
	runtime_regions.name = "RuntimeRegions"
	world.add_child(runtime_regions)
	var region := Node3D.new()
	region.name = "Region_blackwood"
	runtime_regions.add_child(region)
	var terrain_root := Node3D.new()
	terrain_root.name = "GeneratedTerrain"
	region.add_child(terrain_root)

	for i in range(2):
		var chunk := Node3D.new()
		chunk.set_script(TERRAIN_CHUNK_SCRIPT)
		terrain_root.add_child(chunk)
		chunk.add_to_group("generated_terrain_chunk")

	var system := Node.new()
	system.set_script(PROCEDURAL_WORLD_RUNTIME_SCRIPT)
	world.add_child(system)
	system.set("world", world)
	var released: int = int(system.call("release_region_terrain", "blackwood"))
	var stats: Dictionary = system.call("get_pool_stats")
	if released != 2 or int(stats.get("available", -1)) != 2:
		printerr("Chunk pool release mismatch: %s" % [stats])
		world.queue_free()
		return false

	var reuse_parent := Node3D.new()
	world.add_child(reuse_parent)
	var reused: Node3D = system.call("_acquire_chunk", reuse_parent)
	stats = system.call("get_pool_stats")
	var ok: bool = reused.get_parent() == reuse_parent and int(stats.get("available", -1)) == 1 and int(stats.get("reuses", 0)) == 1
	if not ok:
		printerr("Chunk pool reuse mismatch: %s" % [stats])
	world.queue_free()
	return ok
