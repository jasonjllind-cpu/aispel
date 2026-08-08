extends SceneTree

const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const ACCESS := preload("res://scripts/progression/endgame_region_access.gd")
const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")
const CHOICES := preload("res://scripts/progression/endgame_choice_consequences.gd")
const POSTGAME := preload("res://scripts/progression/postgame_world_profile.gd")
const SAVE := preload("res://scripts/progression/endgame_save_codec.gd")

const SEEDS: Array[int] = [880001, 880113, 880227, 880339, 880443, 880557, 880669, 880771, 880883, 880997, 881109, 881221, 881337, 881449, 881553, 881669]
const GRAPH_SIZE: int = 72
const SESSION_ROUNDTRIPS: int = 32

func _init() -> void:
	var final_depth_sum: int = 0
	var guardian_depth_sum: int = 0
	var total_relic_depth: int = 0
	var relic_samples: int = 0
	for seed in SEEDS:
		var result: Dictionary = _exercise_seed(seed)
		if result.get("ok", false) != true:
			_fail("seed=%d %s" % [seed, str(result.get("error", "unknown"))])
			return
		final_depth_sum += int(result.get("final_depth", 0))
		guardian_depth_sum += int(result.get("guardian_depth", 0))
		total_relic_depth += int(result.get("relic_depth_sum", 0))
		relic_samples += int(result.get("relic_count", 0))
	if relic_samples <= 0:
		_fail("No relic placement samples were produced")
		return
	var avg_final: float = float(final_depth_sum) / float(SEEDS.size())
	var avg_guardian: float = float(guardian_depth_sum) / float(SEEDS.size())
	var avg_relic: float = float(total_relic_depth) / float(relic_samples)
	if avg_final < avg_guardian:
		_fail("Final regions are shallower than guardian regions on average")
		return
	if avg_relic <= 0.0:
		_fail("Relic objectives collapsed into graph root across coverage seeds")
		return
	print("ENDGAME_BALANCE_STRESS_OK seeds=%d roundtrips=%d avg_final=%.2f avg_guardian=%.2f avg_relic=%.2f" % [SEEDS.size(), SESSION_ROUNDTRIPS, avg_final, avg_guardian, avg_relic])
	quit(0)

