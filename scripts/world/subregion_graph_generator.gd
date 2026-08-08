extends RefCounted
class_name SubregionGraphGenerator

const FORMAT_VERSION: int = 1
const MIN_NODE_COUNT: int = 6
const MAX_NODE_COUNT: int = 14
const LOCAL_RADIUS: float = 52.0

static func generate(world_seed: int, parent_region: Dictionary) -> Dictionary:
	var parent_id: String = str(parent_region.get("stable_id", ""))
	if parent_id.is_empty():
		return {}
	var neighbours: Array[String] = []
	var neighbour_value: Variant = parent_region.get("neighbor_ids", [])
	if neighbour_value is Array:
		for value in neighbour_value as Array:
			neighbours.append(str(value))
	neighbours.sort()
	var content_profile: Dictionary = parent_region.get("content_profile", {}) as Dictionary
	var requested_count: int = clampi(4 + int(content_profile.get("poi_budget", 3)) + mini(2, neighbours.size()), MIN_NODE_COUNT, MAX_NODE_COUNT)
	var seed_value: int = _seed(world_seed, parent_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var nodes: Array[Dictionary] = []
	nodes.append(_node(parent_id, 0, "core", Vector2.ZERO, ""))
	var index: int = 1
	for i in range(neighbours.size()):
		if index >= requested_count:
			break
		var angle: float = TAU * float(i) / float(maxi(1, neighbours.size()))
		var position := Vector2(cos(angle), sin(angle)) * LOCAL_RADIUS
		nodes.append(_node(parent_id, index, "gateway", position, neighbours[i]))
		index += 1

	while index < requested_count:
		var angle: float = rng.randf_range(0.0, TAU)
		var distance: float = rng.randf_range(LOCAL_RADIUS * 0.28, LOCAL_RADIUS * 0.78)
		var role: String = _site_role(index, content_profile)
		nodes.append(_node(parent_id, index, role, Vector2(cos(angle), sin(angle)) * distance, ""))
		index += 1

	var edges: Array[Dictionary] = _build_connected_edges(parent_id, nodes)
	return {
		"format_version": FORMAT_VERSION,
		"stable_id": "subgraph:%s" % parent_id,
		"parent_region_id": parent_id,
		"world_seed": world_seed,
		"generation_seed": seed_value,
		"node_count": nodes.size(),
		"gateway_count": mini(neighbours.size(), maxi(0, requested_count - 1)),
		"nodes": nodes,
		"edges": edges
	}

static func _node(parent_id: String, index: int, role: String, local_position: Vector2, macro_neighbour_id: String) -> Dictionary:
	return {
		"stable_id": "subregion:%s:%02d" % [parent_id.trim_prefix("region:"), index],
		"parent_region_id": parent_id,
		"local_position": local_position,
		"role": role,
		"macro_neighbor_id": macro_neighbour_id
	}

static func _site_role(index: int, content_profile: Dictionary) -> String:
	var secret_chance: float = float(content_profile.get("secret_chance", 0.18))
	if index % 5 == 0 and secret_chance >= 0.20:
		return "secret_site"
	if index % 3 == 0:
		return "encounter_site"
	return "exploration_site"

static func _build_connected_edges(parent_id: String, nodes: Array[Dictionary]) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	if nodes.size() <= 1:
		return edges
	var connected: Array[int] = [0]
	for index in range(1, nodes.size()):
		var best_index: int = 0
		var best_distance: float = INF
		var current_position: Vector2 = nodes[index].get("local_position", Vector2.ZERO)
		for candidate_index in connected:
			var candidate_position: Vector2 = nodes[candidate_index].get("local_position", Vector2.ZERO)
			var distance: float = current_position.distance_squared_to(candidate_position)
			if distance < best_distance:
				best_distance = distance
				best_index = candidate_index
		edges.append(_edge(parent_id, nodes[best_index], nodes[index], "local_path"))
		connected.append(index)
	# Add a bounded ring of lateral links between gateway/site nodes to avoid a star-only layout.
	for index in range(1, nodes.size() - 1):
		if index % 2 == 1:
			edges.append(_edge(parent_id, nodes[index], nodes[index + 1], "local_link"))
	edges.sort_custom(_edge_less)
	return _deduplicate_edges(edges)

static func _edge(parent_id: String, a: Dictionary, b: Dictionary, route_type: String) -> Dictionary:
	var a_id: String = str(a.get("stable_id", ""))
	var b_id: String = str(b.get("stable_id", ""))
	var from_id: String = a_id if a_id < b_id else b_id
	var to_id: String = b_id if a_id < b_id else a_id
	return {
		"stable_id": "subroute:%s:%s>%s" % [parent_id.trim_prefix("region:"), from_id, to_id],
		"from": from_id,
		"to": to_id,
		"route_type": route_type
	}

static func _deduplicate_edges(edges: Array[Dictionary]) -> Array[Dictionary]:
	var seen: Dictionary = {}
	var result: Array[Dictionary] = []
	for edge in edges:
		var stable_id: String = str(edge.get("stable_id", ""))
		if seen.has(stable_id):
			continue
		seen[stable_id] = true
		result.append(edge)
	return result

static func _seed(world_seed: int, parent_id: String) -> int:
	return int(("%d:%s:subregion_graph:v%d" % [world_seed, parent_id, FORMAT_VERSION]).hash() & 0x7fffffff)

static func _edge_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
