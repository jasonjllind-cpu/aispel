extends SceneTree

const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

func _init() -> void:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", 8242601)
	var graph: Dictionary = generator.call("generate_graph", 48)
	var repeat: Dictionary = generator.call("generate_graph", 48)
	if var_to_str(graph) != var_to_str(repeat):
		_fail("World distribution is not deterministic for the same seed")
		return
	if not _validate_distribution(graph, 48):
		return

	generator.call("configure", 8242602)
	var changed: Dictionary = generator.call("generate_graph", 48)
	if not _validate_distribution(changed, 48):
		return
	if _distribution_signature(graph) == _distribution_signature(changed):
		_fail("Different world seeds produced the same distribution signature")
		return

	print("WORLD_DISTRIBUTION_PLANNER_OK settlements=%d landmarks=%d" % [
		int(graph.get("settlement_count", 0)),
		int(graph.get("major_landmark_count", 0))
	])
	quit(0)

func _validate_distribution(graph: Dictionary, expected_nodes: int) -> bool:
	if int(graph.get("distribution_format_version", 0)) < 1:
		return _fail("Distribution plan has no versioned format")
	var constraints: Dictionary = graph.get("distribution_constraints", {}) as Dictionary
	if constraints.get("settlements_not_adjacent", false) != true:
		return _fail("Settlement spacing constraint is not declared")
	if constraints.get("major_landmarks_not_adjacent", false) != true:
		return _fail("Major landmark spacing constraint is not declared")
	if constraints.get("settlement_landmark_overlap", true) != false:
		return _fail("Distribution overlap constraint is invalid")

	var nodes: Array = graph.get("nodes", []) as Array
	var placements: Array = graph.get("distribution_placements", []) as Array
	if nodes.size() != expected_nodes:
		return _fail("Distribution test generated the wrong macro node count")
	var nodes_by_id: Dictionary = {}
	var settlements: Dictionary = {}
	var landmarks: Dictionary = {}
	var observed_settlements: int = 0
	var observed_landmarks: int = 0
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Distribution graph contains invalid node data")
		var node: Dictionary = node_value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		if stable_id.is_empty() or nodes_by_id.has(stable_id):
			return _fail("Distribution graph has missing or duplicate node IDs")
		var role: String = str(node.get("distribution_role", ""))
		if not ["authored_anchor", "settlement", "major_landmark", "exploration"].has(role):
			return _fail("Distribution graph contains an unknown role")
		if node.get("anchor", false) == true:
			if role != "authored_anchor":
				return _fail("Authored anchor was modified by distribution planner")
			if not str(node.get("distribution_id", "")).is_empty():
				return _fail("Authored anchor received generated distribution ID")
		elif role == "settlement":
			observed_settlements += 1
			settlements[stable_id] = true
			if str(node.get("distribution_id", "")) != "distribution:%s" % stable_id:
				return _fail("Settlement has invalid stable distribution ID")
		elif role == "major_landmark":
			observed_landmarks += 1
			landmarks[stable_id] = true
			if str(node.get("distribution_id", "")) != "distribution:%s" % stable_id:
				return _fail("Major landmark has invalid stable distribution ID")
		elif not str(node.get("distribution_id", "")).is_empty():
			return _fail("Exploration node received a distribution ID")
		nodes_by_id[stable_id] = node

	if observed_settlements != int(graph.get("settlement_count", -1)):
		return _fail("Settlement summary does not match annotated nodes")
	if observed_landmarks != int(graph.get("major_landmark_count", -1)):
		return _fail("Major landmark summary does not match annotated nodes")
	if observed_settlements <= 0 or observed_landmarks <= 0:
		return _fail("Large graph did not receive both settlements and major landmarks")
	if placements.size() != observed_settlements + observed_landmarks:
		return _fail("Distribution placement count does not match node annotations")

	var placement_ids: Dictionary = {}
	var placement_regions: Dictionary = {}
	for placement_value in placements:
		if not placement_value is Dictionary:
			return _fail("Distribution contains invalid placement data")
		var placement: Dictionary = placement_value as Dictionary
		var placement_id: String = str(placement.get("stable_id", ""))
		var region_id: String = str(placement.get("region_id", ""))
		var placement_type: String = str(placement.get("type", ""))
		if placement_id.is_empty() or placement_ids.has(placement_id):
			return _fail("Distribution placements have missing or duplicate stable IDs")
		if region_id.is_empty() or not nodes_by_id.has(region_id) or placement_regions.has(region_id):
			return _fail("Distribution placement references an invalid or duplicate region")
		var node: Dictionary = nodes_by_id[region_id] as Dictionary
		if node.get("anchor", false) == true:
			return _fail("Generated distribution placement used an authored anchor")
		if placement_type == "settlement":
			if not settlements.has(region_id) or str(placement.get("module", "")) != "settlement_hub":
				return _fail("Settlement placement does not match its annotated macro node")
		elif placement_type == "major_landmark":
			if not landmarks.has(region_id) or str(placement.get("module", "")).is_empty():
				return _fail("Major landmark placement does not match its annotated macro node")
		else:
			return _fail("Distribution contains an unknown placement type")
		placement_ids[placement_id] = true
		placement_regions[region_id] = true

	if not _validate_spacing(settlements, nodes_by_id, "settlements"):
		return false
	if not _validate_spacing(landmarks, nodes_by_id, "major landmarks"):
		return false
	for stable_id in settlements.keys():
		if landmarks.has(stable_id):
			return _fail("Settlement and major landmark overlap on the same region")
	return true

func _validate_spacing(selected: Dictionary, nodes_by_id: Dictionary, label: String) -> bool:
	for stable_id_value in selected.keys():
		var stable_id: String = str(stable_id_value)
		var node: Dictionary = nodes_by_id[stable_id] as Dictionary
		for neighbour_value in node.get("neighbor_ids", []) as Array:
			if selected.has(str(neighbour_value)):
				return _fail("Adjacent %s violate macro distribution spacing" % label)
	return true

func _distribution_signature(graph: Dictionary) -> String:
	var parts: Array[String] = []
	for placement_value in graph.get("distribution_placements", []) as Array:
		if placement_value is Dictionary:
			var placement: Dictionary = placement_value as Dictionary
			parts.append("%s=%s" % [str(placement.get("type", "")), str(placement.get("region_id", ""))])
	parts.sort()
	return "|".join(parts)

func _fail(message: String) -> bool:
	printerr("WORLD_DISTRIBUTION_PLANNER_FAILED: %s" % message)
	quit(1)
	return false
