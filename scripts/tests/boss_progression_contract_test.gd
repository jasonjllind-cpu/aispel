extends SceneTree

const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")

func _init() -> void:
	var validation: Dictionary = BOSSES.validate_contract()
	if not bool(validation.get("valid", false)):
		_fail("Boss contract invalid: %s" % str(validation.get("errors", [])))
		return
	var state: Dictionary = BOSSES.empty_state()
	var campaign: Array[String] = ["campaign:convergence"]
	var world: Array[String] = []
	if not bool(BOSSES.boss_access("hollow_king", state, campaign, world).get("allowed", false)):
		_fail("Tier-1 guardian unexpectedly locked")
		return
	if bool(BOSSES.boss_access("stormbound_titan", state, campaign, world).get("allowed", true)):
		_fail("Tier-2 guardian opened before first guardian milestone")
		return
	var unauthorized: Dictionary = BOSSES.record_authoritative_victory(state, "hollow_king", 1, 2, 1)
	if str(unauthorized.get("error", "")) != "not_authority":
		_fail("Non-authority boss victory was accepted")
		return
	var first: Dictionary = BOSSES.record_authoritative_victory(state, "hollow_king", 1, 1, 1)
	if not bool(first.get("ok", false)):
		_fail("First guardian victory rejected")
		return
	state = first.get("state", {}) as Dictionary
	if int(state.get("guardian_count", 0)) != 1 or not (state.get("milestone_ids", []) as Array).has("dungeon_milestone:one_guardian_defeated"):
		_fail("First guardian milestone missing")
		return
	var stale: Dictionary = BOSSES.record_authoritative_victory(state, "blackroot_matriarch", 1, 1, 1)
	if str(stale.get("error", "")) != "stale_sequence":
		_fail("Stale boss sequence was accepted")
		return
	var second: Dictionary = BOSSES.record_authoritative_victory(state, "stormbound_titan", 1, 1, 2)
	if not bool(second.get("ok", false)):
		_fail("Second guardian victory rejected")
		return
	state = second.get("state", {}) as Dictionary
	var third: Dictionary = BOSSES.record_authoritative_victory(state, "frostbound_wyrm", 1, 1, 3)
	if not bool(third.get("ok", false)):
		_fail("Third guardian victory rejected")
		return
	state = third.get("state", {}) as Dictionary
	if int(state.get("guardian_count", 0)) != 3 or not (state.get("milestone_ids", []) as Array).has("dungeon_milestone:three_guardians_defeated"):
		_fail("Three-guardian progression milestone missing")
		return
	var premature_state: Dictionary = BOSSES.empty_state()
	var premature: Dictionary = BOSSES.record_authoritative_victory(premature_state, "eclipsed_regent", 1, 1, 1)
	if str(premature.get("error", "")) != "guardian_gate":
		_fail("Final boss victory bypassed guardian gate")
		return
	var final_campaign: Array[String] = ["campaign:endgame_unlocked"]
	var final_world: Array[String] = ["dungeon_milestone:three_guardians_defeated"]
	if not bool(BOSSES.boss_access("eclipsed_regent", state, final_campaign, final_world).get("allowed", false)):
		_fail("Final boss remained locked after endgame prerequisites")
		return
	var final_result: Dictionary = BOSSES.record_authoritative_victory(state, "eclipsed_regent", 1, 1, 4)
	if not bool(final_result.get("ok", false)):
		_fail("Final boss victory rejected")
		return
	state = final_result.get("state", {}) as Dictionary
	if state.get("final_boss_defeated", false) != true or str(state.get("victory_state_id", "")).is_empty():
		_fail("Final victory state was not persisted")
		return
	var restored: Dictionary = BOSSES.normalize_state(state)
	if restored != state:
		_fail("Boss progression state did not survive normalization/reload")
		return
	print("BOSS_PROGRESSION_CONTRACT_OK guardians=%d victory=%s" % [int(state.get("guardian_count", 0)), str(state.get("victory_state_id", ""))])
	quit(0)

func _fail(message: String) -> void:
	printerr("BOSS_PROGRESSION_CONTRACT_FAILED: %s" % message)
	quit(1)
