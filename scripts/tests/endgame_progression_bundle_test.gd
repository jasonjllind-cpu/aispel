extends SceneTree

const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const BUNDLE := preload("res://scripts/progression/endgame_progression_bundle.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")

func _init() -> void:
	var generator: RefCounted = GRAPH.new()
	generator.call("configure", 89182601)
	var graph: Dictionary = generator.call("generate_graph", 96) as Dictionary
	var state: Dictionary = BUNDLE.create(graph)
	if state.is_empty() or not BUNDLE.validate(state):
		_fail("Could not create valid unified endgame bundle")
		return

	var initial_revision: int = int(state.get("revision", -1))
	state = BUNDLE.complete_campaign(state, "campaign:frontier_oath", ["quest:frontier_oath:frontier_crypt"])
	if not (state.get("completed_campaign", []) as Array).has("campaign:frontier_oath"):
		_fail("Bundle could not complete frontier oath")
		return
	state = BUNDLE.complete_campaign(state, "campaign:blackwood_pact", ["quest:blackwood_pact:blackwood_root_crypt"])
	state = BUNDLE.add_world_milestone(state, "world_milestone:windscar_beacon")
	state = BUNDLE.complete_campaign(state, "campaign:convergence")
	if not (state.get("completed_campaign", []) as Array).has("campaign:convergence"):
		_fail("Bundle could not reach campaign convergence")
		return

	var relic_plan: Dictionary = state.get("relic_plan", {}) as Dictionary
	for objective_id in RELICS.objective_ids():
		var assignment: Dictionary = RELICS.assignment_for_objective(relic_plan, objective_id)
		var previous_sequence: int = int(state.get("sequence", -1))
		state = BUNDLE.acquire_relic(state, objective_id, str(assignment.get("region_id", "")))
		if int(state.get("sequence", -1)) <= previous_sequence:
			_fail("Bundle relic acquisition did not advance sequence: %s" % objective_id)
			return

	for boss_id in ["hollow_king", "stormbound_titan", "frostbound_wyrm"]:
		var previous_count: int = int((state.get("boss_state", {}) as Dictionary).get("guardian_count", 0))
		state = BUNDLE.record_boss_victory(state, boss_id, 1, 1)
		var current_count: int = int((state.get("boss_state", {}) as Dictionary).get("guardian_count", 0))
		if current_count != previous_count + 1:
			_fail("Bundle guardian progression failed: %s" % boss_id)
			return
	if not (state.get("world_milestones", []) as Array).has("dungeon_milestone:three_guardians_defeated"):
		_fail("Bundle did not propagate three-guardian milestone")
		return

	state = BUNDLE.complete_campaign(state, "campaign:endgame_unlocked")
	if not (state.get("completed_campaign", []) as Array).has("campaign:endgame_unlocked"):
		_fail("Bundle could not complete endgame unlock")
		return
	var final_region: String = ""
	for value in (state.get("access_plan", {}) as Dictionary).get("assignments", []) as Array:
		if value is Dictionary and str((value as Dictionary).get("role", "")) == "final_reach":
			final_region = str((value as Dictionary).get("region_id", ""))
			break
	if final_region.is_empty() or BUNDLE.region_access(state, final_region).get("allowed", false) != true:
		_fail("Bundle final region remained locked after endgame unlock")
		return

	state = BUNDLE.record_boss_victory(state, "eclipsed_regent", 1, 1)
	if (state.get("boss_state", {}) as Dictionary).get("final_boss_defeated", false) != true:
		_fail("Bundle final boss victory did not persist")
		return
	state = BUNDLE.commit_choice(state, "choice:moon_oath")
	state = BUNDLE.finish_ending(state, "moon")
	var profile: Dictionary = state.get("postgame_profile", {}) as Dictionary
	if profile.is_empty() or str(profile.get("ending_id", "")) != "ending:moon_restored":
		_fail("Bundle did not produce moon postgame profile")
		return
	if not (state.get("completed_campaign", []) as Array).has("campaign:ending_moon"):
		_fail("Bundle did not persist ending campaign milestone")
		return

	var envelope: Dictionary = BUNDLE.save_envelope(state)
	if envelope.is_empty():
		_fail("Bundle could not create save envelope")
		return
	var restored: Dictionary = BUNDLE.restore_envelope(envelope, graph)
	if restored.is_empty() or not BUNDLE.validate(restored):
		_fail("Bundle could not restore save envelope")
		return
	var network_snapshot: Dictionary = BUNDLE.network_snapshot(state)
	if network_snapshot.is_empty():
		_fail("Bundle could not create network snapshot")
		return
	var restored_network: Dictionary = BUNDLE.restore_network_snapshot(network_snapshot, graph)
	if restored_network.is_empty() or not BUNDLE.validate(restored_network):
		_fail("Bundle could not reconstruct network snapshot")
		return
	if str((restored_network.get("postgame_profile", {}) as Dictionary).get("profile_id", "")) != str(profile.get("profile_id", "")):
		_fail("Network restore changed postgame profile identity")
		return
	if int(state.get("revision", 0)) <= initial_revision:
		_fail("Bundle revision did not advance across full campaign")
		return

	print("ENDGAME_PROGRESSION_BUNDLE_OK revision=%d sequence=%d ending=%s" % [int(state.get("revision", 0)), int(state.get("sequence", 0)), str(profile.get("ending_id", ""))])
	quit(0)

func _fail(message: String) -> void:
	printerr("ENDGAME_PROGRESSION_BUNDLE_FAILED: %s" % message)
	quit(1)
