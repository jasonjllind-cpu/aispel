extends RefCounted
class_name PlayerProgressionBundle

const FORMAT_VERSION: int = 1
const PLAYER_PROGRESSION := preload("res://scripts/progression/player_progression_state.gd")
const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")
const BUILD := preload("res://scripts/progression/character_build_model.gd")
const EQUIPMENT := preload("res://scripts/equipment/equipment_progression_catalog.gd")
const SAVE_CODEC := preload("res://scripts/progression/progression_save_codec.gd")
const NETWORK_REPLICATOR := preload("res://scripts/network/network_progression_replicator.gd")

static func create(player_id: String) -> Dictionary:
	var stable_id: String = player_id if not player_id.is_empty() else "player:local"
	var progression_state: RefCounted = PLAYER_PROGRESSION.new()
	progression_state.call("configure", stable_id)
	return {
		"format_version": FORMAT_VERSION,
		"player_id": stable_id,
		"revision": 0,
		"progression": progression_state.call("to_dict") as Dictionary,
		"magic": MAGIC.create_state(stable_id),
		"build": BUILD.create_build(stable_id),
		"completed_quests": [],
		"applied_reward_ids": []
	}

static func validate(bundle: Dictionary) -> bool:
	if int(bundle.get("format_version", -1)) != FORMAT_VERSION:
		return false
	var player_id: String = str(bundle.get("player_id", ""))
	if player_id.is_empty() or int(bundle.get("revision", -1)) < 0:
		return false
	var progression_value: Variant = bundle.get("progression", {})
	var magic_value: Variant = bundle.get("magic", {})
	var build_value: Variant = bundle.get("build", {})
	var quests_value: Variant = bundle.get("completed_quests", [])
	var rewards_value: Variant = bundle.get("applied_reward_ids", [])
	if not progression_value is Dictionary or not magic_value is Dictionary or not build_value is Dictionary or not quests_value is Array or not rewards_value is Array:
		return false
	var progression_state: RefCounted = PLAYER_PROGRESSION.new()
	if not bool(progression_state.call("load_dict", progression_value as Dictionary)):
		return false
	if str((progression_value as Dictionary).get("player_id", "")) != player_id:
		return false
	if not MAGIC.validate_state(magic_value as Dictionary) or str((magic_value as Dictionary).get("player_id", "")) != player_id:
		return false
	if not BUILD.validate_build(build_value as Dictionary) or str((build_value as Dictionary).get("player_id", "")) != player_id:
		return false
	return _validate_stable_ids(quests_value as Array, "quest:") and _validate_stable_ids(rewards_value as Array, "progression_reward:")

static func player_level(bundle: Dictionary) -> int:
	return int((bundle.get("progression", {}) as Dictionary).get("level", 1)) if validate(bundle) else 0

static func apply_progression_reward(bundle: Dictionary, reward: Dictionary) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result):
		return result
	var reward_id: String = str(reward.get("reward_id", ""))
	if not reward_id.begins_with("progression_reward:"):
		return result
	var applied: Array = result.get("applied_reward_ids", []) as Array
	if applied.has(reward_id):
		return result
	var progression_state: RefCounted = PLAYER_PROGRESSION.new()
	if not bool(progression_state.call("load_dict", result.get("progression", {}) as Dictionary)):
		return result
	var xp: int = maxi(0, int(reward.get("xp", 0)))
	if xp > 0:
		progression_state.call("grant_xp", xp, reward_id)
	result["progression"] = progression_state.call("to_dict") as Dictionary
	var mastery_xp: int = maxi(0, int(reward.get("mastery_xp", 0)))
	var school_id: String = str(reward.get("school_id", ""))
	if mastery_xp > 0 and not school_id.is_empty():
		result["magic"] = MAGIC.grant_mastery(result.get("magic", {}) as Dictionary, school_id, mastery_xp, "magic_discovery:reward:%s" % reward_id.trim_prefix("progression_reward:"))
	applied.append(reward_id)
	applied.sort()
	result["applied_reward_ids"] = applied
	_increment_revision(result)
	return result

static func apply_quest_completion(bundle: Dictionary, event: Dictionary) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result):
		return result
	var progression_id: String = str(event.get("progression_id", ""))
	if not progression_id.begins_with("quest:"):
		return result
	var completed: Array = result.get("completed_quests", []) as Array
	if completed.has(progression_id):
		return result
	var rewards: Array = event.get("reward_ids", []) as Array
	var progression_state: RefCounted = PLAYER_PROGRESSION.new()
	if not bool(progression_state.call("load_dict", result.get("progression", {}) as Dictionary)):
		return result
	for reward_value in rewards:
		var reward_id: String = str(reward_value)
		if reward_id.begins_with("xp:"):
			var xp_text: String = reward_id.trim_prefix("xp:")
			if xp_text.is_valid_int():
				progression_state.call("grant_xp", maxi(0, xp_text.to_int()), progression_id)
	result["progression"] = progression_state.call("to_dict") as Dictionary
	result["magic"] = MAGIC.apply_quest_rewards(result.get("magic", {}) as Dictionary, progression_id, rewards)
	completed.append(progression_id)
	completed.sort()
	result["completed_quests"] = completed
	_increment_revision(result)
	return result

