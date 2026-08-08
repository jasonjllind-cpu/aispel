extends SceneTree

const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const PROFILE := preload("res://scripts/progression/postgame_world_profile.gd")
const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")

func _init() -> void:
	var boss_state: Dictionary = {"guardian_victory_ids": ["boss_victory:g1", "boss_victory:g2", "boss_victory:g3"]}
	var choices: Array[String] = ["choice:roadfolk_covenant", "choice:blackwood_mercy"]
	var moon: Dictionary = PROFILE.build_profile(85082601, "ending:moon_restored", choices, boss_state, 4)
	if not PROFILE.validate_profile(moon):
		_fail("Moon postgame profile is invalid")
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
