extends RefCounted
class_name MagicSchoolProgression

const SpellCatalogScript = preload("res://scripts/magic/spell_catalog.gd")
const FORMAT_VERSION: int = 1

const SCHOOLS: Dictionary = {
	"moon": {
		"required_level": 3,
		"discovery_ids": ["discovery:moon_shrine"],
		"reward_ids_any": ["spell:moon_bolt", "reward:magic:moon_path"],
		"starter_spell": "moon_bolt"
	},
	"ember": {
		"required_level": 4,
		"discovery_ids": ["discovery:ashen_fen_ember_altar"],
		"reward_ids_any": ["reward:magic:ember_path"],
		"starter_spell": "ember_dart"
	},
	"frost": {
		"required_level": 6,
		"discovery_ids": ["discovery:frostmere_rune"],
		"reward_ids_any": ["reward:magic:frost_path"],
		"starter_spell": "frost_lance"
	},
	"thorn": {
		"required_level": 7,
		"discovery_ids": ["discovery:blackwood_witch_stone"],
		"reward_ids_any": ["spell:thorn_grasp", "reward:magic:thorn_path"],
		"starter_spell": "thorn_grasp"
	},
	"storm": {
		"required_level": 11,
		"discovery_ids": ["discovery:windscar_beacon"],
		"reward_ids_any": ["reward:quest:beacon_rekindled", "reward:magic:storm_path"],
		"starter_spell": "storm_spear"
	},
	"veil": {
		"required_level": 13,
		"discovery_ids": ["discovery:veilmoor_pale_ring"],
		"reward_ids_any": ["reward:magic:veil_path"],
		"starter_spell": "veil_touch"
	}
}

var unlocked_schools: Array[String] = []
var unlocked_spells: Array[String] = []
var discoveries: Array[String] = []
var consumed_rewards: Array[String] = []

func school_ids() -> Array[String]:
	var ids: Array[String] = []
	for school_id in SCHOOLS.keys():
		ids.append(str(school_id))
	ids.sort()
	return ids

func apply_progression_snapshot(player_level: int, reward_ids: Array[String], discovery_ids: Array[String]) -> Dictionary:
	for discovery_id in discovery_ids:
		_record_unique(discoveries, discovery_id)
	for reward_id in reward_ids:
		_record_unique(consumed_rewards, reward_id)

	var newly_unlocked_schools: Array[String] = []
	var newly_unlocked_spells: Array[String] = []
	for school_id in school_ids():
		if unlocked_schools.has(school_id):
			continue
		if not _school_requirements_met(school_id, player_level):
			continue
		unlocked_schools.append(school_id)
		newly_unlocked_schools.append(school_id)
		var starter_spell: String = str((SCHOOLS[school_id] as Dictionary).get("starter_spell", ""))
		if not starter_spell.is_empty() and not unlocked_spells.has(starter_spell):
			unlocked_spells.append(starter_spell)
			newly_unlocked_spells.append(starter_spell)

	for reward_id in consumed_rewards:
		if reward_id.begins_with("spell:"):
			var spell_id: String = reward_id.trim_prefix("spell:")
			var spell: Dictionary = SpellCatalogScript.get_spell(spell_id)
			if not spell.is_empty() and int(spell.get("required_level", 1)) <= player_level:
				var school_id: String = str(spell.get("school", ""))
				if unlocked_schools.has(school_id) and not unlocked_spells.has(spell_id):
					unlocked_spells.append(spell_id)
					newly_unlocked_spells.append(spell_id)

	for spell_id in SpellCatalogScript.get_ids():
		var spell: Dictionary = SpellCatalogScript.get_spell(spell_id)
		var school_id: String = str(spell.get("school", ""))
		if unlocked_schools.has(school_id) and int(spell.get("required_level", 1)) <= player_level:
			if _advanced_spell_gate_met(spell_id, school_id) and not unlocked_spells.has(spell_id):
				unlocked_spells.append(spell_id)
				newly_unlocked_spells.append(spell_id)

	unlocked_schools.sort()
	unlocked_spells.sort()
	newly_unlocked_schools.sort()
	newly_unlocked_spells.sort()
	return {
		"new_schools": newly_unlocked_schools,
		"new_spells": newly_unlocked_spells,
		"unlocked_schools": unlocked_schools.duplicate(),
		"unlocked_spells": unlocked_spells.duplicate()
	}

