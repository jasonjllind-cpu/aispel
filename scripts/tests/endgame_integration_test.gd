extends SceneTree

const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const BUNDLE := preload("res://scripts/progression/endgame_progression_bundle.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")
const POSTGAME := preload("res://scripts/progression/postgame_world_profile.gd")
const NETWORK_SCRIPT := preload("res://scripts/network/network_endgame_replicator.gd")

func _init() -> void:
	var generator: RefCounted = GRAPH.new()
	generator.call("configure", 89082601)
	var graph: Dictionary = generator.call("generate_graph", 80) as Dictionary
	var state: Dictionary = BUNDLE.create(graph)
	if state.is_empty() or not BUNDLE.validate(state):
		_fail("Could not create unified endgame progression bundle")
		return

	var final_region: String = ""
	for assignment_value in (state.get("access_plan", {}) as Dictionary).get("assignments", []) as Array:
		if assignment_value is Dictionary and str((assignment_value as Dictionary).get("role", "")) == "final_reach":
			final_region = str((assignment_value as Dictionary).get("region_id", ""))
			break
	if final_region.is_empty():
		_fail("Unified bundle has no final region")
		return
	if BUNDLE.region_access(state, final_region).get("allowed", true) == true:
		_fail("Final region started unlocked")
		return

	state = BUNDLE.complete_campaign(state, "campaign:frontier_oath", ["quest:frontier_oath:frontier_crypt"])
	state = BUNDLE.complete_campaign(state, "campaign:blackwood_pact", ["quest:blackwood_pact:blackwood_root_crypt"])
	state = BUNDLE.add_world_milestone(state, "world_milestone:windscar_beacon")
	state = BUNDLE.complete_campaign(state, "campaign:convergence")
	if not (state.get("completed_campaign", []) as Array).has("campaign:convergence"):
		_fail("Campaign chapters did not reach convergence")
		return

	for boss_id in ["hollow_king", "blackroot_matriarch", "stormbound_titan"]:
		var before: int = int((state.get("boss_state", {}) as Dictionary).get("guardian_count", 0))
		state = BUNDLE.record_boss_victory(state, boss_id, 1, 1)
		var after: int = int((state.get("boss_state", {}) as Dictionary).get("guardian_count", 0))
		if after != before + 1:
			_fail("Guardian progression failed for %s" % boss_id)
			return
	if not (state.get("world_milestones", []) as Array).has("dungeon_milestone:three_guardians_defeated"):
		_fail("Three-guardian campaign gate was not raised")
		return
	state = BUNDLE.complete_campaign(state, "campaign:endgame_unlocked")
	if not (state.get("completed_campaign", []) as Array).has("campaign:endgame_unlocked"):
		_fail("Endgame campaign milestone did not unlock")
		return
	if BUNDLE.region_access(state, final_region).get("allowed", false) != true:
		_fail("Final region remained locked after campaign and guardian requirements")
		return

	var before_final: Dictionary = state.duplicate(true)
	state = BUNDLE.record_boss_victory(state, "eclipsed_regent", 1, 1)
	if (state.get("boss_state", {}) as Dictionary).get("final_boss_defeated", false) == true:
		_fail("Final boss could be defeated before recovering required relics")
		return
	if var_to_str(state) != var_to_str(before_final):
		_fail("Rejected final boss attempt mutated progression state")
		return

	for objective_id in RELICS.objective_ids():
		var assignment: Dictionary = RELICS.assignment_for_objective(state.get("relic_plan", {}) as Dictionary, objective_id)
		state = BUNDLE.acquire_relic(state, objective_id, str(assignment.get("region_id", "")))
	if not RELICS.endgame_ready(state.get("relic_state", {}) as Dictionary, state.get("relic_plan", {}) as Dictionary):
		_fail("Relic recovery did not satisfy final access objective")
		return

	state = BUNDLE.commit_choice(state, "choice:moon_oath")
	state = BUNDLE.record_boss_victory(state, "eclipsed_regent", 1, 1)
	if (state.get("boss_state", {}) as Dictionary).get("final_boss_defeated", false) != true:
		_fail("Final boss victory failed after all authoritative gates")
		return
	state = BUNDLE.finish_ending(state, "moon")
	var profile: Dictionary = state.get("postgame_profile", {}) as Dictionary
	if not POSTGAME.validate_profile(profile) or str(profile.get("ending_id", "")) != "ending:moon_restored":
		_fail("Completed campaign did not create Moon postgame profile")
		return
	if not (state.get("completed_campaign", []) as Array).has("campaign:ending_moon"):
		_fail("Moon ending campaign milestone was not completed")
		return

	var network_snapshot: Dictionary = BUNDLE.network_snapshot(state)
	if network_snapshot.is_empty():
		_fail("Unified endgame state could not build co-op snapshot")
		return
	var host := Node.new()
	host.set_script(NETWORK_SCRIPT)
	get_root().add_child(host)
	if (host.call("apply_authoritative_snapshot", network_snapshot, true) as Dictionary).get("ok", false) != true:
		_fail("Host could not register final shared endgame snapshot")
		return
	var package: Dictionary = host.call("build_late_join_package", 44)
	var client := Node.new()
	client.set_script(NETWORK_SCRIPT)
	get_root().add_child(client)
	if (client.call("apply_late_join_package", package) as Dictionary).get("ok", false) != true:
		_fail("Late-join client could not reconstruct completed campaign")
		return
	if var_to_str(client.call("current_snapshot")) != var_to_str(network_snapshot):
		_fail("Late-join state differs from authoritative completed campaign")
		return

	var envelope: Dictionary = BUNDLE.save_envelope(state)
	var restored: Dictionary = BUNDLE.restore_envelope(envelope, graph)
	if restored.is_empty() or not BUNDLE.validate(restored):
		_fail("Completed campaign could not survive save/reload")
		return
	if var_to_str(restored.get("postgame_profile", {})) != var_to_str(state.get("postgame_profile", {})):
		_fail("Save/reload lost postgame state")
		return
	if int(restored.get("sequence", 0)) < int(state.get("sequence", 0)):
		_fail("Save/reload rewound authoritative event sequence")
		return

	var other_generator: RefCounted = GRAPH.new()
	other_generator.call("configure", 89082602)
	var other_graph: Dictionary = other_generator.call("generate_graph", 80) as Dictionary
	if not BUNDLE.restore_envelope(envelope, other_graph).is_empty():
		_fail("Save from one deterministic world was accepted by another seed")
		return

	print("ENDGAME_INTEGRATION_OK ending=%s revision=%d sequence=%d" % [str(profile.get("ending_id", "")), int(state.get("revision", 0)), int(state.get("sequence", 0))])
	host.queue_free()
	client.queue_free()
	quit(0)

func _fail(message: String) -> void:
	printerr("ENDGAME_INTEGRATION_FAILED: %s" % message)
	quit(1)
