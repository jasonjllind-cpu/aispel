extends RefCounted
class_name ProgressionSaveCodec

const CURRENT_VERSION: int = 2
const LEGACY_VERSION: int = 1
const PLAYER_PROGRESSION := preload("res://scripts/progression/player_progression_state.gd")
const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")
const BUILD := preload("res://scripts/progression/character_build_model.gd")

static func encode(player_id: String, progression: Dictionary, magic: Dictionary, build: Dictionary, completed_quests: Array[String], revision: int = 0) -> Dictionary:
	var payload: Dictionary = {
		"version": CURRENT_VERSION,
		"player_id": player_id,
		"revision": maxi(0, revision),
		"progression": progression.duplicate(true),
		"magic": magic.duplicate(true),
		"build": build.duplicate(true),
		"completed_quests": completed_quests.duplicate()
	}
	return payload if validate(payload) else {}

static func validate(payload: Dictionary) -> bool:
	if int(payload.get("version", -1)) != CURRENT_VERSION:
		return false
	var player_id: String = str(payload.get("player_id", ""))
	if player_id.is_empty() or int(payload.get("revision", -1)) < 0:
		return false
	var progression_value: Variant = payload.get("progression", {})
	var magic_value: Variant = payload.get("magic", {})
	var build_value: Variant = payload.get("build", {})
	var quests_value: Variant = payload.get("completed_quests", [])
	if not progression_value is Dictionary or not magic_value is Dictionary or not build_value is Dictionary or not quests_value is Array:
		return false
	var progression: Dictionary = progression_value as Dictionary
	if str(progression.get("player_id", "")) != player_id or not _validate_progression(progression):
		return false
	var magic: Dictionary = magic_value as Dictionary
	if str(magic.get("player_id", "")) != player_id or not MAGIC.validate_state(magic):
		return false
	var build: Dictionary = build_value as Dictionary
	if str(build.get("player_id", "")) != player_id or not BUILD.validate_build(build):
		return false
	return _validate_quests(quests_value as Array)

static func migrate(payload: Dictionary) -> Dictionary:
	var version: int = int(payload.get("version", LEGACY_VERSION))
	if version == CURRENT_VERSION:
		return payload.duplicate(true) if validate(payload) else {}
	if version != LEGACY_VERSION:
		return {}
	return _migrate_v1(payload)

static func decode(payload: Dictionary) -> Dictionary:
	var migrated: Dictionary = migrate(payload)
	if migrated.is_empty():
		return {}
	return {
		"player_id": str(migrated.get("player_id", "")),
		"revision": int(migrated.get("revision", 0)),
		"progression": (migrated.get("progression", {}) as Dictionary).duplicate(true),
		"magic": (migrated.get("magic", {}) as Dictionary).duplicate(true),
		"build": (migrated.get("build", {}) as Dictionary).duplicate(true),
		"completed_quests": (migrated.get("completed_quests", []) as Array).duplicate()
	}

static func build_legacy_v1(player_id: String, level: int, current_xp: int, lifetime_xp: int, unspent_points: int, unlocked_spells: Array[String], completed_quests: Array[String]) -> Dictionary:
	return {
		"version": LEGACY_VERSION,
		"player_id": player_id,
		"level": level,
		"current_xp": current_xp,
		"lifetime_xp": lifetime_xp,
		"unspent_attribute_points": unspent_points,
		"unlocked_spells": unlocked_spells.duplicate(),
		"completed_quests": completed_quests.duplicate()
	}

static func _migrate_v1(payload: Dictionary) -> Dictionary:
	var player_id: String = str(payload.get("player_id", ""))
	if player_id.is_empty():
		return {}
	var progression_state: RefCounted = PLAYER_PROGRESSION.new()
	var progression: Dictionary = {
		"format_version": PLAYER_PROGRESSION.FORMAT_VERSION,
		"player_id": player_id,
		"level": int(payload.get("level", 1)),
		"current_xp": int(payload.get("current_xp", 0)),
		"lifetime_xp": int(payload.get("lifetime_xp", 0)),
		"unspent_attribute_points": int(payload.get("unspent_attribute_points", 0)),
		"unlocked_rewards": []
	}
	if not bool(progression_state.call("load_dict", progression)):
		return {}
	var magic: Dictionary = MAGIC.create_state(player_id)
	var unlocked_value: Variant = payload.get("unlocked_spells", [])
	if not unlocked_value is Array:
		return {}
	var unlocked: Array = magic.get("unlocked_spells", []) as Array
	for spell_value in unlocked_value as Array:
		var spell_id: String = str(spell_value)
		if spell_id.is_empty():
			continue
		var spell = preload("res://scripts/magic/spell_catalog.gd").get_spell(spell_id)
		if spell.is_empty():
			return {}
		if not unlocked.has(spell_id):
			unlocked.append(spell_id)
	unlocked.sort()
	magic["unlocked_spells"] = unlocked
	var build: Dictionary = BUILD.create_build(player_id)
	var quests_value: Variant = payload.get("completed_quests", [])
	if not quests_value is Array or not _validate_quests(quests_value as Array):
		return {}
	var migrated: Dictionary = {
		"version": CURRENT_VERSION,
		"player_id": player_id,
		"revision": 0,
		"progression": progression,
		"magic": magic,
		"build": build,
		"completed_quests": (quests_value as Array).duplicate()
	}
	return migrated if validate(migrated) else {}

static func _validate_progression(data: Dictionary) -> bool:
	var state: RefCounted = PLAYER_PROGRESSION.new()
	return bool(state.call("load_dict", data))

static func _validate_quests(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var quest_id: String = str(value)
		if not quest_id.begins_with("quest:") or seen.has(quest_id):
			return false
		seen[quest_id] = true
	return true
