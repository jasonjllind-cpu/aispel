extends SceneTree

const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const ACCESS := preload("res://scripts/progression/endgame_region_access.gd")
const CAMPAIGN := preload("res://scripts/progression/campaign_progression_catalog.gd")
const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")
const CHOICES := preload("res://scripts/progression/endgame_choice_consequences.gd")
const POSTGAME := preload("res://scripts/progression/postgame_world_profile.gd")
const SAVE := preload("res://scripts/progression/endgame_save_codec.gd")
const NETWORK := preload("res://scripts/network/network_endgame_replicator.gd")
const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")

func _init() -> void:
	var seed: int = 89082601
	var generator: RefCounted = GRAPH.new()
	generator.call("configure", seed)
	var graph: Dictionary = generator.call("generate_graph", 96) as Dictionary
	var access: Dictionary = ACCESS.build_access_plan(graph)
	if not ACCESS.validate_plan(access):
		_fail("Release candidate world has invalid endgame access plan")
		return
	var final_region: String = ACCESS.region_for_role(access, "final_reach")
	if final_region.is_empty():
		_fail("Release candidate world has no final reach")
		return

	var relic_plan: Dictionary = RELICS.build_plan(graph, access)
	var relic_state: Dictionary = RELICS.create_state(relic_plan)
	if not RELICS.validate_plan(relic_plan) or not RELICS.validate_state(relic_state, relic_plan):
		_fail("Release candidate relic plan/state invalid")
		return
	var sequence: int = 1
	for objective_id in RELICS.objective_ids():
		var assignment: Dictionary = RELICS.assignment_for_objective(relic_plan, objective_id)
		var acquired: Dictionary = RELICS.acquire(relic_state, relic_plan, objective_id, str(assignment.get("region_id", "")), sequence)
		if acquired.get("accepted", false) != true:
			_fail("Release candidate relic acquisition failed: %s" % objective_id)
			return
		relic_state = acquired.get("state", {}) as Dictionary
		sequence += 1
	if not RELICS.endgame_ready(relic_state, relic_plan):
		_fail("Release candidate relic progression did not unlock endgame readiness")
		return

	var campaign_completed: Array[String] = ["campaign:frontier_oath", "campaign:blackwood_pact", "campaign:convergence"]
	var world_milestones: Array[String] = ["world_milestone:windscar_beacon"]
	var boss_state: Dictionary = BOSSES.empty_state()
	for boss_id in ["hollow_king", "stormbound_titan", "frostbound_wyrm"]:
		var access_decision: Dictionary = BOSSES.boss_access(boss_id, boss_state, campaign_completed, world_milestones)
		if access_decision.get("allowed", false) != true:
			_fail("Release candidate guardian access failed: %s %s" % [boss_id, str(access_decision.get("missing_requirements", []))])
			return
		var victory: Dictionary = BOSSES.record_authoritative_victory(boss_state, boss_id, 1, 1, sequence)
		if victory.get("ok", false) != true:
			_fail("Release candidate guardian victory failed: %s" % boss_id)
			return
		boss_state = victory.get("state", {}) as Dictionary
		for milestone in victory.get("event", {}).get("milestones_added", []) as Array:
			var milestone_id: String = str(milestone)
			if not world_milestones.has(milestone_id):
				world_milestones.append(milestone_id)
		sequence += 1
	if not world_milestones.has("dungeon_milestone:three_guardians_defeated"):
		_fail("Release candidate did not emit three-guardian milestone")
		return

	var endgame_available: Array[String] = CAMPAIGN.available_milestones(campaign_completed, world_milestones)
	if not endgame_available.has("campaign:endgame_unlocked"):
		_fail("Campaign endgame milestone not available after guardian progression")
		return
	campaign_completed.append("campaign:endgame_unlocked")
	if ACCESS.evaluate_region(access, final_region, campaign_completed, world_milestones).get("allowed", false) != true:
		_fail("Final reach remained locked after campaign and guardian prerequisites")
		return

	var final_access: Dictionary = BOSSES.boss_access("eclipsed_regent", boss_state, campaign_completed, world_milestones)
	if final_access.get("allowed", false) != true:
		_fail("Final boss remained locked in release candidate progression")
		return
	var final_victory: Dictionary = BOSSES.record_authoritative_victory(boss_state, "eclipsed_regent", 1, 1, sequence)
	if final_victory.get("ok", false) != true:
		_fail("Final boss victory rejected in release candidate progression")
		return
	boss_state = final_victory.get("state", {}) as Dictionary
	for milestone in final_victory.get("event", {}).get("milestones_added", []) as Array:
		var milestone_id: String = str(milestone)
		if not world_milestones.has(milestone_id):
			world_milestones.append(milestone_id)
	sequence += 1

	var choice_state: Dictionary = CHOICES.create_state("world:release_candidate")
	var choice_result: Dictionary = CHOICES.apply_choice(choice_state, "choice:moon_oath", sequence)
	if choice_result.get("accepted", false) != true:
		_fail("Moon ending choice failed in release candidate progression")
		return
	choice_state = choice_result.get("state", {}) as Dictionary
	sequence += 1
	var ending_state_ids: Array[String] = world_milestones.duplicate()
	ending_state_ids.append("choice:moon_oath")
	var endings_available: Array[String] = CAMPAIGN.available_milestones(campaign_completed, ending_state_ids)
	if not endings_available.has("campaign:ending_moon"):
		_fail("Moon campaign ending did not become available after moon oath")
		return
	campaign_completed.append("campaign:ending_moon")

	var completed_choices: Array[String] = []
	for value in choice_state.get("committed_choice_ids", []) as Array:
		completed_choices.append(str(value))
	var profile: Dictionary = POSTGAME.build_profile(seed, "ending:moon_restored", completed_choices, boss_state, sequence)
	if not POSTGAME.validate_profile(profile):
		_fail("Release candidate postgame profile invalid")
		return
	var changed_world: Dictionary = POSTGAME.build_region_modifier_plan(profile, graph, 10)
	if not POSTGAME.validate_region_plan(changed_world, profile):
		_fail("Release candidate changed-world plan invalid")
		return

	var world_state := Node.new()
	world_state.set_script(WORLD_STATE_SCRIPT)
	get_root().add_child(world_state)
	if not POSTGAME.apply_to_world_state(world_state, profile):
		_fail("Release candidate could not persist postgame profile to WorldState")
		return
	if world_state.call("get_flag", "postgame:active", false) != true:
		_fail("Postgame active flag missing after release candidate victory")
		return

	var snapshot: Dictionary = {
		"completed_campaign": campaign_completed,
		"world_milestones": world_milestones,
		"boss_state": boss_state,
		"relic_plan": relic_plan,
		"relic_state": relic_state,
		"choice_state": choice_state,
		"postgame_profile": profile
	}
	var encoded: Dictionary = SAVE.encode(snapshot, sequence)
	if not SAVE.validate(encoded) or var_to_str(SAVE.decode(encoded)) != var_to_str(snapshot):
		_fail("Release candidate final state failed save roundtrip")
		return

	var host := Node.new()
	host.set_script(NETWORK)
	get_root().add_child(host)
	var network_snapshot: Dictionary = host.call("build_snapshot", campaign_completed, world_milestones, boss_state, relic_plan, relic_state, choice_state, profile, 20)
	if network_snapshot.is_empty():
		_fail("Release candidate network snapshot invalid")
		return
	if host.call("apply_authoritative_snapshot", network_snapshot, true).get("ok", false) != true:
		_fail("Release candidate authority could not register final shared state")
		return
	var package: Dictionary = host.call("build_late_join_package", 44)
	var late_join := Node.new()
	late_join.set_script(NETWORK)
	get_root().add_child(late_join)
	if late_join.call("apply_late_join_package", package).get("ok", false) != true:
		_fail("Release candidate late join reconstruction failed")
		return
	if var_to_str(late_join.call("current_snapshot")) != var_to_str(network_snapshot):
		_fail("Late join reconstructed different release candidate state")
		return

	print("ENDGAME_RELEASE_CANDIDATE_OK final=%s ending=%s regions=%d revision=%d" % [final_region, str(profile.get("ending_id", "")), (changed_world.get("assignments", []) as Array).size(), int(network_snapshot.get("revision", 0))])
	host.queue_free()
	late_join.queue_free()
	world_state.queue_free()
	quit(0)

func _fail(message: String) -> void:
	printerr("ENDGAME_RELEASE_CANDIDATE_FAILED: %s" % message)
	quit(1)
