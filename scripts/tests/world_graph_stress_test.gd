extends SceneTree

const GENERATOR_SCRIPT := preload("res://scripts/world/world_graph_generator.gd")

const CASES: Array[Dictionary] = [
	{"seed": 1, "nodes": 18},
	{"seed": 8242601, "nodes": 64},
	{"seed": 2147483647, "nodes": 128},
	{"seed": 9007199254740991, "nodes": 256}
]

func _init() -> void:
	var generator: RefCounted = GENERATOR_SCRIPT.new()
	var observed_signatures: Dictionary = {}
	var total_nodes: int = 0
	for case_data in CASES:
		var world_seed: int = int(case_data.get("seed", 0))
		var node_count: int = int(case_data.get("nodes", 0))
		generator.call("configure", world_seed)
		var first: Dictionary = generator.call("generate_graph", node_count)
		var second: Dictionary = generator.call("generate_graph", node_count)
		var first_signature: String = _graph_signature(first)
		var second_signature: String = _graph_signature(second)
		if first_signature != second_signature:
			_fail("Regeneration changed graph for seed=%d nodes=%d" % [world_seed, node_count])
			return
		if not _validate_case(first, world_seed, node_count):
			return
		if observed_signatures.has(first_signature):
			_fail("Distinct stress cases produced an identical graph signature")
			return
		observed_signatures[first_signature] = true
		total_nodes += node_count

	print("WORLD_GRAPH_STRESS_OK cases=%d regenerated_nodes=%d largest_graph=%d" % [CASES.size(), total_nodes * 2, int(CASES.back().get("nodes", 0))])
	quit(0)

func _validate_case(graph: Dictionary, world_seed: int, expected_nodes: int) -> bool:
	var nodes: Array = graph.get("nodes", []) as Array
	var edges: Array = graph.get("edges", []) as Array
	var placements: Array = graph.get("distribution_placements", []) as Array
	if int(graph.get("world_seed", world_seed)) != world_seed:
		return _fail("Stress graph did not retain its world seed")
	if nodes.size() != expected_nodes:
		return _fail("Stress graph node count mismatch for seed=%d" % world_seed)
	if nodes.is_empty() or edges.is_empty():
		return _fail("Stress graph is missing topology data")

	var nodes_by_id: Dictionary = {}
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Stress graph contains non-dictionary node data")
		var node: Dictionary = node_value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		if stable_id.is_empty() or nodes_by_id.has(stable_id):
			return _fail("Stress graph contains missing or duplicate region IDs")
		if int(node.get("graph_depth", -1)) < 0:
			return _fail("Stress graph contains unreachable region metadata")
		nodes_by_id[stable_id] = node

	var edge_ids: Dictionary = {}
	for edge_value in edges:
		if not edge_value is Dictionary:
			return _fail("Stress graph contains non-dictionary edge data")
		var edge: Dictionary = edge_value as Dictionary
		var edge_id: String = str(edge.get("stable_id", ""))
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if edge_id.is_empty() or edge_ids.has(edge_id):
			return _fail("Stress graph contains duplicate route IDs")
		if not nodes_by_id.has(from_id) or not nodes_by_id.has(to_id) or from_id == to_id:
			return _fail("Stress graph route references an invalid region")
		edge_ids[edge_id] = true

	if not _validate_connectivity(nodes_by_id):
		return false
	if not _validate_distribution(nodes_by_id, placements):
		return false
	return true

func _validate_connectivity(nodes_by_id: Dictionary) -> bool:
	var start_id: String = "region:starting_valley"
	if not nodes_by_id.has(start_id):
		return _fail("Starting Valley is missing from stress graph")
	var visited: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		var node: Dictionary = nodes_by_id[current] as Dictionary
		for neighbour_value in node.get("neighbor_ids", []) as Array:
			var neighbour: String = str(neighbour_value)
			if not nodes_by_id.has(neighbour):
				return _fail("Stress graph neighbour metadata references a missing region")
			if visited.has(neighbour):
				continue
			visited[neighbour] = true
			queue.append(neighbour)
	if visited.size() != nodes_by_id.size():
		return _fail("Stress graph is not fully connected")
	return true

func _validate_distribution(nodes_by_id: Dictionary, placements: Array) -> bool:
	var placement_ids: Dictionary = {}
	var settlement_ids: Dictionary = {}
	var landmark_ids: Dictionary = {}
	for placement_value in placements:
		if not placement_value is Dictionary:
			return _fail("Stress graph contains invalid distribution placement data")
		var placement: Dictionary = placement_value as Dictionary
		var placement_id: String = str(placement.get("stable_id", ""))
		var region_id: String = str(placement.get("region_id", ""))
		var placement_type: String = str(placement.get("type", ""))
		if placement_id.is_empty() or placement_ids.has(placement_id):
			return _fail("Stress graph contains duplicate distribution placement IDs")
		if not nodes_by_id.has(region_id):
			return _fail("Distribution placement references missing region")
		placement_ids[placement_id] = true
		if placement_type == "settlement":
			settlement_ids[region_id] = true
		elif placement_type == "major_landmark":
			landmark_ids[region_id] = true
		else:
			return _fail("Distribution placement contains unknown type")

	for region_id_value in settlement_ids.keys():
		var region_id: String = str(region_id_value)
		if landmark_ids.has(region_id):
			return _fail("Settlement and landmark overlap in stress graph")
		var node: Dictionary = nodes_by_id[region_id] as Dictionary
		for neighbour_value in node.get("neighbor_ids", []) as Array:
			if settlement_ids.has(str(neighbour_value)):
				return _fail("Adjacent settlements violate stress distribution constraints")
	for region_id_value in landmark_ids.keys():
		var region_id: String = str(region_id_value)
		var node: Dictionary = nodes_by_id[region_id] as Dictionary
		for neighbour_value in node.get("neighbor_ids", []) as Array:
			if landmark_ids.has(str(neighbour_value)):
				return _fail("Adjacent major landmarks violate stress distribution constraints")
	return true

func _graph_signature(graph: Dictionary) -> String:
	var parts: Array[String] = []
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		var cell: Vector2i = node.get("graph_cell", Vector2i.ZERO)
		parts.append("N:%s:%d:%d:%s:%s" % [str(node.get("stable_id", "")), cell.x, cell.y, str(node.get("template_id", "")), str(node.get("distribution_role", ""))])
	for edge_value in graph.get("edges", []) as Array:
		if edge_value is Dictionary:
			parts.append("E:%s" % str((edge_value as Dictionary).get("stable_id", "")))
	for placement_value in graph.get("distribution_placements", []) as Array:
		if placement_value is Dictionary:
			parts.append("P:%s" % str((placement_value as Dictionary).get("stable_id", "")))
	parts.sort()
	return "|".join(parts)

func _fail(message: String) -> bool:
	printerr("WORLD_GRAPH_STRESS_FAILED: %s" % message)
	quit(1)
	return false
