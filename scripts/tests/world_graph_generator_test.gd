extends SceneTree

const GENERATOR_SCRIPT := preload("res://scripts/world/world_graph_generator.gd")

func _init() -> void:
	var generator: RefCounted = GENERATOR_SCRIPT.new()
	generator.call("configure", 8242601)
	var first: Dictionary = generator.call("generate_graph", 18)
	var second: Dictionary = generator.call("generate_graph", 18)
	if var_to_str(first) != var_to_str(second):
		_fail("Same seed generated different macro world graphs")
		return
	if not _validate_graph(first, 18):
		return

	var blackwood_terrain_seed: int = int(generator.call("region_layer_seed", "region:blackwood", "terrain"))
	var blackwood_poi_seed: int = int(generator.call("region_layer_seed", "region:blackwood", "poi"))
	if blackwood_terrain_seed == blackwood_poi_seed:
		_fail("Region generation layers share the same deterministic seed")
		return

	generator.call("configure", 8242602)
	var changed: Dictionary = generator.call("generate_graph", 18)
	if _content_signature(first) == _content_signature(changed):
		_fail("Different world seed did not change macro world content")
		return
	if not _validate_graph(changed, 18):
		return

	print("WORLD_GRAPH_OK nodes=%d edges=%d anchors=4" % [
		(first.get("nodes", []) as Array).size(),
		(first.get("edges", []) as Array).size()
	])
	quit(0)

func _validate_graph(graph: Dictionary, expected_nodes: int) -> bool:
	var nodes_value: Variant = graph.get("nodes", null)
	var edges_value: Variant = graph.get("edges", null)
	if not nodes_value is Array or not edges_value is Array:
		return _fail("Macro world graph is missing node/edge arrays")
	var nodes: Array = nodes_value as Array
	var edges: Array = edges_value as Array
	if nodes.size() != expected_nodes:
		return _fail("Macro world graph node count mismatch")
	if int(graph.get("anchor_count", 0)) != 4:
		return _fail("Macro world graph anchor count mismatch")

	var node_ids: Dictionary = {}
	var anchor_ids: Dictionary = {}
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Macro world graph contains a non-dictionary node")
		var node: Dictionary = node_value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		if stable_id.is_empty() or node_ids.has(stable_id):
			return _fail("Macro world graph has missing or duplicate stable region IDs")
		node_ids[stable_id] = true
		if node.get("anchor", false) == true:
			anchor_ids[stable_id] = true
		else:
			var cell_value: Variant = node.get("graph_cell", null)
			var center_value: Variant = node.get("center", null)
			if not cell_value is Vector2i or not center_value is Vector3:
				return _fail("Generated macro region has invalid cell/center data")
			var cell: Vector2i = cell_value as Vector2i
			var center: Vector3 = center_value as Vector3
			if not is_equal_approx(center.x, float(cell.x) * float(graph.get("region_spacing", 170.0))) or not is_equal_approx(center.z, float(cell.y) * float(graph.get("region_spacing", 170.0))):
				return _fail("Generated macro region center does not match graph cell")

	for required_anchor in ["region:starting_valley", "region:blackwood", "region:windscar_highlands", "region:veilmoor"]:
		if not anchor_ids.has(required_anchor):
			return _fail("Legacy authored anchor missing from macro graph: %s" % required_anchor)

	var adjacency: Dictionary = {}
	for stable_id in node_ids.keys():
		adjacency[stable_id] = []
	var edge_ids: Dictionary = {}
	for edge_value in edges:
		if not edge_value is Dictionary:
			return _fail("Macro world graph contains a non-dictionary edge")
		var edge: Dictionary = edge_value as Dictionary
		var edge_id: String = str(edge.get("stable_id", ""))
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if edge_id.is_empty() or edge_ids.has(edge_id):
			return _fail("Macro world graph has duplicate route IDs")
		if not node_ids.has(from_id) or not node_ids.has(to_id) or from_id == to_id:
			return _fail("Macro world route references an invalid region")
		edge_ids[edge_id] = true
		(adjacency[from_id] as Array).append(to_id)
		(adjacency[to_id] as Array).append(from_id)

	var start_id: String = "region:starting_valley"
	var visited: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbour_value in adjacency[current] as Array:
			var neighbour: String = str(neighbour_value)
			if visited.has(neighbour):
				continue
			visited[neighbour] = true
			queue.append(neighbour)
	if visited.size() != nodes.size():
		return _fail("Macro world graph is not fully connected")
	return true

func _content_signature(graph: Dictionary) -> String:
	var parts: Array[String] = []
	var nodes: Array = graph.get("nodes", []) as Array
	for node_value in nodes:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		if node.get("anchor", false) == true:
			continue
		var cell: Vector2i = node.get("graph_cell", Vector2i.ZERO)
		parts.append("%d,%d=%s" % [cell.x, cell.y, str(node.get("template_id", ""))])
	parts.sort()
	return "|".join(parts)

func _fail(message: String) -> bool:
	printerr("WORLD_GRAPH_FAILED: %s" % message)
	quit(1)
	return false
