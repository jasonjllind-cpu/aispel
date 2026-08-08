extends SceneTree

const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")
const QUESTS := preload("res://scripts/progression/quest_chain_catalog.gd")

func _init() -> void:
	if not _validate_initial_state():
		return
	if not _validate_quest_unlocks():
		return
	if not _validate_lore_mastery():
		return
	if not _validate_rank_unlocks():
		return
	print("MAGIC_SCHOOL_PROGRESSION_OK schools=%d" % MAGIC.get_school_ids().size())
	quit(0)

func _validate_initial_state() -> bool:
	var state: Dictionary = MAGIC.create_state("player:test")
	if not MAGIC.validate_state(state):
		return _fail("Fresh magic-school state failed validation")
	if MAGIC.get_school_ids().size() != 6:
		return _fail("Magic-school progression does not cover all spell schools")
	if not (state.get("unlocked_spells", []) as Array).is_empty():
		return _fail("Fresh magic-school state should not unlock spells")
	return true

func _validate_quest_unlocks() -> bool:
	var state: Dictionary = MAGIC.create_state("player:test")
	var event: Dictionary = QUESTS.build_completion_event("frontier_oath", "frontier:moon_shrine", 1)
	state = MAGIC.apply_quest_rewards(state, str(event.get("progression_id", "")), event.get("reward_ids", []) as Array)
	if not (state.get("unlocked_spells", []) as Array).has("moon_bolt"):
		return _fail("Quest spell reward did not unlock Moon Bolt")
	var moon_state: Dictionary = (state.get("schools", {}) as Dictionary).get("moon", {}) as Dictionary
	if int(moon_state.get("mastery_xp", 0)) != 90:
		return _fail("Quest spell discovery did not grant moon mastery")
	var repeated: Dictionary = MAGIC.apply_quest_rewards(state, str(event.get("progression_id", "")), event.get("reward_ids", []) as Array)
	if var_to_str(repeated) != var_to_str(state):
		return _fail("Quest magic discovery is not idempotent")
	if not MAGIC.available_spells(state, 3).has("moon_bolt"):
		return _fail("Unlocked spell is unavailable at its player-level requirement")
	if MAGIC.available_spells(state, 2).has("moon_bolt"):
		return _fail("Player-level gate was bypassed for an unlocked spell")
	return true

func _validate_lore_mastery() -> bool:
	var state: Dictionary = MAGIC.create_state("player:test")
	state = MAGIC.apply_lore_discovery(state, "witchfire_litany")
	var ember: Dictionary = (state.get("schools", {}) as Dictionary).get("ember", {}) as Dictionary
	if int(ember.get("mastery_xp", 0)) != 85:
		return _fail("Shrine lore discovery granted the wrong mastery amount")
	if not (state.get("discoveries", []) as Array).has("magic_discovery:lore:witchfire_litany"):
		return _fail("Lore discovery stable ID was not persisted")
	var repeated: Dictionary = MAGIC.apply_lore_discovery(state, "witchfire_litany")
	if var_to_str(repeated) != var_to_str(state):
		return _fail("Lore discovery is not idempotent")
	var unknown: Dictionary = MAGIC.apply_lore_discovery(state, "not_real")
	if var_to_str(unknown) != var_to_str(state):
		return _fail("Unknown lore record modified magic progression")
	return true

func _validate_rank_unlocks() -> bool:
	var state: Dictionary = MAGIC.create_state("player:test")
	state = MAGIC.grant_mastery(state, "frost", 430, "magic_discovery:test:frost")
	var frost: Dictionary = (state.get("schools", {}) as Dictionary).get("frost", {}) as Dictionary
	if int(frost.get("rank", -1)) != 2:
		return _fail("Frost mastery did not reach expected rank")
	var unlocked: Array = state.get("unlocked_spells", []) as Array
	if not unlocked.has("frost_lance") or not unlocked.has("ice_skin"):
		return _fail("School rank did not unlock its eligible spell set")
	if MAGIC.rank_for_xp("missing", 999) != -1:
		return _fail("Unknown school returned a valid rank")
	if not MAGIC.validate_state(state):
		return _fail("Advanced magic-school state failed validation")
	return true

func _fail(message: String) -> bool:
	printerr("MAGIC_SCHOOL_PROGRESSION_FAILED: %s" % message)
	quit(1)
	return false
