extends RefCounted
class_name TerrainChunkPool

const DEFAULT_MAX_RETAINED: int = 64

var chunk_script: Script
var max_retained: int = DEFAULT_MAX_RETAINED
var available: Array[Node3D] = []
var total_created: int = 0
var total_reused: int = 0
var total_released: int = 0
var total_discarded: int = 0

func _init(script: Script, capacity: int = DEFAULT_MAX_RETAINED) -> void:
	chunk_script = script
	max_retained = maxi(0, capacity)

func acquire(parent: Node) -> Node3D:
	var chunk: Node3D
	if not available.is_empty():
		chunk = available.pop_back()
		total_reused += 1
	else:
		chunk = Node3D.new()
		chunk.set_script(chunk_script)
		total_created += 1
	if parent != null:
		parent.add_child(chunk)
	chunk.visible = true
	return chunk

func release(chunk: Node3D) -> bool:
	if chunk == null or not is_instance_valid(chunk):
		return false
	if chunk.get_parent() != null:
		chunk.get_parent().remove_child(chunk)
	if chunk.has_method("prepare_for_pool"):
		chunk.call("prepare_for_pool")
	total_released += 1
	if available.size() >= max_retained:
		total_discarded += 1
		chunk.queue_free()
		return false
	available.append(chunk)
	return true

func release_children(parent: Node) -> int:
	if parent == null:
		return 0
	var released: int = 0
	for child in parent.get_children().duplicate():
		if child is Node3D and (child as Node).is_in_group("generated_terrain_chunk"):
			if release(child as Node3D):
				released += 1
	return released

func clear() -> void:
	for chunk in available:
		if chunk != null and is_instance_valid(chunk):
			chunk.queue_free()
	available.clear()

func stats() -> Dictionary:
	return {
		"available": available.size(),
		"capacity": max_retained,
		"created": total_created,
		"reused": total_reused,
		"released": total_released,
		"discarded": total_discarded
	}
