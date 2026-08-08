extends RefCounted
class_name WorldStreamingPlanner

const FORMAT_VERSION: int = 1

static func rank_candidates(nodes: Array, player_position: Vector3, current_region_id: String, route_target_id: String, max_distance: float, load_budget: int, excluded_ids: Dictionary = {}) -> Array[Dictionary]:
	if load_budget <= 0:
		return []
	var nodes_by_id: Dictionary = _index_nodes(nodes)
	var hop_distance: Dictionary = _hop_distances(nodes_by_id, current_region_id)
	var active_route: Dictionary = _shortest_path_set(nodes_by_id, current_region_id, route_target_id)
	var ranked: Array[Dictionary] = []
	for stable_id_value in nodes_by_id.keys():
		var stable_id: String = str(stable_id_value)
		if excluded_ids.has(stable_id):
			continue
		var node: Dictionary = nodes_by_id[stable_id] as Dictionary
		if node.get("anchor", false) == true:
			continue
		var center_value: Variant = node.get("center", null)
		if not center_value is Vector3:
			continue
		var center: Vector3 = center_value as Vector3
		var physical_distance: float = Vector2(player_position.x - center.x, player_position.z - center.z).length()
		if physical_distance > max_distance:
			continue
		var hops: int = int(hop_distance.get(stable_id, 999))
		var on_route: bool = active_route.has(stable_id)
		var route_bonus: float = -120.0 if on_route else 0.0
		var hop_cost: float = float(mini(hops, 8)) * 24.0
		var depth_cost: float = float(maxi(0, int(node.get("graph_depth", 0)))) * 1.5
		var score: float = physical_distance + hop_cost + depth_cost + route_bonus
		ranked.append({
			"stable_id": stable_id,
			"score": score,
			"physical_distance": physical_distance,
			"graph_hops": hops,
			"on_active_route": on_route,
			"priority_tier": _priority_tier(physical_distance, hops, on_route, max_distance)
		})
	ranked.sort_custom(_priority_less)
	var result: Array[Dictionary] = []
	for candidate in ranked:
		if result.size() >= load_budget:
			break
		result.append(candidate.duplicate(true))
	return result

static func _index_nodes(nodes: Array) -> Dictionary:
	var result: Dictionary = {}
	for node_value in nodes:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		if not stable_id.is_empty():
			result[stable_id] = node
	return result

static func _hop_distances(nodes_by_id: Dictionary, start_id: String) -> Dictionary:
	var distances: Dictionary = {}
	if not nodes_by_id.has(start_id):
		return distances
	distances[start_id] = 0
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		var node: Dictionary = nodes_by_id[current] as Dictionary
		var next_distance: int = int(distances[current]) + 1
		for neighbour_value in node.get("neighbor_ids", []) as Array:
			var neighbour: String = str(neighbour_value)
			if not nodes_by_id.has(neighbour) or distances.has(neighbour):
				continue
			distances[neighbour] = next_distance
			queue.append(neighbour)
	return distances

static func _shortest_path_set(nodes_by_id: Dictionary, start_id: String, target_id: String) -> Dictionary:
	var result: Dictionary = {}
	if target_id.is_empty() or start_id == target_id or not nodes_by_id.has(start_id) or not nodes_by_id.has(target_id):
		return result
	var previous: Dictionary = {}
	var visited: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == target_id:
			break
		var node: Dictionary = nodes_by_id[current] as Dictionary
		var neighbours: Array = (node.get("neighbor_ids", []) as Array).duplicate()
		neighbours.sort()
		for neighbour_value in neighbours:
			var neighbour: String = str(neighbour_value)
			if not nodes_by_id.has(neighbour) or visited.has(neighbour):
				continue
			visited[neighbour] = true
			previous[neighbour] = current
			queue.append(neighbour)
	if not visited.has(target_id):
		return result
	var cursor: String = target_id
	while cursor != start_id:
		result[cursor] = true
		if not previous.has(cursor):
			break
		cursor = str(previous[cursor])
	return result

static func _priority_tier(physical_distance: float, hops: int, on_route: bool, max_distance: float) -> String:
	if on_route or hops <= 1 or physical_distance <= max_distance * 0.42:
		return "immediate"
	if hops <= 2 or physical_distance <= max_distance * 0.72:
		return "preload"
	return "background"

static func _priority_less(a: Dictionary, b: Dictionary) -> bool:
	var score_a: float = float(a.get("score", INF))
	var score_b: float = float(b.get("score", INF))
	if is_equal_approx(score_a, score_b):
		return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
	return score_a < score_b
