extends SceneTree

const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const ACCESS := preload("res://scripts/progression/endgame_region_access.gd")
const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")
const CHOICES := preload("res://scripts/progression/endgame_choice_consequences.gd")
const POSTGAME := preload("res://scripts/progression/postgame_world_profile.gd")
const SAVE := preload("res://scripts/progression/endgame_save_codec.gd")

const SEEDS: Array[int] = [
	81001, 81017, 81103, 81241, 81359, 81473, 81587, 81701,
	81817, 81929, 82051, 82163, 82279, 82393, 82507, 82621,
	82739, 82853, 82967, 83081, 83197, 83311, 83429, 83543
]

func _init() -> void:
	var start_msec: int = Time.get_ticks_msec()
	var total_regions: int = 0
	var moon_runs: int = 0
	var veil_runs: int = 0
	for index in range(SEEDS.size()):
		var seed: int = SEEDS[index]
		var result: Dictionary = _exercise_seed(seed, index)
		if result.get("ok", false) != true:
			_fail("Seed %d failed: %s" % [seed, str(result.get("error", "unknown"))])
			return
		total_regions += int(result.get("regions", 0))
		if str(result.get("route", "")) == "moon":
			moon_runs += 1
		else:
			veil_runs += 1
	var elapsed_msec: int = Time.get_ticks_msec() - start_msec
	if moon_runs == 0 or veil_runs == 0:
		_fail("Stress matrix did not exercise both ending routes")
		return
	if total_regions < SEEDS.size() * 72:
		_fail("Stress matrix generated fewer regions than requested")
		return
	if elapsed_msec > 20000:
		_fail("Endgame seed stress exceeded 20 second budget: %d ms" % elapsed_msec)
		return
	print("ENDGAME_SEED_STRESS_OK seeds=%d regions=%d ms=%d moon=%d veil=%d" % [SEEDS.size(), total_regions, elapsed_msec, moon_runs, veil_runs])
	quit(0)