static func apply_lore_discovery(bundle: Dictionary, lore_record_id: String) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result) or lore_record_id.is_empty():
		return result
	var before: Dictionary = result.get("magic", {}) as Dictionary
	var after: Dictionary = MAGIC.apply_lore_discovery(before, lore_record_id)
	if var_to_str(before) == var_to_str(after):
		return result
	result["magic"] = after
	_increment_revision(result)
	return result

static func equip_item(bundle: Dictionary, item: Dictionary) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result) or not EQUIPMENT.validate_instance(item):
		return result
	var before: Dictionary = result.get("build", {}) as Dictionary
	var after: Dictionary = BUILD.equip(before, item, player_level(result))
	if var_to_str(before) == var_to_str(after):
		return result
	result["build"] = after
	_increment_revision(result)
	return result

static func assign_spell(bundle: Dictionary, slot_index: int, spell_id: String) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result):
		return result
	var before: Dictionary = result.get("build", {}) as Dictionary
	var after: Dictionary = BUILD.assign_spell(before, slot_index, spell_id, player_level(result), result.get("magic", {}) as Dictionary)
	if var_to_str(before) == var_to_str(after):
		return result
	result["build"] = after
	_increment_revision(result)
	return result

static func derived_stats(bundle: Dictionary, spent_attributes: Dictionary = {}) -> Dictionary:
	if not validate(bundle):
		return {}
	return BUILD.derive_stats(bundle.get("build", {}) as Dictionary, player_level(bundle), bundle.get("magic", {}) as Dictionary, spent_attributes)

static func save_envelope(bundle: Dictionary) -> Dictionary:
	if not validate(bundle):
		return {}
	var player_id: String = str(bundle.get("player_id", ""))
	var payload: Dictionary = SAVE_CODEC.encode(
		player_id,
		bundle.get("progression", {}) as Dictionary,
		bundle.get("magic", {}) as Dictionary,
		bundle.get("build", {}) as Dictionary,
		_to_string_array(bundle.get("completed_quests", []) as Array),
		int(bundle.get("revision", 0))
	)
	if payload.is_empty():
		return {}
	return {
		"bundle_version": FORMAT_VERSION,
		"progression_payload": payload,
		"applied_reward_ids": (bundle.get("applied_reward_ids", []) as Array).duplicate()
	}

static func restore_envelope(envelope: Dictionary) -> Dictionary:
	if int(envelope.get("bundle_version", -1)) != FORMAT_VERSION:
		return {}
	var payload_value: Variant = envelope.get("progression_payload", {})
	var rewards_value: Variant = envelope.get("applied_reward_ids", [])
	if not payload_value is Dictionary or not rewards_value is Array or not _validate_stable_ids(rewards_value as Array, "progression_reward:"):
		return {}
	var decoded: Dictionary = SAVE_CODEC.decode(payload_value as Dictionary)
	if decoded.is_empty():
		return {}
	var restored: Dictionary = {
		"format_version": FORMAT_VERSION,
		"player_id": str(decoded.get("player_id", "")),
		"revision": int(decoded.get("revision", 0)),
		"progression": (decoded.get("progression", {}) as Dictionary).duplicate(true),
		"magic": (decoded.get("magic", {}) as Dictionary).duplicate(true),
		"build": (decoded.get("build", {}) as Dictionary).duplicate(true),
		"completed_quests": _to_plain_array(decoded.get("completed_quests", []) as Array),
		"applied_reward_ids": _to_plain_array(rewards_value as Array)
	}
	return restored if validate(restored) else {}

static func build_network_snapshot(bundle: Dictionary, replicator: Node = null) -> Dictionary:
	if not validate(bundle):
		return {}
	var network: Node = replicator
	if network == null:
		network = NETWORK_REPLICATOR.new()
	return network.call(
		"build_player_snapshot",
		str(bundle.get("player_id", "")),
		bundle.get("progression", {}) as Dictionary,
		bundle.get("magic", {}) as Dictionary,
		bundle.get("build", {}) as Dictionary,
		_to_string_array(bundle.get("completed_quests", []) as Array),
		maxi(1, int(bundle.get("revision", 0)))
	) as Dictionary

static func _increment_revision(bundle: Dictionary) -> void:
	bundle["revision"] = int(bundle.get("revision", 0)) + 1

static func _validate_stable_ids(values: Array, prefix: String) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var stable_id: String = str(value)
		if not stable_id.begins_with(prefix) or seen.has(stable_id):
			return false
		seen[stable_id] = true
	return true

static func _to_string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result

static func _to_plain_array(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(value)
	return result
