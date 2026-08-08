extends SceneTree

const CONTRACT := preload("res://scripts/progression/boss_progression_contract.gd")
const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")

func _init() -> void:
	var validation: Dictionary = CONTRACT.validate_contract()
	if validation.get("valid", false) != true:
		_fail("Boss progression contract is invalid: %s" % str(validation.get("errors", [])))
		return

	var state: Dictionary = CONTRACT.empty_state()
	var campaign: Array[String] = ["campaign:convergence"]
	var world: Array[String] = []
	var first_access: Dictionary = CONTRACT.boss_access("hollow_king", state, campaign, world)
	if first_access.get("allowed", false) != true:
		_fail("Tier-1 guardian should be available after convergence")
		return

	var spoof: Dictionary = CONTRACT.record_authoritative_victory(state, "hollow_king", 1, 4, 1)
	if str(spoof.get("error", "")) != "not_authority":
		_fail("Non-authority peer was allowed to record boss victory")
		return

	var first: Dictionary = CONTRACT.record_authoritative_victory(state, "hollow_king", 1, 1, 1)
	if first.get("ok", false) != true:
		_fail("Authority could not record first guardian victory")
		return
	state = first.get("state", {}) as Dictionary
	if int(state.get("guardian_count", 0)) != 1 or not (state.get("milestone_ids", []) as Array).has("dungeon_milestone:one_guardian_defeated"):
		_fail("First guardian victory did not create one-guardian milestone")
		return

	var stale: Dictionary = CONTRACT.record_authoritative_victory(state, "blackroot_matriarch", 1, 1, 1)
	if str(stale.get("error", "")) != "stale_sequence":
		_fail("Stale victory sequence was not rejected")
		return

	var second: Dictionary = CONTRACT.record_authoritative_victory(state, "blackroot_matriarch", 1, 1, 2)
	if second.get("ok", false) != true:
		_fail("Second guardian victory was rejected")
		return
	state = second.get("state", {}) as Dictionary
	if int(state.get("guardian_count", 0)) != 2 or not (state.get("milestone_ids", []) as Array).has("dungeon_milestone:two_guardians_defeated"):
		_fail("Second guardian victory did not create two-guardian milestone")
		return

	var locked_tier3: Dictionary = CONTRACT.boss_access("frostbound_wyrm", first.get("state", {}), campaign, world)
	if locked_tier3.get("allowed", true) == true:
		_fail("Tier-3 guardian opened before two guardian victories")
		return
	var tier3_access: Dictionary = CONTRACT.boss_access("frostbound_wyrm", state, campaign, world)
	if tier3_access.get("allowed", false) != true:
		_fail("Tier-3 guardian remained locked after two guardian victories")
		return

	var third: Dictionary = CONTRACT.record_authoritative_victory(state, "frostbound_wyrm", 1, 1, 3)
	if third.get("ok", false) != true:
		_fail("Third guardian victory was rejected")
		return
	state = third.get("state", {}) as Dictionary
	if int(state.get("guardian_count", 0)) != 3 or not (state.get("milestone_ids", []) as Array).has("dungeon_milestone:three_guardians_defeated"):
		_fail("Third guardian victory did not create three-guardian milestone")
		return

	var final_locked: Dictionary = CONTRACT.boss_access("eclipsed_regent", state, campaign, world)
	if final_locked.get("allowed", true) == true:
		_fail("Final boss opened before campaign endgame unlock")
		return
	var endgame_campaign: Array[String] = ["campaign:convergence", "campaign:endgame_unlocked"]
	var final_access: Dictionary = CONTRACT.boss_access("eclipsed_regent", state, endgame_campaign, world)
	if final_access.get("allowed", false) != true:
		_fail("Final boss remained locked after valid endgame state")
		return

	var final_result: Dictionary = CONTRACT.record_authoritative_victory(state, "eclipsed_regent", 1, 1, 4)
	if final_result.get("ok", false) != true:
		_fail("Final authoritative victory was rejected")
		return
	state = final_result.get("state", {}) as Dictionary
	if state.get("final_boss_defeated", false) != true or not str(state.get("victory_state_id", "")).begins_with("victory:endgame:eclipsed_regent:"):
		_fail("Final victory state contract was not recorded")
		return

	var world_state := Node.new()
	world_state.set_script(WORLD_STATE_SCRIPT)
	get_root().add_child(world_state)
	if not CONTRACT.apply_result_to_world_state(world_state, final_result):
		_fail("Victory result could not be applied to WorldState")
		return
	var persisted: Dictionary = world_state.call("get_entity_state", CONTRACT.STATE_ID)
	if persisted.get("final_boss_defeated", false) != true:
		_fail("WorldState did not persist final victory state")
		return
	if world_state.call("get_flag", "boss_milestone:final_victory", false) != true:
		_fail("Final boss victory flag was not persisted")
		return

	print("BOSS_PROGRESSION_CONTRACT_OK guardians=%d victory=%s" % [int(state.get("guardian_count", 0)), str(state.get("victory_state_id", ""))])
	world_state.queue_free()
	quit(0)

func _fail(message: String) -> void:
	printerr("BOSS_PROGRESSION_CONTRACT_FAILED: %s" % message)
	quit(1)
