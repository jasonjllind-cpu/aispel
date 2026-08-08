extends SceneTree

const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const PROFILE := preload("res://scripts/progression/postgame_world_profile.gd")
const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")
const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")

func _init() -> void:
	var boss_state: Dictionary = BOSSES.empty_state()
	var guardian_ids: Array[String] = ["hollow_king", "stormbound_titan", "frostbound_wyrm"]
	var sequence: int = 1
	for boss_id in guardian_ids:
		var result: Dictionary = BOSSES.record_authoritative_victory(boss_state, boss_id, 1, 1, sequence)
		if result.get("ok", false) != true:
			_fail("Could not build canonical three-guardian fixture: %s" % str(result.get("error", "")))
			return
		boss_state = result.get("state", {}) as Dictionary
		sequence += 1
	if int(boss_state.get("guardian_count", 0)) != 3:
		_fail("Canonical boss fixture did not reach three guardians")
		return

	var choices: Array[String] = ["choice:roadfolk_covenant", "choice:blackwood_mercy"]
	var moon: Dictionary = PROFILE.build_profile(85082601, "ending:moon_restored", choices, boss_state, 4)
	if not PROFILE.validate_profile(moon):
		_fail("Moon postgame profile is invalid")
		return
	if int(moon.get("guardian_count", 0)) != 3 or not (moon.get("modifier_ids", []) as Array).has("world_modifier:guardian_echoes"):
		_fail("Postgame profile did not consume canonical boss guardian state")
		return
	var moon_repeat: Dictionary = PROFILE.build_profile(85082601, "ending:moon_restored", choices, boss_state, 4)
	if var_to_str(moon) != var_to_str(moon_repeat):
		_fail("Same completed world produced different postgame profile")
		return
	var veil: Dictionary = PROFILE.build_profile(85082601, "ending:veil_bound", choices, boss_state, 4)
	if not PROFILE.validate_profile(veil) or var_to_str(veil.get("modifier_ids", [])) == var_to_str(moon.get("modifier_ids", [])):
		_fail("Different endings did not produce distinct valid world modifiers")
		return

	var generator: RefCounted = GRAPH.new()
	generator.call("configure", 85082601)
	var graph: Dictionary = generator.call("generate_graph", 72) as Dictionary
	var plan_a: Dictionary = PROFILE.build_region_modifier_plan(moon, graph, 9)
	var plan_b: Dictionary = PROFILE.build_region_modifier_plan(moon, graph, 9)
	if not PROFILE.validate_region_plan(plan_a, moon):
		_fail("Postgame region modifier plan is invalid")
		return
	if var_to_str(plan_a) != var_to_str(plan_b):
		_fail("Postgame changed-world region plan is not deterministic")
		return
	if (plan_a.get("assignments", []) as Array).size() != 9:
		_fail("Postgame region modifier plan did not respect requested coverage")
		return

	var world_state := Node.new()
	world_state.set_script(WORLD_STATE_SCRIPT)
	get_root().add_child(world_state)
	if not PROFILE.apply_to_world_state(world_state, moon):
		_fail("Postgame profile could not be persisted into WorldState")
		return
	var restored: Dictionary = world_state.call("get_entity_state", PROFILE.STATE_ID)
	if not PROFILE.validate_profile(restored):
		_fail("Persisted postgame profile did not survive WorldState roundtrip")
		return
	if world_state.call("get_flag", "postgame:active", false) != true or world_state.call("get_flag", "ending:moon_restored", false) != true:
		_fail("Postgame world flags were not applied")
		return

	print("POSTGAME_WORLD_PROFILE_OK profile=%s regions=%d" % [str(moon.get("profile_id", "")), (plan_a.get("assignments", []) as Array).size()])
	world_state.queue_free()
	quit(0)

func _fail(message: String) -> void:
	printerr("POSTGAME_WORLD_PROFILE_FAILED: %s" % message)
	quit(1)
