extends SceneTree

const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const ACCESS := preload("res://scripts/progression/endgame_region_access.gd")

func _init() -> void:
	if not ACCESS.campaign_contract_valid():
		_fail("Endgame access references unknown campaign milestones")
		return
	var first_generator: RefCounted = GRAPH.new()
	first_generator.call("configure", 81082601)
	var graph_a: Dictionary = first_generator.call("generate_graph", 48) as Dictionary
	var plan_a: Dictionary = ACCESS.build_access_plan(graph_a)
	if not ACCESS.validate_plan(plan_a):
		_fail("Generated endgame access plan is invalid")
		return
	var second_generator: RefCounted = GRAPH.new()
	second_generator.call("configure", 81082601)
	var graph_b: Dictionary = second_generator.call("generate_graph", 48) as Dictionary
	var plan_b: Dictionary = ACCESS.build_access_plan(graph_b)
	if var_to_str(plan_a) != var_to_str(plan_b):
		_fail("Same seed produced different endgame access plans")
		return

	var convergence_id: String = ACCESS.region_for_role(plan_a, "convergence_gate")
	var guardian_id: String = ACCESS.region_for_role(plan_a, "guardian_reach")
	var final_id: String = ACCESS.region_for_role(plan_a, "final_reach")
	if convergence_id.is_empty() or guardian_id.is_empty() or final_id.is_empty():
		_fail("Endgame access roles are incomplete")
		return
	if convergence_id == guardian_id or convergence_id == final_id or guardian_id == final_id:
		_fail("Endgame access roles must use distinct regions")
		return

	var no_campaign: Array[String] = []
	var no_world: Array[String] = []
	if bool(ACCESS.evaluate_region(plan_a, final_id, no_campaign, no_world).get("allowed", true)):
		_fail("Final reach opened without campaign progression")
		return
	var campaign_convergence: Array[String] = ["campaign:convergence"]
	var beacon: Array[String] = ["world_milestone:windscar_beacon"]
	if not bool(ACCESS.evaluate_region(plan_a, convergence_id, campaign_convergence, beacon).get("allowed", false)):
		_fail("Convergence gate remained locked after valid campaign/exploration state")
		return
	var one_guardian: Array[String] = ["dungeon_milestone:one_guardian_defeated"]
	if not bool(ACCESS.evaluate_region(plan_a, guardian_id, campaign_convergence, one_guardian).get("allowed", false)):
		_fail("Guardian reach remained locked after guardian progression")
		return
	var campaign_endgame: Array[String] = ["campaign:endgame_unlocked"]
	var three_guardians: Array[String] = ["dungeon_milestone:three_guardians_defeated"]
	if not bool(ACCESS.evaluate_region(plan_a, final_id, campaign_endgame, three_guardians).get("allowed", false)):
		_fail("Final reach remained locked after endgame campaign unlock")
		return

	var normal_region: String = ""
	for node_value in graph_a.get("nodes", []) as Array:
		if not node_value is Dictionary:
			continue
		var candidate: String = str((node_value as Dictionary).get("stable_id", ""))
		if candidate != convergence_id and candidate != guardian_id and candidate != final_id:
			normal_region = candidate
			break
	if normal_region.is_empty() or not bool(ACCESS.evaluate_region(plan_a, normal_region, no_campaign, no_world).get("allowed", false)):
		_fail("Ordinary world regions were accidentally campaign-gated")
		return

	var final_assignment: Dictionary = ACCESS.assignment_for_region(plan_a, final_id)
	var guardian_assignment: Dictionary = ACCESS.assignment_for_region(plan_a, guardian_id)
	if int(final_assignment.get("graph_depth", -1)) < int(guardian_assignment.get("graph_depth", -1)):
		_fail("Final reach is not selected from deepest world-graph tier")
		return

	print("ENDGAME_REGION_ACCESS_OK plan=%s final=%s" % [str(plan_a.get("plan_id", "")), final_id])
	quit(0)

func _fail(message: String) -> void:
	printerr("ENDGAME_REGION_ACCESS_FAILED: %s" % message)
	quit(1)
