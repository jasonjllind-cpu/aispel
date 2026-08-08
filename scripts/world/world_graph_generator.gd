extends RefCounted
class_name WorldGraphGenerator

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const TEMPLATE_CATALOG := preload("res://scripts/world/region_template_catalog.gd")
const CONTENT_PROFILE_CATALOG := preload("res://scripts/world/region_content_profile_catalog.gd")
const ROUTE_PLANNER := preload("res://scripts/world/world_route_planner.gd")

const GRAPH_FORMAT_VERSION: int = 4
const REGION_SPACING: float = 170.0
const DEFAULT_NODE_COUNT: int = 18
const START_REGION_ID: String = "region:starting_valley"
const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const ANCHOR_CELLS: Dictionary = {
	"starting_valley": Vector2i(0, 0),
	"blackwood": Vector2i(-1, 0),
	"windscar_highlands": Vector2i(1, 0),
	"veilmoor": Vector2i(0, -1)
}

var world_seed: int = 8242601

func configure(seed_value: int) -> void:
	world_seed = abs(seed_value) if seed_value != 0 else 8242601

func graph_seed() -> int:
	return int(("%d:world_graph:v%d" % [world_seed, GRAPH_FORMAT_VERSION]).hash() & 0x7fffffff)

func region_layer_seed(stable_region_id: String, layer_id: String) -> int:
	return int(("%d:%s:%s" % [world_seed, stable_region_id, layer_id]).hash() & 0x7fffffff)

func generate_graph(target_node_count: int = DEFAULT_NODE_COUNT) -> Dictionary:
	var requested_count: int = maxi(target_node_count, ANCHOR_CELLS.size())
	var nodes_by_cell: Dictionary = {}
	_install_anchor_nodes(nodes_by_cell)

	var rng := RandomNumberGenerator.new()
	rng.seed = graph_seed()
	while nodes_by_cell.size() < requested_count:
		var frontier: Array[Vector2i] = _frontier_cells(nodes_by_cell)
		if frontier.is_empty():
			break
		var chosen_cell: Vector2i = frontier[rng.randi_range(0, frontier.size() - 1)]
		var template_id: String = _pick_template_for_cell(chosen_cell, nodes_by_cell, rng)
		nodes_by_cell[chosen_cell] = _generated_node(chosen_cell, template_id)

	var nodes: Array[Dictionary] = _sorted_nodes(nodes_by_cell)
	var edges: Array[Dictionary] = _build_edges(nodes_by_cell)
	var topology: Dictionary = _annotate_topology(nodes, edges, START_REGION_ID)
	var topology_nodes: Array = topology.get("nodes", nodes) as Array
	var topology_edges: Array = topology.get("edges", edges) as Array
	var route_plan: Dictionary = ROUTE_PLANNER.build(world_seed, topology_nodes, topology_edges)
	return {
		"format_version": GRAPH_FORMAT_VERSION,
		"world_seed": world_seed,
		"graph_seed": graph_seed(),
		"region_spacing": REGION_SPACING,
		"start_region_id": START_REGION_ID,
		"max_graph_depth": int(topology.get("max_graph_depth", 0)),
		"progression_band_counts": topology.get("progression_band_counts", {}).duplicate(true),
		"route_format_version": int(route_plan.get("format_version", 0)),
		"route_class_counts": route_plan.get("route_class_counts", {}).duplicate(true),
		"gateway_count": int(route_plan.get("gateway_count", 0)),
		"shortcut_candidates": (route_plan.get("shortcut_candidates", []) as Array).duplicate(true),
		"nodes": topology_nodes,
		"edges": route_plan.get("edges", topology_edges),
		"anchor_count": ANCHOR_CELLS.size(),
		"generated_count": maxi(0, nodes.size() - ANCHOR_CELLS.size())
	}

func stable_region_id_for_cell(cell: Vector2i) -> String:
	for anchor_id in ANCHOR_CELLS.keys():
		if ANCHOR_CELLS[anchor_id] == cell:
			return "region:%s" % str(anchor_id)
	return "region:cell:%d:%d" % [cell.x, cell.y]

