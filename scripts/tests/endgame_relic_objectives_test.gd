extends SceneTree

const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const ACCESS := preload("res://scripts/progression/endgame_region_access.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")

func _init() -> void:
	var generator: RefCounted = GRAPH.new()
	generator.call("configure", 83082601)
	var graph_a: Dictionary = generator.call("generate_graph", 64) as Dictionary
	var access_a: Dictionary = ACCESS.build_access_plan(graph_a)
	var plan_a: Dictionary = RELICS.build_plan(graph_a, access_a)
	if not RELICS.validate_plan(plan_a):
		_fail("Generated relic plan is invalid")
		return

	var generator_b: RefCounted = GRAPH.new()
	generator_b.call("configure", 83082601)
	var graph_b: Dictionary = generator_b.call("generate_graph", 64) as Dictionary
	var plan_b: Dictionary = RELICS.build_plan(graph_b, ACCESS.build_access_plan(graph_b))
	if var_to_str(plan_a) != var_to_str(plan_b):
		_fail("Same seed produced different relic objective plan")
		return

	var state: Dictionary = RELICS.create_state(plan_a)
	if not RELICS.validate_state(state, plan_a):
		_fail("Fresh relic objective state is invalid")
		return
	if RELICS.endgame_ready(state, plan_a):
		_fail("Fresh state incorrectly satisfies endgame relic gate")
		return

	var sequence: int = 10
	for objective_id in RELICS.objective_ids():
		var assignment: Dictionary = RELICS.assignment_for_objective(plan_a, objective_id)
		if assignment.is_empty():
			_fail("Missing deterministic placement for %s" % objective_id)
			return
		var wrong: Dictionary = RELICS.acquire(state, plan_a, objective_id, "region:wrong", sequence)
		if str(wrong.get("reason", "")) != "wrong_region":
			_fail("Relic acquisition ignored deterministic source region")
			return
		var result: Dictionary = RELICS.acquire(state, plan_a, objective_id, str(assignment.get("region_id", "")), sequence)
		if result.get("accepted", false) != true:
			_fail("Valid relic acquisition failed for %s" % objective_id)
			return
		state = result.get("state", {}) as Dictionary
		sequence += 1

	if not RELICS.endgame_ready(state, plan_a):
		_fail("All relic objectives did not satisfy endgame gate")
		return
	if not RELICS.missing_objectives(state, plan_a).is_empty():
		_fail("Completed relic state still reports missing objectives")
		return

	var empty_inventory: Dictionary = {}
	var grants: Array[Dictionary] = RELICS.recovery_grants(state, plan_a, empty_inventory)
	if grants.size() != RELICS.objective_ids().size():
		_fail("Reload recovery did not restore every acquired missing relic")
		return
	var recovered_inventory: Dictionary = {}
	for grant in grants:
		recovered_inventory[str(grant.get("item_id", ""))] = int(grant.get("amount", 0))
	if not RELICS.recovery_grants(state, plan_a, recovered_inventory).is_empty():
		_fail("Recovery would duplicate relics already present in inventory")
		return

	var final_region: String = str(plan_a.get("final_region_id", ""))
	for objective_id in RELICS.objective_ids():
		if str(RELICS.assignment_for_objective(plan_a, objective_id).get("region_id", "")) == final_region:
			_fail("Endgame relic was placed inside final region it is supposed to unlock")
			return

	print("ENDGAME_RELIC_OBJECTIVES_OK plan=%s revision=%d" % [str(plan_a.get("plan_id", "")), int(state.get("revision", 0))])
	quit(0)

func _fail(message: String) -> void:
	printerr("ENDGAME_RELIC_OBJECTIVES_FAILED: %s" % message)
	quit(1)