func _exercise_seed(seed: int) -> Dictionary:
	var generator: RefCounted = GRAPH.new()
	generator.call("configure", seed)
	var graph: Dictionary = generator.call("generate_graph", GRAPH_SIZE) as Dictionary
	var access: Dictionary = ACCESS.build_access_plan(graph)
	if not ACCESS.validate_plan(access):
		return _error("invalid endgame access plan")
	var final_region: String = ACCESS.region_for_role(access, "final_reach")
	var guardian_region: String = ACCESS.region_for_role(access, "guardian_reach")
	var final_assignment: Dictionary = ACCESS.assignment_for_region(access, final_region)
	var guardian_assignment: Dictionary = ACCESS.assignment_for_region(access, guardian_region)
	var final_depth: int = int(final_assignment.get("graph_depth", -1))
	var guardian_depth: int = int(guardian_assignment.get("graph_depth", -1))
	if final_depth < guardian_depth or final_depth < 0:
		return _error("invalid final/guardian depth ordering")

	var relic_plan: Dictionary = RELICS.build_plan(graph, access)
	if not RELICS.validate_plan(relic_plan):
		return _error("invalid relic plan")
	var relic_state: Dictionary = RELICS.create_state(relic_plan)
	var relic_regions: Dictionary = {}
	var relic_depth_sum: int = 0
	var sequence: int = 1
	for objective_id in RELICS.objective_ids():
		var assignment: Dictionary = RELICS.assignment_for_objective(relic_plan, objective_id)
		var region_id: String = str(assignment.get("region_id", ""))
		if region_id == final_region or relic_regions.has(region_id):
			return _error("relic placement violates unique/pre-final distribution")
		relic_regions[region_id] = true
		relic_depth_sum += int(assignment.get("graph_depth", 0))
		var acquired: Dictionary = RELICS.acquire(relic_state, relic_plan, objective_id, region_id, sequence)
		if acquired.get("accepted", false) != true:
			return _error("relic acquisition failed")
		relic_state = acquired.get("state", {}) as Dictionary
		sequence += 1
	if not RELICS.endgame_ready(relic_state, relic_plan):
		return _error("completed relic state did not open endgame gate")

	var boss_state: Dictionary = BOSSES.empty_state()
	for boss_id in ["hollow_king", "stormbound_titan", "frostbound_wyrm"]:
		var victory: Dictionary = BOSSES.record_authoritative_victory(boss_state, boss_id, 1, 1, sequence)
		if victory.get("ok", false) != true:
			return _error("guardian victory failed: %s" % boss_id)
		boss_state = victory.get("state", {}) as Dictionary
		sequence += 1
	if int(boss_state.get("guardian_count", 0)) != 3:
		return _error("guardian progression did not reach three")
	var final_victory: Dictionary = BOSSES.record_authoritative_victory(boss_state, "eclipsed_regent", 1, 1, sequence)
	if final_victory.get("ok", false) != true:
		return _error("final victory failed after three guardians")
	boss_state = final_victory.get("state", {}) as Dictionary
	sequence += 1

	var choice_state: Dictionary = CHOICES.create_state("world:%d" % seed)
	var route: String = "moon" if seed % 2 == 0 else "veil"
	var choice_id: String = "choice:moon_oath" if route == "moon" else "choice:veil_bargain"
	var choice_result: Dictionary = CHOICES.apply_choice(choice_state, choice_id, sequence)
	if choice_result.get("accepted", false) != true:
		return _error("ending choice failed")
	choice_state = choice_result.get("state", {}) as Dictionary
	sequence += 1
	if CHOICES.ending_route_decision(route, choice_state).get("allowed", false) != true:
		return _error("chosen ending route unavailable")

	var ending_id: String = "ending:moon_restored" if route == "moon" else "ending:veil_bound"
	var completed_choices: Array[String] = []
	for value in choice_state.get("committed_choice_ids", []) as Array:
		completed_choices.append(str(value))
	var profile: Dictionary = POSTGAME.build_profile(seed, ending_id, completed_choices, boss_state, sequence)
	if not POSTGAME.validate_profile(profile):
		return _error("invalid postgame profile")
	var postgame_plan: Dictionary = POSTGAME.build_region_modifier_plan(profile, graph, 8)
	if not POSTGAME.validate_region_plan(postgame_plan, profile) or (postgame_plan.get("assignments", []) as Array).size() != 8:
		return _error("postgame changed-world coverage invalid")

	var world_milestones: Array[String] = ["world_milestone:windscar_beacon", "dungeon_milestone:three_guardians_defeated", "campaign_milestone:final_boss_defeated"]
	var snapshot: Dictionary = {
		"completed_campaign": ["campaign:frontier_oath", "campaign:blackwood_pact", "campaign:convergence", "campaign:endgame_unlocked"],
		"world_milestones": world_milestones,
		"boss_state": boss_state,
		"relic_plan": relic_plan,
		"relic_state": relic_state,
		"choice_state": choice_state,
		"postgame_profile": profile
	}
	if not SAVE.validate_snapshot(snapshot):
		return _error("completed session snapshot invalid")
	var expected: String = var_to_str(snapshot)
	for roundtrip in range(SESSION_ROUNDTRIPS):
		var encoded: Dictionary = SAVE.encode(snapshot, roundtrip + 1)
		if not SAVE.validate(encoded):
			return _error("save validation failed at roundtrip %d" % roundtrip)
		var decoded: Dictionary = SAVE.decode(encoded)
		if var_to_str(decoded) != expected:
			return _error("session state drifted at roundtrip %d" % roundtrip)
		snapshot = decoded
	return {
		"ok": true,
		"final_depth": final_depth,
		"guardian_depth": guardian_depth,
		"relic_depth_sum": relic_depth_sum,
		"relic_count": RELICS.objective_ids().size()
	}

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _fail(message: String) -> void:
	printerr("ENDGAME_BALANCE_STRESS_FAILED: %s" % message)
	quit(1)
