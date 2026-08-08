extends SceneTree

const CONSEQUENCES := preload("res://scripts/progression/endgame_choice_consequences.gd")

func _init() -> void:
	var state: Dictionary = CONSEQUENCES.create_state("world:test")
	if not CONSEQUENCES.validate_state(state):
		_fail("Fresh choice consequence state is invalid")
		return

	var neutral_routes: Array[String] = CONSEQUENCES.compatible_ending_routes(state)
	if not neutral_routes.is_empty():
		_fail("Ending routes opened without oath, mastery or trusted faction")
		return

	var roadfolk: Dictionary = CONSEQUENCES.apply_choice(state, "choice:roadfolk_covenant", 1)
	if roadfolk.get("accepted", false) != true:
		_fail("Compatible neutral choice was rejected")
		return
	state = roadfolk.get("state", {}) as Dictionary
	if CONSEQUENCES.effective_reputation(state, "roadfolk", 10) != 30:
		_fail("Faction consequence delta was not applied")
		return

	var moon: Dictionary = CONSEQUENCES.apply_choice(state, "choice:moon_oath", 2)
	if moon.get("accepted", false) != true:
		_fail("Moon oath was rejected")
		return
	state = moon.get("state", {}) as Dictionary
	if CONSEQUENCES.ending_route_decision("moon", state).get("allowed", false) != true:
		_fail("Moon oath did not unlock moon ending route")
		return
	if CONSEQUENCES.ending_route_decision("veil", state).get("allowed", true) == true:
		_fail("Opposing veil ending remained compatible with moon oath")
		return
	var conflict: Dictionary = CONSEQUENCES.apply_choice(state, "choice:veil_bargain", 3)
	if str(conflict.get("reason", "")) != "exclusive_choice_conflict":
		_fail("Mutually exclusive ending oath was not rejected")
		return

	var mastery_state: Dictionary = CONSEQUENCES.create_state("world:mastery")
	var mastery: Array[String] = ["magic_mastery:veil"]
	if CONSEQUENCES.ending_route_decision("veil", mastery_state, {}, mastery).get("allowed", false) != true:
		_fail("Veil mastery did not provide compatible veil ending route")
		return
	var reputation: Dictionary = {"moon_wardens": 45}
	if CONSEQUENCES.ending_route_decision("moon", mastery_state, reputation, []).get("allowed", false) != true:
		_fail("Trusted Moon Wardens reputation did not provide moon route")
		return

	var restored: Dictionary = state.duplicate(true)
	if not CONSEQUENCES.validate_state(restored):
		_fail("Choice consequence state did not survive dictionary reload")
		return
	if not (restored.get("world_flags", []) as Array).has("choice:moon_oath"):
		_fail("Ending choice world flag was not persisted")
		return

	print("ENDGAME_CHOICE_CONSEQUENCES_OK revision=%d routes=%s" % [int(state.get("revision", 0)), str(CONSEQUENCES.compatible_ending_routes(state))])
	quit(0)

func _fail(message: String) -> void:
	printerr("ENDGAME_CHOICE_CONSEQUENCES_FAILED: %s" % message)
	quit(1)
