extends SceneTree

const PROGRESSION := preload("res://scripts/progression/player_progression_state.gd")

func _init() -> void:
	if not _validate_curve():
		return
	if not _validate_progression_and_rewards():
		return
	if not _validate_round_trip():
		return
	if not _validate_rejection_paths():
		return
	print("PLAYER_PROGRESSION_STATE_OK max_level=%d" % PROGRESSION.MAX_LEVEL)
	quit(0)

func _validate_curve() -> bool:
	var state: RefCounted = PROGRESSION.new()
	var previous_cost: int = 0
	var previous_total: int = 0
	for target_level in range(2, PROGRESSION.MAX_LEVEL + 1):
		var cost: int = state.call("xp_required_for_level", target_level)
		var total: int = state.call("total_xp_required_for_level", target_level)
		if cost <= previous_cost or total <= previous_total:
			return _fail("XP curve is not strictly increasing at level %d" % target_level)
		previous_cost = cost
		previous_total = total
	return true

func _validate_progression_and_rewards() -> bool:
	var state: RefCounted = PROGRESSION.new()
	state.call("configure", "player:test:progression")
	var to_level_ten: int = state.call("total_xp_required_for_level", 10)
	var result: Dictionary = state.call("grant_xp", to_level_ten, "quest:test")
	if int(result.get("level", 0)) != 10:
		return _fail("Expected progression to reach level 10")
	var rewards: Array = result.get("unlocked_rewards", []) as Array
	for required_reward in ["reward:equipment:uncommon", "reward:magic:first_spell_slot", "reward:equipment:rare", "reward:magic:second_spell_slot", "reward:quest:frontier_chain"]:
		if not rewards.has(required_reward):
			return _fail("Missing milestone reward %s" % required_reward)
	if int(result.get("unspent_attribute_points", 0)) != 11:
		return _fail("Attribute-point rewards do not match the level curve")
	if not bool(state.call("spend_attribute_points", 4)):
		return _fail("Valid attribute-point spend was rejected")
	if bool(state.call("spend_attribute_points", 999)):
		return _fail("Invalid attribute-point spend was accepted")
	return true

func _validate_round_trip() -> bool:
	var state: RefCounted = PROGRESSION.new()
	state.call("configure", "player:test:roundtrip")
	state.call("grant_xp", int(state.call("total_xp_required_for_level", 12)) + 37, "dungeon:test")
	state.call("spend_attribute_points", 3)
	var snapshot: Dictionary = state.call("to_dict")
	var restored: RefCounted = PROGRESSION.new()
	if not bool(restored.call("load_dict", snapshot)):
		return _fail("Progression snapshot failed to restore")
	if var_to_str(restored.call("to_dict")) != var_to_str(snapshot):
		return _fail("Progression state changed after save/load round trip")
	return true

func _validate_rejection_paths() -> bool:
	var state: RefCounted = PROGRESSION.new()
	if bool(state.call("load_dict", {"format_version": 99})):
		return _fail("Unsupported progression format was accepted")
	var invalid: Dictionary = {
		"format_version": PROGRESSION.FORMAT_VERSION,
		"player_id": "player:test",
		"level": 3,
		"current_xp": 999999,
		"lifetime_xp": 999999,
		"unspent_attribute_points": 0,
		"unlocked_rewards": []
	}
	if bool(state.call("load_dict", invalid)):
		return _fail("Invalid XP remainder was accepted")
	var capped: RefCounted = PROGRESSION.new()
	capped.call("grant_xp", 100000000, "test:max")
	var capped_snapshot: Dictionary = capped.call("to_dict")
	if int(capped_snapshot.get("level", 0)) != PROGRESSION.MAX_LEVEL or int(capped_snapshot.get("current_xp", -1)) != 0:
		return _fail("Max-level progression is not clamped")
	return true

func _fail(message: String) -> bool:
	printerr("PLAYER_PROGRESSION_STATE_FAILED: %s" % message)
	quit(1)
	return false