func _exercise_seed(seed: int, index: int) -> Dictionary:
	var node_count: int = 96 if index % 6 == 0 else 72
	var generator: RefCounted = GRAPH.new()
	generator.call("configure", seed)
	var graph: Dictionary = generator.call("generate_graph", node_count) as Dictionary
	if (graph.get("nodes", []) as Array).size() < node_count:
		return {"ok": false, "error": "world_graph_underfilled"}
	var access: Dictionary = ACCESS.build_access_plan(graph)
	if not ACCESS.validate_plan(access):
		return {"ok": false, "error": "invalid_access_plan"}
	var relic_plan: Dictionary = RELICS.build_plan(graph, access)
	if not RELICS.validate_plan(relic_plan):
		return {"ok": false, "error": "invalid_relic_plan"}

	var repeat_generator: RefCounted = GRAPH.new()
	repeat_generator.call("configure", seed)
	var repeat_graph: Dictionary = repeat_generator.call("generate_graph", node_count) as Dictionary
	var repeat_access: Dictionary = ACCESS.build_access_plan(repeat_graph)
	var repeat_relics: Dictionary = RELICS.build_plan(repeat_graph, repeat_access)
	if var_to_str(access) != var_to_str(repeat_access) or var_to_str(relic_plan) != var_to_str(repeat_relics):
		return {"ok": false, "error": "nondeterministic_endgame_plan"}

	var relic_state: Dictionary = RELICS.create_state(relic_plan)
	var sequence: int = 1
	for objective_id in RELICS.objective_ids():
		var assignment: Dictionary = RELICS.assignment_for_objective(relic_plan, objective_id)
		var acquisition: Dictionary = RELICS.acquire(relic_state, relic_plan, objective_id, str(assignment.get("region_id", "")), sequence)
		if acquisition.get("accepted", false) != true:
			return {"ok": false, "error": "relic_acquisition_failed"}
		relic_state = acquisition.get("state", {}) as Dictionary
		sequence += 1
	if not RELICS.endgame_ready(relic_state, relic_plan):
		return {"ok": false, "error": "relic_gate_not_satisfied"}

	var boss_state: Dictionary = BOSSES.empty_state()
	var campaign_ids: Array[String] = ["campaign:frontier_oath", "campaign:blackwood_pact", "campaign:convergence"]
	var guardian_route: Array[String] = ["hollow_king", "stormbound_titan", "frostbound_wyrm"]
	for boss_id in guardian_route:
		var world_ids: Array[String] = []
		for milestone in boss_state.get("milestone_ids", []) as Array:
			world_ids.append(str(milestone))
		var access_decision: Dictionary = BOSSES.boss_access(boss_id, boss_state, campaign_ids, world_ids)
		if access_decision.get("allowed", false) != true:
			return {"ok": false, "error": "guardian_access_failed:%s:%s" % [boss_id, str(access_decision.get("reason", ""))]}
		var boss_result: Dictionary = BOSSES.record_authoritative_victory(boss_state, boss_id, 1, 1, sequence)
		if boss_result.get("ok", false) != true:
			return {"ok": false, "error": "guardian_progression_failed:%s" % boss_id}
		boss_state = boss_result.get("state", {}) as Dictionary
		sequence += 1
	if int(boss_state.get("guardian_count", 0)) < 3 or int(boss_state.get("highest_guardian_tier", 0)) < 3:
		return {"ok": false, "error": "guardian_tier_coverage_incomplete"}

	var locked_final: Dictionary = BOSSES.boss_access("eclipsed_regent", boss_state, campaign_ids, _string_array(boss_state.get("milestone_ids", []) as Array))
	if locked_final.get("allowed", false) == true:
		return {"ok": false, "error": "final_boss_campaign_gate_bypassed"}
	campaign_ids.append("campaign:endgame_unlocked")
	var final_access: Dictionary = BOSSES.boss_access("eclipsed_regent", boss_state, campaign_ids, _string_array(boss_state.get("milestone_ids", []) as Array))
	if final_access.get("allowed", false) != true:
		return {"ok": false, "error": "final_boss_access_failed"}
	var final_result: Dictionary = BOSSES.record_authoritative_victory(boss_state, "eclipsed_regent", 1, 1, sequence)
	if final_result.get("ok", false) != true:
		return {"ok": false, "error": "final_victory_failed"}
	boss_state = final_result.get("state", {}) as Dictionary
	sequence += 1

	var choice_state: Dictionary = CHOICES.create_state("world:stress:%d" % seed)
	var route: String = "moon" if index % 2 == 0 else "veil"
	var choice_id: String = "choice:moon_oath" if route == "moon" else "choice:veil_bargain"
	var choice_result: Dictionary = CHOICES.apply_choice(choice_state, choice_id, sequence)
	if choice_result.get("accepted", false) != true:
		return {"ok": false, "error": "ending_choice_failed"}
	choice_state = choice_result.get("state", {}) as Dictionary
	if CHOICES.ending_route_decision(route, choice_state).get("allowed", false) != true:
		return {"ok": false, "error": "ending_route_not_allowed"}
	sequence += 1

	var ending_id: String = "ending:moon_restored" if route == "moon" else "ending:veil_bound"
	var choices: Array[String] = []
	for value in choice_state.get("committed_choice_ids", []) as Array:
		choices.append(str(value))
	var profile: Dictionary = POSTGAME.build_profile(seed, ending_id, choices, boss_state, sequence)
	if not POSTGAME.validate_profile(profile):
		return {"ok": false, "error": "invalid_postgame_profile"}
	var region_plan: Dictionary = POSTGAME.build_region_modifier_plan(profile, graph, 12)
	if not POSTGAME.validate_region_plan(region_plan, profile):
		return {"ok": false, "error": "invalid_postgame_region_plan"}

	var snapshot: Dictionary = {
		"completed_campaign": campaign_ids.duplicate(),
		"world_milestones": (boss_state.get("milestone_ids", []) as Array).duplicate(),
		"boss_state": boss_state.duplicate(true),
		"relic_plan": relic_plan.duplicate(true),
		"relic_state": relic_state.duplicate(true),
		"choice_state": choice_state.duplicate(true),
		"postgame_profile": profile.duplicate(true)
	}
	var encoded: Dictionary = SAVE.encode(snapshot, sequence)
	if encoded.is_empty() or not SAVE.validate(encoded):
		return {"ok": false, "error": "save_encode_failed"}
	if var_to_str(SAVE.decode(encoded)) != var_to_str(snapshot):
		return {"ok": false, "error": "save_roundtrip_failed"}

	return {"ok": true, "regions": (graph.get("nodes", []) as Array).size(), "route": route}

func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result

func _fail(message: String) -> void:
	printerr("ENDGAME_SEED_STRESS_FAILED: %s" % message)
	quit(1)
