extends SceneTree

const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")
const SUBREGION_GENERATOR := preload("res://scripts/world/subregion_graph_generator.gd")
const WORLD_GRAPH_RUNTIME := preload("res://scripts/world/world_graph_runtime.gd")

func _init() -> void:
	var macro_generator: RefCounted = GRAPH_GENERATOR.new()
	macro_generator.call("configure", 8242601)
	var macro_graph: Dictionary = macro_generator.call("generate_graph", 24)
	var parent_region: Dictionary = _pick_parent_region(macro_graph)
	if parent_region.is_empty():
		_fail("Could not find a suitable macro region for subregion test")
		return

	var first: Dictionary = SUBREGION_GENERATOR.generate(8242601, parent_region)
	var second: Dictionary = SUBREGION_GENERATOR.generate(8242601, parent_region)
	if var_to_str(first) != var_to_str(second):
		_fail("Subregion graph is not deterministic for same seed and parent")
		return
	if not _validate_subgraph(first, parent_region):
		return
	var changed: Dictionary = SUBREGION_GENERATOR.generate(8242602, parent_region)
	if _site_signature(first) == _site_signature(changed):
		_fail("Different world seed did not alter generated subregion sites")
		return
	if not _validate_subgraph(changed, parent_region):
		return

	if not _validate_lazy_runtime_cache(macro_graph, parent_region, first):
		return

	print("SUBREGION_GRAPH_OK nodes=%d edges=%d gateways=%d" % [
		int(first.get("node_count", 0)),
		(first.get("edges", []) as Array).size(),
		int(first.get("gateway_count", 0))
	])
	quit(0)

func _pick_parent_region(graph: Dictionary) -> Dictionary:
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		if node.get("anchor", false) == false and (node.get("neighbor_ids", []) as Array).size() >= 2:
			return node.duplicate(true)
	return {}

func _validate_subgraph(subgraph: Dictionary, parent_region: Dictionary) -> bool:
	var parent_id: String = str(parent_region.get("stable_id", ""))
	if int(subgraph.get("format_version", 0)) < 1:
		return _fail("Subregion graph has no versioned format")
	if str(subgraph.get("parent_region_id", "")) != parent_id:
		return _fail("Subregion graph lost parent region identity")
	if str(subgraph.get("stable_id", "")) != "subgraph:%s" % parent_id:
		return _fail("Subregion graph stable ID is invalid")
	var nodes: Array = subgraph.get("nodes", []) as Array
	var edges: Array = subgraph.get("edges", []) as Array
	if nodes.size() < 6 or nodes.size() > 14 or int(subgraph.get("node_count", 0)) != nodes.size():
		return _fail("Subregion graph node budget is out of bounds")
	if edges.size() < nodes.size() - 1:
		return _fail("Subregion graph cannot be connected with its edge count")

	var node_ids: Dictionary = {}
	var gateway_targets: Dictionary = {}
	var core_count: int = 0
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Subregion graph contains invalid node data")
		var node: Dictionary = node_value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		if stable_id.is_empty() or node_ids.has(stable_id):
			return _fail("Subregion graph has missing or duplicate node IDs")
		if str(node.get("parent_region_id", "")) != parent_id:
			return _fail("Subregion node lost parent region identity")
		if not node.get("local_position", null) is Vector2:
			return _fail("Subregion node has invalid local position data")
		var role: String = str(node.get("role", ""))
		if role == "core":
			core_count += 1
		elif role == "gateway":
			var macro_target: String = str(node.get("macro_neighbor_id", ""))
			if macro_target.is_empty() or gateway_targets.has(macro_target):
				return _fail("Subregion gateway target is missing or duplicated")
			gateway_targets[macro_target] = true
		node_ids[stable_id] = true
	if core_count != 1:
		return _fail("Subregion graph must have exactly one core node")
	if gateway_targets.size() != int(subgraph.get("gateway_count", -1)):
		return _fail("Subregion gateway summary is incorrect")

	var adjacency: Dictionary = {}
	for stable_id in node_ids.keys():
		adjacency[stable_id] = []
	var edge_ids: Dictionary = {}
	for edge_value in edges:
		if not edge_value is Dictionary:
			return _fail("Subregion graph contains invalid edge data")
		var edge: Dictionary = edge_value as Dictionary
		var edge_id: String = str(edge.get("stable_id", ""))
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if edge_id.is_empty() or edge_ids.has(edge_id):
			return _fail("Subregion graph has missing or duplicate route IDs")
		if not node_ids.has(from_id) or not node_ids.has(to_id) or from_id == to_id:
			return _fail("Subregion route references invalid nodes")
		edge_ids[edge_id] = true
		(adjacency[from_id] as Array).append(to_id)
		(adjacency[to_id] as Array).append(from_id)

	var start_id: String = str((nodes[0] as Dictionary).get("stable_id", ""))
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
		return _fail("Subregion graph is not fully connected")
	return true

func _validate_lazy_runtime_cache(macro_graph: Dictionary, parent_region: Dictionary, expected: Dictionary) -> bool:
	var runtime: Node = WORLD_GRAPH_RUNTIME.new()
	runtime.set("active_world_seed", 8242601)
	var index: Dictionary = {}
	for node_value in macro_graph.get("nodes", []) as Array:
		if node_value is Dictionary:
			var node: Dictionary = node_value as Dictionary
			index[str(node.get("stable_id", ""))] = node.duplicate(true)
	runtime.set("nodes_by_id", index)
	if runtime.get_child_count() != 0:
		return _fail("Subregion runtime unexpectedly instantiated scene children before request")
	var generated: Dictionary = runtime.call("subregion_graph", str(parent_region.get("stable_id", "")))
	if var_to_str(generated) != var_to_str(expected):
		return _fail("Lazy runtime subregion data differs from deterministic generator")
	var cached_ids: Array = runtime.call("cached_subregion_ids") as Array
	if cached_ids.size() != 1:
		return _fail("Lazy runtime did not cache exactly the requested subregion graph")
	if runtime.get_child_count() != 0:
		return _fail("Requesting subregion data increased active scene-tree cost")
	var repeated: Dictionary = runtime.call("subregion_graph", str(parent_region.get("stable_id", "")))
	if var_to_str(repeated) != var_to_str(generated):
		return _fail("Cached subregion graph changed across reads")
	runtime.free()
	return true

func _site_signature(subgraph: Dictionary) -> String:
	var parts: Array[String] = []
	for node_value in subgraph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		if str(node.get("role", "")) == "gateway" or str(node.get("role", "")) == "core":
			continue
		parts.append("%s=%s" % [str(node.get("stable_id", "")), var_to_str(node.get("local_position", Vector2.ZERO))])
	parts.sort()
	return "|".join(parts)

func _fail(message: String) -> bool:
	printerr("SUBREGION_GRAPH_FAILED: %s" % message)
	quit(1)
	return false
