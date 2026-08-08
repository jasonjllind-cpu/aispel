extends SceneTree

const TERRAIN_CHUNK := preload("res://scripts/world/terrain_chunk.gd")
const CHUNK_POOL := preload("res://scripts/world/terrain_chunk_pool.gd")

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

	pool.call("clear")
	if int((pool.call("stats") as Dictionary).get("available", -1)) != 0:
		_fail("Pool clear left retained chunks")
		return
	parent.free()
	print("STREAMING_OPTIMIZATION_OK created=8 reused=6 capacity=8")
	quit(0)

func _fail(message: String) -> void:
	printerr("STREAMING_OPTIMIZATION_FAILED: %s" % message)
	quit(1)
