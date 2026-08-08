extends SceneTree

const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")
const STREAMING_PLANNER := preload("res://scripts/world/world_streaming_planner.gd")

func _init() -> void:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", 8242601)
	var graph: Dictionary = generator.call("generate_graph", 30)
	var nodes: Array = graph.get("nodes", []) as Array
	var start: Dictionary = _node_by_id(nodes, "region:starting_valley")
	var target: Dictionary = _deepest_generated_node(nodes)
	if start.is_empty() or target.is_empty():
		_fail("Streaming planner test could not resolve start/target regions")
		return
	var player_position: Vector3 = start.get("center", Vector3.ZERO)
	var target_id: String = str(target.get("stable_id", ""))

	var baseline: Array[Dictionary] = STREAMING_PLANNER.rank_candidates(nodes, player_position, "region:starting_valley", "", 10000.0, 100)
	var routed: Array[Dictionary] = STREAMING_PLANNER.rank_candidates(nodes, player_position, "region:starting_valley", target_id, 10000.0, 100)
	var repeat: Array[Dictionary] = STREAMING_PLANNER.rank_candidates(nodes, player_position, "region:starting_valley", target_id, 10000.0, 100)
	if var_to_str(routed) != var_to_str(repeat):
		_fail("Streaming priority plan is not deterministic")
		return
	var baseline_target: Dictionary = _candidate_by_id(baseline, target_id)
	var routed_target: Dictionary = _candidate_by_id(routed, target_id)
	if baseline_target.is_empty() or routed_target.is_empty():
		_fail("Streaming priority plan lost route target candidate")
		return
	if bool(baseline_target.get("on_active_route", false)):
		_fail("Baseline streaming plan unexpectedly contains an active route")
		return
	if not bool(routed_target.get("on_active_route", false)):
		_fail("Route-aware streaming plan did not mark route target")
		return
	if float(routed_target.get("score", INF)) >= float(baseline_target.get("score", INF)):
		_fail("Active route did not improve streaming priority score")
		return

	var budgeted: Array[Dictionary] = STREAMING_PLANNER.rank_candidates(nodes, player_position, "region:starting_valley", target_id, 10000.0, 2)
	if budgeted.size() > 2:
		_fail("Streaming planner exceeded generation/load budget")
		return
	if budgeted.is_empty():
		_fail("Streaming planner produced no candidates inside a large radius")
		return
	for candidate in budgeted:
		if int(candidate.get("graph_hops", 999)) >= 999:
			_fail("Streaming planner did not use graph topology for candidate hops")
			return
		var tier: String = str(candidate.get("priority_tier", ""))
		if not ["immediate", "preload", "background"].has(tier):
			_fail("Streaming planner produced invalid priority tier")
			return

	var excluded: Dictionary = {str(budgeted[0].get("stable_id", "")): true}
	var next_plan: Array[Dictionary] = STREAMING_PLANNER.rank_candidates(nodes, player_position, "region:starting_valley", target_id, 10000.0, 2, excluded)
	for candidate in next_plan:
		if excluded.has(str(candidate.get("stable_id", ""))):
			_fail("Streaming planner did not exclude an already active region")
			return

	var none: Array[Dictionary] = STREAMING_PLANNER.rank_candidates(nodes, player_position, "region:starting_valley", target_id, 10000.0, 0)
	if not none.is_empty():
		_fail("Zero streaming budget still produced candidates")
		return

	print("WORLD_STREAMING_PLANNER_OK target=%s budgeted=%d" % [target_id, budgeted.size()])
	quit(0)

func _node_by_id(nodes: Array, stable_id: String) -> Dictionary:
	for node_value in nodes:
		if node_value is Dictionary and str((node_value as Dictionary).get("stable_id", "")) == stable_id:
			return (node_value as Dictionary).duplicate(true)
	return {}

func _deepest_generated_node(nodes: Array) -> Dictionary:
	var result: Dictionary = {}
	var best_depth: int = -1
	for node_value in nodes:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		if node.get("anchor", false) == true:
			continue
		var depth: int = int(node.get("graph_depth", -1))
		if depth > best_depth or (depth == best_depth and str(node.get("stable_id", "")) < str(result.get("stable_id", "~"))):
			best_depth = depth
			result = node.duplicate(true)
	return result

func _candidate_by_id(candidates: Array[Dictionary], stable_id: String) -> Dictionary:
	for candidate in candidates:
		if str(candidate.get("stable_id", "")) == stable_id:
			return candidate.duplicate(true)
	return {}

func _fail(message: String) -> void:
	printerr("WORLD_STREAMING_PLANNER_FAILED: %s" % message)
	quit(1)
