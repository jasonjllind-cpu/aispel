extends SceneTree

const GENERATOR_SCRIPT := preload("res://scripts/world/world_graph_generator.gd")
const STREAMING_PLANNER := preload("res://scripts/world/world_streaming_planner.gd")
const SUBREGION_GENERATOR := preload("res://scripts/world/subregion_graph_generator.gd")

const QUALITY_SEED: int = 2147483647
const QUALITY_NODE_COUNT: int = 512
const STREAM_BUDGET: int = 2
const MAX_GRAPH_GENERATION_USEC: int = 3000000

func _init() -> void:
	var generator: RefCounted = GENERATOR_SCRIPT.new()
	generator.call("configure", QUALITY_SEED)
	var started_usec: int = Time.get_ticks_usec()
	var graph: Dictionary = generator.call("generate_graph", QUALITY_NODE_COUNT)
	var generation_usec: int = Time.get_ticks_usec() - started_usec
	if generation_usec > MAX_GRAPH_GENERATION_USEC:
		_fail("512-node macro graph exceeded performance gate: %.2f ms" % (float(generation_usec) / 1000.0))
		return
	if not _validate_graph_quality(graph):
		return
	if not _validate_streaming_budget(graph):
		return
	if not _validate_subregion_determinism(graph):
		return

	print("PROCEDURAL_GENERATION_2_OK generation_ms=%.2f nodes=%d edges=%d placements=%d" % [
		float(generation_usec) / 1000.0,
		(graph.get("nodes", []) as Array).size(),
		(graph.get("edges", []) as Array).size(),
		(graph.get("distribution_placements", []) as Array).size()
	])
	quit(0)

func _validate_graph_quality(graph: Dictionary) -> bool:
	var nodes: Array = graph.get("nodes", []) as Array
	var edges: Array = graph.get("edges", []) as Array
	var placements: Array = graph.get("distribution_placements", []) as Array
	if nodes.size() != QUALITY_NODE_COUNT:
		return _fail("Quality graph node count mismatch")
	if int(graph.get("anchor_count", 0)) != 4 or int(graph.get("generated_count", -1)) != QUALITY_NODE_COUNT - 4:
		return _fail("Quality graph anchor/generated summary mismatch")
	if edges.size() < QUALITY_NODE_COUNT - 1:
		return _fail("Quality graph does not contain enough routes for connectivity")
	if int(graph.get("max_graph_depth", 0)) < 5:
		return _fail("Large graph did not produce meaningful progression depth")
	var band_counts: Dictionary = graph.get("progression_band_counts", {}) as Dictionary
	var band_total: int = int(band_counts.get("heartland", 0)) + int(band_counts.get("frontier", 0)) + int(band_counts.get("wilds", 0))
	if band_total != QUALITY_NODE_COUNT:
		return _fail("Progression band counts do not cover the full graph")
	var route_counts: Dictionary = graph.get("route_class_counts", {}) as Dictionary
	if route_counts.is_empty():
		return _fail("Large graph is missing route hierarchy summary")
	var settlement_count: int = int(graph.get("settlement_count", 0))
	var landmark_count: int = int(graph.get("major_landmark_count", 0))
	if settlement_count <= 0 or landmark_count <= 0:
		return _fail("Large graph did not distribute settlements and landmarks")
	if placements.size() != settlement_count + landmark_count:
		return _fail("Distribution placement summary mismatch")
	var seen_ids: Dictionary = {}
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Quality graph contains invalid node data")
		var node: Dictionary = node_value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		if stable_id.is_empty() or seen_ids.has(stable_id):
			return _fail("Quality graph contains missing or duplicate region IDs")
		if str(node.get("content_profile_id", "")).is_empty():
			return _fail("Quality graph node is missing content profile integration")
		if str(node.get("distribution_role", "")).is_empty():
			return _fail("Quality graph node is missing distribution role integration")
		seen_ids[stable_id] = true
	return true

func _validate_streaming_budget(graph: Dictionary) -> bool:
	var nodes: Array = graph.get("nodes", []) as Array
	var start_id: String = str(graph.get("start_region_id", "region:starting_valley"))
	var start_center: Vector3 = Vector3.ZERO
	for node_value in nodes:
		if node_value is Dictionary and str((node_value as Dictionary).get("stable_id", "")) == start_id:
			start_center = (node_value as Dictionary).get("center", Vector3.ZERO)
			break
	var candidates: Array[Dictionary] = STREAMING_PLANNER.rank_candidates(
		nodes,
		start_center,
		start_id,
		"",
		1000.0,
		STREAM_BUDGET,
		{}
	)
	if candidates.is_empty() or candidates.size() > STREAM_BUDGET:
		return _fail("Streaming planner violated bounded load budget")
	var valid_ids: Dictionary = {}
	for node_value in nodes:
		if node_value is Dictionary:
			valid_ids[str((node_value as Dictionary).get("stable_id", ""))] = true
	for candidate in candidates:
		if not valid_ids.has(str(candidate.get("stable_id", ""))):
			return _fail("Streaming planner returned unknown graph region")
	return true

func _validate_subregion_determinism(graph: Dictionary) -> bool:
	var parent: Dictionary = {}
	for node_value in graph.get("nodes", []) as Array:
		if node_value is Dictionary and (node_value as Dictionary).get("anchor", false) != true:
			parent = (node_value as Dictionary).duplicate(true)
			break
	if parent.is_empty():
		return _fail("No generated region available for subregion quality gate")
	var first: Dictionary = SUBREGION_GENERATOR.generate(QUALITY_SEED, parent)
	var second: Dictionary = SUBREGION_GENERATOR.generate(QUALITY_SEED, parent)
	if first.is_empty() or var_to_str(first) != var_to_str(second):
		return _fail("Subregion graph regeneration is not deterministic")
	if str(first.get("parent_region_id", "")) != str(parent.get("stable_id", "")):
		return _fail("Subregion graph lost parent region identity")
	var subnodes: Array = first.get("nodes", []) as Array
	var subedges: Array = first.get("edges", []) as Array
	if subnodes.size() < 6 or subedges.size() < subnodes.size() - 1:
		return _fail("Subregion graph failed connectivity/scale quality gate")
	return true

func _fail(message: String) -> bool:
	printerr("PROCEDURAL_GENERATION_2_FAILED: %s" % message)
	quit(1)
	return false