func register_discovery(discovery_id: String, player_level: int, reward_ids: Array[String] = []) -> Dictionary:
	var current_discoveries: Array[String] = discoveries.duplicate()
	_record_unique(current_discoveries, discovery_id)
	return apply_progression_snapshot(player_level, reward_ids, current_discoveries)

func apply_quest_rewards(player_level: int, reward_ids: Array[String]) -> Dictionary:
	return apply_progression_snapshot(player_level, reward_ids, discoveries.duplicate())

func can_use_spell(spell_id: String, player_level: int) -> bool:
	if not unlocked_spells.has(spell_id):
		return false
	var spell: Dictionary = SpellCatalogScript.get_spell(spell_id)
	return not spell.is_empty() and int(spell.get("required_level", 1)) <= player_level and unlocked_schools.has(str(spell.get("school", "")))

func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"unlocked_schools": unlocked_schools.duplicate(),
		"unlocked_spells": unlocked_spells.duplicate(),
		"discoveries": discoveries.duplicate(),
		"consumed_rewards": consumed_rewards.duplicate()
	}

func load_dict(data: Dictionary) -> bool:
	if int(data.get("format_version", -1)) != FORMAT_VERSION:
		return false
	for key in ["unlocked_schools", "unlocked_spells", "discoveries", "consumed_rewards"]:
		if not data.get(key, []) is Array:
			return false
	var loaded_schools: Array[String] = _normalized_strings(data.get("unlocked_schools", []) as Array)
	var loaded_spells: Array[String] = _normalized_strings(data.get("unlocked_spells", []) as Array)
	for school_id in loaded_schools:
		if not SCHOOLS.has(school_id):
			return false
	for spell_id in loaded_spells:
		if SpellCatalogScript.get_spell(spell_id).is_empty():
			return false
		if not loaded_schools.has(str(SpellCatalogScript.get_spell(spell_id).get("school", ""))):
			return false
	unlocked_schools = loaded_schools
	unlocked_spells = loaded_spells
	discoveries = _normalized_strings(data.get("discoveries", []) as Array)
	consumed_rewards = _normalized_strings(data.get("consumed_rewards", []) as Array)
	return true

func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	var spell_schools: Array[String] = SpellCatalogScript.get_school_ids()
	for school_id in school_ids():
		var definition: Dictionary = SCHOOLS[school_id] as Dictionary
		if not spell_schools.has(school_id):
			errors.append("school has no spells: %s" % school_id)
		if int(definition.get("required_level", 0)) <= 0:
			errors.append("invalid required level: %s" % school_id)
		var starter_spell: String = str(definition.get("starter_spell", ""))
		var spell: Dictionary = SpellCatalogScript.get_spell(starter_spell)
		if spell.is_empty() or str(spell.get("school", "")) != school_id:
			errors.append("invalid starter spell: %s" % school_id)
		if (definition.get("discovery_ids", []) as Array).is_empty() and (definition.get("reward_ids_any", []) as Array).is_empty():
			errors.append("school has no discovery or quest gate: %s" % school_id)
	return errors

func _school_requirements_met(school_id: String, player_level: int) -> bool:
	var definition: Dictionary = SCHOOLS[school_id] as Dictionary
	if player_level < int(definition.get("required_level", 1)):
		return false
	for discovery_id in definition.get("discovery_ids", []) as Array:
		if discoveries.has(str(discovery_id)):
			return true
	for reward_id in definition.get("reward_ids_any", []) as Array:
		if consumed_rewards.has(str(reward_id)):
			return true
	return false

func _advanced_spell_gate_met(spell_id: String, school_id: String) -> bool:
	var starter_spell: String = str((SCHOOLS[school_id] as Dictionary).get("starter_spell", ""))
	if spell_id == starter_spell:
		return true
	return consumed_rewards.has("spell:%s" % spell_id) or consumed_rewards.has("reward:magic:%s_mastery" % school_id)

func _record_unique(target: Array[String], value: String) -> void:
	if not value.is_empty() and not target.has(value):
		target.append(value)
	target.sort()

func _normalized_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text: String = str(value)
		if not text.is_empty() and not result.has(text):
			result.append(text)
	result.sort()
	return result