func generation_key_for_cell(cell: Vector2i) -> String:
	var stable_id: String = stable_region_id_for_cell(cell)
	return stable_id.trim_prefix("region:").replace(":", "_")

func _install_anchor_nodes(nodes_by_cell: Dictionary) -> void:
	var anchor_ids: Array[String] = []
	for key in ANCHOR_CELLS.keys():
		anchor_ids.append(str(key))
	anchor_ids.sort()
	for region_id in anchor_ids:
		var cell: Vector2i = ANCHOR_CELLS[region_id]
		var definition: Dictionary = REGION_CATALOG.get_region(region_id)
		nodes_by_cell[cell] = {
			"stable_id": "region:%s" % region_id,
			"generation_key": region_id,
			"graph_cell": cell,
			"center": definition.get("center", _center_for_cell(cell)),
			"display_name": str(definition.get("display_name", region_id.capitalize())),
			"biome": str(definition.get("biome", "green_highlands")),
			"radius": float(definition.get("radius", 68.0)),
			"poi_count": int(definition.get("poi_count", 3)),
			"landmark_module": "legacy:%s" % region_id,
			"anchor": true,
			"catalog_region_id": region_id,
			"template_id": "legacy_anchor"
		}

func _generated_node(cell: Vector2i, template_id: String) -> Dictionary:
	var definition: Dictionary = TEMPLATE_CATALOG.get_template(template_id)
	var stable_id: String = stable_region_id_for_cell(cell)
	return {
		"stable_id": stable_id,
		"generation_key": generation_key_for_cell(cell),
		"graph_cell": cell,
		"center": _center_for_cell(cell),
		"display_name": str(definition.get("display_name", "Unknown Reach")),
		"biome": str(definition.get("biome", "green_highlands")),
		"radius": float(definition.get("radius", 68.0)),
		"poi_count": int(definition.get("poi_count", 3)),
		"landmark_module": str(definition.get("landmark_module", "roadside_ruin")),
		"anchor": false,
		"catalog_region_id": "",
		"template_id": template_id,
		"seed_namespace": "%d:%s" % [world_seed, stable_id]
	}

func _center_for_cell(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * REGION_SPACING, 0.0, float(cell.y) * REGION_SPACING)

func _frontier_cells(nodes_by_cell: Dictionary) -> Array[Vector2i]:
	var unique: Dictionary = {}
	for cell_value in nodes_by_cell.keys():
		if not cell_value is Vector2i:
			continue
		var cell: Vector2i = cell_value as Vector2i
		for direction in DIRECTIONS:
			var candidate: Vector2i = cell + direction
			if not nodes_by_cell.has(candidate):
				unique[candidate] = true
	var result: Array[Vector2i] = []
	for candidate_value in unique.keys():
		if candidate_value is Vector2i:
			result.append(candidate_value as Vector2i)
	result.sort_custom(_cell_less)
	return result

func _pick_template_for_cell(cell: Vector2i, nodes_by_cell: Dictionary, rng: RandomNumberGenerator) -> String:
	var neighbour_biomes: Array[String] = []
	for direction in DIRECTIONS:
		var neighbour_cell: Vector2i = cell + direction
		if not nodes_by_cell.has(neighbour_cell):
			continue
		var neighbour_value: Variant = nodes_by_cell[neighbour_cell]
		if not neighbour_value is Dictionary:
			continue
		var biome_id: String = str((neighbour_value as Dictionary).get("biome", "green_highlands"))
		if not neighbour_biomes.has(biome_id):
			neighbour_biomes.append(biome_id)
	neighbour_biomes.sort()
	if not neighbour_biomes.is_empty() and rng.randf() < 0.68:
		return TEMPLATE_CATALOG.weighted_pick(rng, neighbour_biomes)
	return TEMPLATE_CATALOG.weighted_pick(rng)

