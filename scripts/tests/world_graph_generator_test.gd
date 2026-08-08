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

	print("WORLD_GRAPH_OK nodes=%d edges=%d max_depth=%d anchors=4" % [
		(first.get("nodes", []) as Array).size(),
		(first.get("edges", []) as Array).size(),
		int(first.get("max_graph_depth", -1))
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
	if str(graph.get("start_region_id", "")) != "region:starting_valley":
		return _fail("Macro world graph has an invalid start region")
	if int(graph.get("format_version", 0)) < 2:
		return _fail("Macro world graph format was not advanced for topology metadata")

	var node_ids: Dictionary = {}
	var anchor_ids: Dictionary = {}
	var node_by_id: Dictionary = {}
	var observed_max_depth: int = 0
	var observed_band_counts: Dictionary = {"heartland": 0, "frontier": 0, "wilds": 0}
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Macro world graph contains a non-dictionary node")
		var node: Dictionary = node_value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		if stable_id.is_empty() or node_ids.has(stable_id):
			return _fail("Macro world graph has missing or duplicate stable region IDs")
		node_ids[stable_id] = true
		node_by_id[stable_id] = node
		var depth: int = int(node.get("graph_depth", -1))
		if depth < 0:
			return _fail("Macro world graph contains unreachable topology metadata")
		var band: String = str(node.get("progression_band", ""))
		if not observed_band_counts.has(band):
			return _fail("Macro world graph contains an unknown progression band")
		observed_band_counts[band] = int(observed_band_counts[band]) + 1
		observed_max_depth = maxi(observed_max_depth, depth)
		var neighbours_value: Variant = node.get("neighbor_ids", null)
		if not neighbours_value is Array:
			return _fail("Macro world node is missing deterministic neighbour metadata")
		var neighbours: Array = neighbours_value as Array
		if int(node.get("degree", -1)) != neighbours.size():
			return _fail("Macro world node degree does not match neighbour metadata")
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

	var start_node: Dictionary = node_by_id.get("region:starting_valley", {}) as Dictionary
	if int(start_node.get("graph_depth", -1)) != 0 or str(start_node.get("progression_band", "")) != "heartland":
		return _fail("Starting Valley topology metadata is invalid")

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
		var expected_route_depth: int = maxi(int((node_by_id[from_id] as Dictionary).get("graph_depth", -1)), int((node_by_id[to_id] as Dictionary).get("graph_depth", -1)))
		if int(edge.get("graph_depth", -1)) != expected_route_depth:
			return _fail("Macro world route depth does not match its endpoint topology")
		edge_ids[edge_id] = true
		(adjacency[from_id] as Array).append(to_id)
		(adjacency[to_id] as Array).append(from_id)

	for stable_id in node_ids.keys():
		var expected_neighbours: Array = (adjacency[stable_id] as Array).duplicate()
		expected_neighbours.sort()
		var stored_neighbours: Array = ((node_by_id[stable_id] as Dictionary).get("neighbor_ids", []) as Array).duplicate()
		stored_neighbours.sort()
		if var_to_str(expected_neighbours) != var_to_str(stored_neighbours):
			return _fail("Stored topology neighbours do not match graph edges")
		if stable_id != "region:starting_valley":
			var depth: int = int((node_by_id[stable_id] as Dictionary).get("graph_depth", -1))
			var has_parent_depth: bool = false
			for neighbour_value in expected_neighbours:
				var neighbour_id: String = str(neighbour_value)
				if int((node_by_id[neighbour_id] as Dictionary).get("graph_depth", -1)) == depth - 1:
					has_parent_depth = true
					break
			if not has_parent_depth:
				return _fail("Topology depth has no valid shortest-path predecessor")

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
	if int(graph.get("max_graph_depth", -1)) != observed_max_depth:
		return _fail("Macro world graph max depth summary is incorrect")
	var stored_band_counts: Dictionary = graph.get("progression_band_counts", {}) as Dictionary
	if var_to_str(stored_band_counts) != var_to_str(observed_band_counts):
		return _fail("Macro world graph progression band summary is incorrect")
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
