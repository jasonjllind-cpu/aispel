extends SceneTree

const BOSSES := preload("res://scripts/progression/boss_progression_state.gd")

func _init() -> void:
	var state: Dictionary = BOSSES.create_state("world:test")
	if not BOSSES.validate_state(state):
		_fail("Fresh boss progression state is invalid")
		return

	var guardian_contracts: Array[Dictionary] = []
	for index in range(3):
		var contract: Dictionary = BOSSES.build_guardian_contract("region:test:%d" % index, "dungeon:test:%d" % index, index, "blackwood")
		if not BOSSES.validate_contract(contract):
			_fail("Guardian contract %d is invalid" % index)
			return
		guardian_contracts.append(contract)

	var unauthorized: Dictionary = BOSSES.apply_authoritative_victory(state, guardian_contracts[0], BOSSES.build_victory_command(guardian_contracts[0], 1, 7), false, 7)
	if str(unauthorized.get("reason", "")) != "not_authority":
		_fail("Non-authority victory mutation was accepted")
		return
	var stale: Dictionary = BOSSES.apply_authoritative_victory(state, guardian_contracts[0], BOSSES.build_victory_command(guardian_contracts[0], 1, 6), true, 7)
	if str(stale.get("reason", "")) != "stale_authority_epoch":
		_fail("Stale authority epoch was accepted")
		return

	for index in range(3):
		var command: Dictionary = BOSSES.build_victory_command(guardian_contracts[index], index + 10, 7)
		var result: Dictionary = BOSSES.apply_authoritative_victory(state, guardian_contracts[index], command, true, 7)
		if not bool(result.get("accepted", false)):
			_fail("Guardian victory %d was rejected: %s" % [index, str(result.get("reason", ""))])
			return
		state = result.get("state", {}) as Dictionary
		var expected_milestone: String = ["dungeon_milestone:one_guardian_defeated", "dungeon_milestone:two_guardians_defeated", "dungeon_milestone:three_guardians_defeated"][index]
		if not (state.get("world_milestones", []) as Array).has(expected_milestone):
			_fail("Guardian victory did not emit %s" % expected_milestone)
			return

	if (state.get("guardian_victory_ids", []) as Array).size() != 3 or int(state.get("revision", 0)) != 3:
		_fail("Guardian progression count/revision is incorrect")
		return
	var duplicate: Dictionary = BOSSES.apply_authoritative_victory(state, guardian_contracts[2], BOSSES.build_victory_command(guardian_contracts[2], 20, 7), true, 7)
	if str(duplicate.get("reason", "")) != "already_defeated":
		_fail("Duplicate boss victory was not idempotently rejected")
		return

	var fresh_state: Dictionary = BOSSES.create_state("world:fresh")
	var final_contract: Dictionary = BOSSES.build_final_boss_contract("region:final", "campaign:endgame_unlocked", "moon")
	if not BOSSES.validate_contract(final_contract):
		_fail("Final boss contract is invalid")
		return
	var final_command: Dictionary = BOSSES.build_victory_command(final_contract, 99, 7)
	var premature: Dictionary = BOSSES.apply_authoritative_victory(fresh_state, final_contract, final_command, true, 7)
	if str(premature.get("reason", "")) != "guardian_gate":
		_fail("Final boss victory bypassed three-guardian gate")
		return
	var final_result: Dictionary = BOSSES.apply_authoritative_victory(state, final_contract, final_command, true, 7)
	if not bool(final_result.get("accepted", false)):
		_fail("Final boss victory was rejected after guardian completion")
		return
	state = final_result.get("state", {}) as Dictionary
	if not (state.get("world_milestones", []) as Array).has("boss_milestone:final_moon_defeated"):
		_fail("Final boss victory did not emit ending milestone")
		return
	if int(state.get("revision", 0)) != 4 or not BOSSES.validate_state(state):
		_fail("Final authoritative boss state is invalid")
		return

	print("BOSS_PROGRESSION_STATE_OK guardians=3 revision=%d" % int(state.get("revision", 0)))
	quit(0)

func _fail(message: String) -> void:
	printerr("BOSS_PROGRESSION_STATE_FAILED: %s" % message)
	quit(1)