func _sorted_nodes(nodes_by_cell: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in nodes_by_cell.values():
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	result.sort_custom(_node_less)
	return result

func _build_edges(nodes_by_cell: Dictionary) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for cell_value in nodes_by_cell.keys():
		if not cell_value is Vector2i:
			continue
		var cell: Vector2i = cell_value as Vector2i
		var node: Dictionary = nodes_by_cell[cell] as Dictionary
		var node_id: String = str(node.get("stable_id", ""))
		for direction in [Vector2i(1, 0), Vector2i(0, 1)]:
			var neighbour_cell: Vector2i = cell + direction
			if not nodes_by_cell.has(neighbour_cell):
				continue
			var neighbour: Dictionary = nodes_by_cell[neighbour_cell] as Dictionary
			var neighbour_id: String = str(neighbour.get("stable_id", ""))
			var from_id: String = node_id
			var to_id: String = neighbour_id
			if to_id < from_id:
				var swap: String = from_id
				from_id = to_id
				to_id = swap
			edges.append({
				"stable_id": "route:%s>%s" % [from_id, to_id],
				"from": from_id,
				"to": to_id,
				"from_cell": cell,
				"to_cell": neighbour_cell,
				"route_type": "world_road"
			})
	edges.sort_custom(_edge_less)
	return edges

func _annotate_topology(nodes: Array[Dictionary], edges: Array[Dictionary], start_id: String) -> Dictionary:
	var adjacency: Dictionary = {}
	for node in nodes:
		adjacency[str(node.get("stable_id", ""))] = []
	for edge in edges:
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if adjacency.has(from_id) and adjacency.has(to_id):
			(adjacency[from_id] as Array).append(to_id)
			(adjacency[to_id] as Array).append(from_id)
	for region_id in adjacency.keys():
		(adjacency[region_id] as Array).sort()

	var depths: Dictionary = {}
	if adjacency.has(start_id):
		depths[start_id] = 0
		var queue: Array[String] = [start_id]
		while not queue.is_empty():
			var current: String = queue.pop_front()
			var next_depth: int = int(depths[current]) + 1
			for neighbour_value in adjacency[current] as Array:
				var neighbour: String = str(neighbour_value)
				if depths.has(neighbour):
					continue
				depths[neighbour] = next_depth
				queue.append(neighbour)

	var max_depth: int = 0
	var band_counts: Dictionary = {"heartland": 0, "frontier": 0, "wilds": 0}
	var annotated_nodes: Array[Dictionary] = []
	for source_node in nodes:
		var node: Dictionary = source_node.duplicate(true)
		var stable_id: String = str(node.get("stable_id", ""))
		var neighbours: Array = (adjacency.get(stable_id, []) as Array).duplicate()
		var depth: int = int(depths.get(stable_id, -1))
		var band: String = _progression_band_for_depth(depth)
		var biome_id: String = str(node.get("biome", "green_highlands"))
		var content_profile: Dictionary = CONTENT_PROFILE_CATALOG.build_profile(biome_id, band, depth)
		node["neighbor_ids"] = neighbours
		node["degree"] = neighbours.size()
		node["graph_depth"] = depth
		node["progression_band"] = band
		node["content_profile_id"] = str(content_profile.get("profile_id", ""))
		node["content_profile"] = content_profile
		max_depth = maxi(max_depth, depth)
		band_counts[band] = int(band_counts.get(band, 0)) + 1
		annotated_nodes.append(node)
	annotated_nodes.sort_custom(_node_less)

	var annotated_edges: Array[Dictionary] = []
	for source_edge in edges:
		var edge: Dictionary = source_edge.duplicate(true)
		var from_depth: int = int(depths.get(str(edge.get("from", "")), -1))
		var to_depth: int = int(depths.get(str(edge.get("to", "")), -1))
		var route_depth: int = maxi(from_depth, to_depth)
		edge["graph_depth"] = route_depth
		edge["progression_band"] = _progression_band_for_depth(route_depth)
		annotated_edges.append(edge)
	annotated_edges.sort_custom(_edge_less)

	return {
		"nodes": annotated_nodes,
		"edges": annotated_edges,
		"max_graph_depth": max_depth,
		"progression_band_counts": band_counts
	}

func _progression_band_for_depth(depth: int) -> String:
	if depth <= 1:
		return "heartland"
	if depth <= 3:
		return "frontier"
	return "wilds"

func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y

func _node_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))

func _edge_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
