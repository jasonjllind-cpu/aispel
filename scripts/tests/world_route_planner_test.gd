extends SceneTree

const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

func _init() -> void:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", 8242601)
	var graph: Dictionary = generator.call("generate_graph", 36)
	var repeat: Dictionary = generator.call("generate_graph", 36)
	if var_to_str(graph) != var_to_str(repeat):
		_fail("Route plan is not deterministic for the same world seed")
		return
	if not _validate_route_plan(graph):
		return
	generator.call("configure", 8242602)
	var changed: Dictionary = generator.call("generate_graph", 36)
	if _shortcut_signature(graph) == _shortcut_signature(changed) and _route_signature(graph) == _route_signature(changed):
		_fail("Different world seeds did not alter route topology metadata")
		return
	if not _validate_route_plan(changed):
		return
	print("WORLD_ROUTE_PLANNER_OK edges=%d gateways=%d shortcuts=%d" % [
		(graph.get("edges", []) as Array).size(),
		int(graph.get("gateway_count", 0)),
		(graph.get("shortcut_candidates", []) as Array).size()
	])
	quit(0)

func _validate_route_plan(graph: Dictionary) -> bool:
	if int(graph.get("route_format_version", 0)) < 1:
		return _fail("Route plan has no versioned format")
	var nodes: Array = graph.get("nodes", []) as Array
	var edges: Array = graph.get("edges", []) as Array
	var shortcuts: Array = graph.get("shortcut_candidates", []) as Array
	if nodes.size() != 36 or edges.is_empty():
		return _fail("Route plan has invalid graph size")

	var nodes_by_id: Dictionary = {}
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Route plan contains invalid node data")
		var node: Dictionary = node_value as Dictionary
		nodes_by_id[str(node.get("stable_id", ""))] = node

	var direct_pairs: Dictionary = {}
	var observed_counts: Dictionary = {"primary": 0, "regional": 0, "remote": 0, "cross_route": 0}
	var observed_gateways: int = 0
	for edge_value in edges:
		if not edge_value is Dictionary:
			return _fail("Route plan contains invalid edge data")
		var edge: Dictionary = edge_value as Dictionary
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if not nodes_by_id.has(from_id) or not nodes_by_id.has(to_id):
			return _fail("Route hierarchy references an unknown node")
		var route_class: String = str(edge.get("route_class", ""))
		if not observed_counts.has(route_class):
			return _fail("Route hierarchy contains an unknown route class")
		observed_counts[route_class] = int(observed_counts[route_class]) + 1
		var route_rank: int = int(edge.get("route_rank", -1))
		if route_rank < 0 or route_rank > 3:
			return _fail("Route hierarchy contains an invalid route rank")
		var from_band: String = str((nodes_by_id[from_id] as Dictionary).get("progression_band", ""))
		var to_band: String = str((nodes_by_id[to_id] as Dictionary).get("progression_band", ""))
		var expected_gateway: bool = from_band != to_band
		if bool(edge.get("gateway", false)) != expected_gateway:
			return _fail("Gateway flag does not match progression-band crossing")
		if expected_gateway:
			observed_gateways += 1
			if str(edge.get("gateway_id", "")).is_empty():
				return _fail("Gateway route is missing a stable gateway ID")
		elif not str(edge.get("gateway_id", "")).is_empty():
			return _fail("Non-gateway route has a gateway ID")
		direct_pairs[_pair_key(from_id, to_id)] = true

	var stored_counts: Dictionary = graph.get("route_class_counts", {}) as Dictionary
	if var_to_str(stored_counts) != var_to_str(observed_counts):
		return _fail("Route class summary does not match generated edges")
	if int(graph.get("gateway_count", -1)) != observed_gateways:
		return _fail("Gateway summary does not match generated edges")
	if int(observed_counts.get("primary", 0)) <= 0:
		return _fail("Route hierarchy produced no primary routes")
	if int(graph.get("max_graph_depth", 0)) >= 2 and observed_gateways <= 0:
		return _fail("Progression graph has no gateway transitions")

	var shortcut_ids: Dictionary = {}
	var shortcut_nodes: Dictionary = {}
	for shortcut_value in shortcuts:
		if not shortcut_value is Dictionary:
			return _fail("Shortcut candidate contains invalid data")
		var shortcut: Dictionary = shortcut_value as Dictionary
		var stable_id: String = str(shortcut.get("stable_id", ""))
		var from_id: String = str(shortcut.get("from", ""))
		var to_id: String = str(shortcut.get("to", ""))
		if stable_id.is_empty() or shortcut_ids.has(stable_id):
			return _fail("Shortcut candidates have missing or duplicate IDs")
		if not nodes_by_id.has(from_id) or not nodes_by_id.has(to_id) or from_id == to_id:
			return _fail("Shortcut candidate references invalid nodes")
		if direct_pairs.has(_pair_key(from_id, to_id)):
			return _fail("Shortcut candidate duplicates an existing direct route")
		if shortcut_nodes.has(from_id) or shortcut_nodes.has(to_id):
			return _fail("Shortcut planner reused a node in the same candidate set")
		if int(shortcut.get("graph_distance", 0)) != 2:
			return _fail("Shortcut candidate is outside the bounded local graph distance")
		var score: float = float(shortcut.get("score", -1.0))
		if score < 0.0 or score > 1.0:
			return _fail("Shortcut candidate score is out of range")
		shortcut_ids[stable_id] = true
		shortcut_nodes[from_id] = true
		shortcut_nodes[to_id] = true
	if nodes.size() >= 16 and shortcuts.is_empty():
		return _fail("Large macro graph produced no deterministic shortcut candidates")
	return true

func _route_signature(graph: Dictionary) -> String:
	var parts: Array[String] = []
	for edge_value in graph.get("edges", []) as Array:
		if edge_value is Dictionary:
			var edge: Dictionary = edge_value as Dictionary
			parts.append("%s:%s:%s" % [str(edge.get("stable_id", "")), str(edge.get("route_class", "")), str(edge.get("gateway", false))])
	parts.sort()
	return "|".join(parts)

func _shortcut_signature(graph: Dictionary) -> String:
	var parts: Array[String] = []
	for shortcut_value in graph.get("shortcut_candidates", []) as Array:
		if shortcut_value is Dictionary:
			parts.append(str((shortcut_value as Dictionary).get("stable_id", "")))
	parts.sort()
	return "|".join(parts)

func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

func _fail(message: String) -> bool:
	printerr("WORLD_ROUTE_PLANNER_FAILED: %s" % message)
	quit(1)
	return false
