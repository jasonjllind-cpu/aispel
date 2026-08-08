extends RefCounted
class_name WorldRoutePlanner

const ROUTE_FORMAT_VERSION: int = 1
const SHORTCUT_DENSITY_DIVISOR: int = 8

static func build(world_seed: int, nodes: Array, edges: Array) -> Dictionary:
	var nodes_by_id: Dictionary = {}
	for node_value in nodes:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		if not stable_id.is_empty():
			nodes_by_id[stable_id] = node

	var annotated_edges: Array[Dictionary] = []
	var direct_pairs: Dictionary = {}
	var class_counts: Dictionary = {"primary": 0, "regional": 0, "remote": 0, "cross_route": 0}
	var gateway_count: int = 0
	for edge_value in edges:
		if not edge_value is Dictionary:
			continue
		var edge: Dictionary = (edge_value as Dictionary).duplicate(true)
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		var from_node: Dictionary = nodes_by_id.get(from_id, {}) as Dictionary
		var to_node: Dictionary = nodes_by_id.get(to_id, {}) as Dictionary
		var route_class: String = _route_class(from_node, to_node)
		var gateway: bool = str(from_node.get("progression_band", "")) != str(to_node.get("progression_band", ""))
		edge["route_format_version"] = ROUTE_FORMAT_VERSION
		edge["route_class"] = route_class
		edge["route_rank"] = _route_rank(route_class)
		edge["gateway"] = gateway
		edge["gateway_id"] = "gateway:%s" % str(edge.get("stable_id", "")) if gateway else ""
		class_counts[route_class] = int(class_counts.get(route_class, 0)) + 1
		if gateway:
			gateway_count += 1
		direct_pairs[_pair_key(from_id, to_id)] = true
		annotated_edges.append(edge)
	annotated_edges.sort_custom(_edge_less)

	var shortcut_candidates: Array[Dictionary] = _build_shortcuts(world_seed, nodes_by_id, direct_pairs)
	return {
		"format_version": ROUTE_FORMAT_VERSION,
		"edges": annotated_edges,
		"shortcut_candidates": shortcut_candidates,
		"route_class_counts": class_counts,
		"gateway_count": gateway_count
	}

static func _route_class(from_node: Dictionary, to_node: Dictionary) -> String:
	var from_depth: int = int(from_node.get("graph_depth", 0))
	var to_depth: int = int(to_node.get("graph_depth", 0))
	if from_depth == to_depth:
		return "cross_route"
	var shallow_depth: int = mini(from_depth, to_depth)
	if shallow_depth <= 1:
		return "primary"
	if shallow_depth <= 3:
		return "regional"
	return "remote"

static func _route_rank(route_class: String) -> int:
	match route_class:
		"primary":
			return 0
		"regional":
			return 1
		"remote":
			return 2
		_:
			return 3

static func _build_shortcuts(world_seed: int, nodes_by_id: Dictionary, direct_pairs: Dictionary) -> Array[Dictionary]:
	var ids: Array[String] = []
	for key in nodes_by_id.keys():
		ids.append(str(key))
	ids.sort()
	var candidates: Array[Dictionary] = []
	for i in range(ids.size()):
		var from_id: String = ids[i]
		var from_node: Dictionary = nodes_by_id[from_id] as Dictionary
		var from_cell: Vector2i = from_node.get("graph_cell", Vector2i.ZERO)
		for j in range(i + 1, ids.size()):
			var to_id: String = ids[j]
			if direct_pairs.has(_pair_key(from_id, to_id)):
				continue
			var to_node: Dictionary = nodes_by_id[to_id] as Dictionary
			var to_cell: Vector2i = to_node.get("graph_cell", Vector2i.ZERO)
			var manhattan: int = absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
			if manhattan != 2:
				continue
			var depth_delta: int = absi(int(from_node.get("graph_depth", 0)) - int(to_node.get("graph_depth", 0)))
			if depth_delta > 2:
				continue
			var pair_key: String = _pair_key(from_id, to_id)
			var score: float = _shortcut_score(world_seed, pair_key)
			candidates.append({
				"stable_id": "shortcut:%s>%s" % [from_id, to_id],
				"from": from_id,
				"to": to_id,
				"from_cell": from_cell,
				"to_cell": to_cell,
				"score": score,
				"graph_distance": manhattan,
				"depth_delta": depth_delta,
				"gateway": str(from_node.get("progression_band", "")) != str(to_node.get("progression_band", "")),
				"route_class": "shortcut"
			})
	candidates.sort_custom(_shortcut_less)

	var target_count: int = maxi(1, floori(float(ids.size()) / float(SHORTCUT_DENSITY_DIVISOR))) if ids.size() >= 8 else 0
	var selected: Array[Dictionary] = []
	var used_nodes: Dictionary = {}
	for candidate in candidates:
		if selected.size() >= target_count:
			break
		var from_id: String = str(candidate.get("from", ""))
		var to_id: String = str(candidate.get("to", ""))
		if used_nodes.has(from_id) or used_nodes.has(to_id):
			continue
		used_nodes[from_id] = true
		used_nodes[to_id] = true
		selected.append(candidate)
	selected.sort_custom(_stable_id_less)
	return selected

static func _shortcut_score(world_seed: int, pair_key: String) -> float:
	var raw: int = int(("%d:shortcut:%s:v%d" % [world_seed, pair_key, ROUTE_FORMAT_VERSION]).hash() & 0x7fffffff)
	return float(raw) / float(0x7fffffff)

static func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

static func _edge_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))

static func _shortcut_less(a: Dictionary, b: Dictionary) -> bool:
	var score_a: float = float(a.get("score", 0.0))
	var score_b: float = float(b.get("score", 0.0))
	if is_equal_approx(score_a, score_b):
		return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
	return score_a < score_b

static func _stable_id_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
