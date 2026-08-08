extends SceneTree

const TERRAIN_CHUNK := preload("res://scripts/world/terrain_chunk.gd")
const CHUNK_POOL := preload("res://scripts/world/terrain_chunk_pool.gd")
const GENERATION_CACHE := preload("res://scripts/world/bounded_generation_cache.gd")

func _init() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var pool: RefCounted = CHUNK_POOL.new(TERRAIN_CHUNK, 8)
	var active: Array[Node3D] = []

	for index in range(8):
		var chunk: Node3D = pool.call("acquire", parent) as Node3D
		chunk.call("build_from_data", {"chunk_id": "test:%d" % index, "generation_seed": index})
		active.append(chunk)
	var initial: Dictionary = pool.call("stats") as Dictionary
	if int(initial.get("created", -1)) != 8 or int(initial.get("available", -1)) != 0:
		_fail("Pool did not create the bounded initial working set: %s" % str(initial))
		return

	for chunk in active:
		pool.call("release", chunk)
	active.clear()
	var released: Dictionary = pool.call("stats") as Dictionary
	if int(released.get("available", -1)) != 8 or int(released.get("released", -1)) != 8:
		_fail("Released chunks were not retained for reuse: %s" % str(released))
		return

	for index in range(6):
		active.append(pool.call("acquire", parent) as Node3D)
	var reused: Dictionary = pool.call("stats") as Dictionary
	if int(reused.get("created", -1)) != 8 or int(reused.get("reused", -1)) != 6 or int(reused.get("available", -1)) != 2:
		_fail("Pool acquisition allocated instead of reusing chunks: %s" % str(reused))
		return

	for chunk in active:
		pool.call("release", chunk)
	active.clear()
	var overflow: Node3D = Node3D.new()
	overflow.set_script(TERRAIN_CHUNK)
	parent.add_child(overflow)
	var retained: bool = bool(pool.call("release", overflow))
	var bounded: Dictionary = pool.call("stats") as Dictionary
	if retained or int(bounded.get("available", -1)) != 8 or int(bounded.get("discarded", -1)) != 1:
		_fail("Pool capacity is not strictly bounded: %s" % str(bounded))
		return

	var cache: RefCounted = GENERATION_CACHE.new(3)
	cache.call("put", "a", {"value": 1})
	cache.call("put", "b", {"value": 2})
	cache.call("put", "c", {"value": 3})
	var b_value: Dictionary = cache.call("get_value", "b") as Dictionary
	if int(b_value.get("value", -1)) != 2:
		_fail("Generation cache did not return stored data")
		return
	cache.call("put", "d", {"value": 4})
	var cache_stats: Dictionary = cache.call("stats") as Dictionary
	if int(cache_stats.get("size", -1)) != 3 or int(cache_stats.get("evictions", -1)) != 1:
		_fail("Generation cache capacity is not bounded: %s" % str(cache_stats))
		return
	if not (cache.call("get_value", "a") as Dictionary).is_empty():
		_fail("Generation cache did not evict least-recently-used data")
		return
	if int((cache.call("get_value", "b") as Dictionary).get("value", -1)) != 2:
		_fail("Generation cache evicted a recently used entry")
		return

	pool.call("clear")
	cache.call("clear")
	if int((pool.call("stats") as Dictionary).get("available", -1)) != 0:
		_fail("Pool clear left retained chunks")
		return
	if int((cache.call("stats") as Dictionary).get("size", -1)) != 0:
		_fail("Generation cache clear left retained data")
		return
	parent.free()
	print("STREAMING_OPTIMIZATION_OK created=8 reused=6 pool_capacity=8 cache_capacity=3")
	quit(0)

func _fail(message: String) -> void:
	printerr("STREAMING_OPTIMIZATION_FAILED: %s" % message)
	quit(1)
