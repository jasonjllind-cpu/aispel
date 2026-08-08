extends RefCounted
class_name MagicSchoolProgression

const FORMAT_VERSION: int = 1
const SPELLS := preload("res://scripts/magic/spell_catalog.gd")
const LORE := preload("res://scripts/world/lore_discovery_catalog.gd")

const SCHOOLS: Dictionary = {
	"moon": {"rank_thresholds": [0, 120, 360, 760], "rank_names": ["Initiate", "Acolyte", "Seer", "Luminary"]},
	"ember": {"rank_thresholds": [0, 140, 400, 820], "rank_names": ["Spark", "Kindled", "Cinder Sage", "Flamekeeper"]},
	"frost": {"rank_thresholds": [0, 150, 420, 850], "rank_names": ["Rimeborn", "Icebound", "Winter Sage", "Frostkeeper"]},
	"thorn": {"rank_thresholds": [0, 130, 390, 800], "rank_names": ["Seedling", "Rootbound", "Thorn Sage", "Grovekeeper"]},
	"storm": {"rank_thresholds": [0, 150, 430, 880], "rank_names": ["Breeze", "Gale", "Storm Sage", "Skykeeper"]},
	"veil": {"rank_thresholds": [0, 160, 460, 920], "rank_names": ["Whisper", "Pale Hand", "Veil Sage", "Gatekeeper"]}
}

const LORE_SCHOOL_OVERRIDES: Dictionary = {
	"moon_shrine_verse": "moon",
	"valley_relic_record": "moon",
	"blackwood_warning": "thorn",
	"root_chapel_fragment": "thorn",
	"witchwood_charm_record": "thorn",
	"windscar_beacon_marks": "storm",
	"giants_step_account": "storm",
	"storm_glass_record": "storm",
	"veilmoor_funeral_prayer": "veil",
	"drowned_bell_inscription": "veil",
	"pale_procession_account": "veil",
	"cinder_watch_tablet": "ember",
	"witchfire_litany": "ember",
	"ember_glass_record": "ember",
	"frostmere_waystone": "frost",
	"icebound_pilgrim_page": "frost",
	"frost_glass_record": "frost"
}

static func create_state(player_id: String) -> Dictionary:
	var schools: Dictionary = {}
	for school_id in get_school_ids():
		schools[school_id] = {"mastery_xp": 0, "rank": 0}
	return {
		"format_version": FORMAT_VERSION,
		"player_id": player_id if not player_id.is_empty() else "player:local",
		"schools": schools,
		"unlocked_spells": [],
		"discoveries": []
	}

static func get_school_ids() -> Array[String]:
	var result: Array[String] = []
	for key in SCHOOLS.keys():
		result.append(str(key))
	result.sort()
	return result

static func validate_state(state: Dictionary) -> bool:
	if int(state.get("format_version", -1)) != FORMAT_VERSION or str(state.get("player_id", "")).is_empty():
		return false
	var schools_value: Variant = state.get("schools", {})
	var spells_value: Variant = state.get("unlocked_spells", [])
	var discoveries_value: Variant = state.get("discoveries", [])
	if not schools_value is Dictionary or not spells_value is Array or not discoveries_value is Array:
		return false
	var schools: Dictionary = schools_value as Dictionary
	for school_id in get_school_ids():
		if not schools.has(school_id) or not schools[school_id] is Dictionary:
			return false
		var school_state: Dictionary = schools[school_id] as Dictionary
		var xp: int = int(school_state.get("mastery_xp", -1))
		var rank: int = int(school_state.get("rank", -1))
		if xp < 0 or rank != rank_for_xp(school_id, xp):
			return false
	for spell_value in spells_value as Array:
		if SPELLS.get_spell(str(spell_value)).is_empty():
			return false
	return true

static func rank_for_xp(school_id: String, mastery_xp: int) -> int:
	if not SCHOOLS.has(school_id):
		return -1
	var thresholds: Array = (SCHOOLS[school_id] as Dictionary).get("rank_thresholds", []) as Array
	var rank: int = 0
	for index in range(thresholds.size()):
		if mastery_xp >= int(thresholds[index]):
			rank = index
	return rank

static func grant_mastery(state: Dictionary, school_id: String, amount: int, discovery_id: String = "") -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	if not validate_state(result) or not SCHOOLS.has(school_id) or amount <= 0:
		return result
	var schools: Dictionary = result.get("schools", {}) as Dictionary
	var school_state: Dictionary = (schools[school_id] as Dictionary).duplicate(true)
	var old_rank: int = int(school_state.get("rank", 0))
	var new_xp: int = int(school_state.get("mastery_xp", 0)) + amount
	var new_rank: int = rank_for_xp(school_id, new_xp)
	school_state["mastery_xp"] = new_xp
	school_state["rank"] = new_rank
	schools[school_id] = school_state
	result["schools"] = schools
	if not discovery_id.is_empty():
		var discoveries: Array = result.get("discoveries", []) as Array
		if not discoveries.has(discovery_id):
			discoveries.append(discovery_id)
			discoveries.sort()
		result["discoveries"] = discoveries
	if new_rank > old_rank:
		_unlock_rank_spells(result, school_id, new_rank)
	return result

static func apply_quest_rewards(state: Dictionary, quest_progression_id: String, reward_ids: Array) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	if not validate_state(result) or quest_progression_id.is_empty():
		return result
	var discovery_id: String = "magic_discovery:quest:%s" % quest_progression_id.trim_prefix("quest:")
	if (result.get("discoveries", []) as Array).has(discovery_id):
		return result
	var touched_schools: Dictionary = {}
	for reward_value in reward_ids:
		var reward_id: String = str(reward_value)
		if not reward_id.begins_with("spell:"):
			continue
		var spell_id: String = reward_id.trim_prefix("spell:")
		var spell: Dictionary = SPELLS.get_spell(spell_id)
		if spell.is_empty():
			continue
		var school_id: String = str(spell.get("school", ""))
		_unlock_spell(result, spell_id)
		touched_schools[school_id] = true
	for school_id in touched_schools.keys():
		result = grant_mastery(result, str(school_id), 90, "")
	var discoveries: Array = result.get("discoveries", []) as Array
	discoveries.append(discovery_id)
	discoveries.sort()
	result["discoveries"] = discoveries
	return result

static func apply_lore_discovery(state: Dictionary, lore_record_id: String) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	if not validate_state(result):
		return result
	var record: Dictionary = LORE.get_record(lore_record_id)
	if record.is_empty():
		return result
	var school_id: String = str(LORE_SCHOOL_OVERRIDES.get(lore_record_id, ""))
	if school_id.is_empty():
		return result
	var discovery_id: String = "magic_discovery:lore:%s" % lore_record_id
	if (result.get("discoveries", []) as Array).has(discovery_id):
		return result
	var amount: int = 55
	match str(record.get("type", "")):
		"shrine": amount = 85
		"relic_record": amount = 70
		"history_fragment": amount = 65
		_: amount = 55
	return grant_mastery(result, school_id, amount, discovery_id)

static func available_spells(state: Dictionary, player_level: int) -> Array[String]:
	var result: Array[String] = []
	if not validate_state(state):
		return result
	var unlocked: Array = state.get("unlocked_spells", []) as Array
	for spell_value in unlocked:
		var spell_id: String = str(spell_value)
		var spell: Dictionary = SPELLS.get_spell(spell_id)
		if not spell.is_empty() and player_level >= int(spell.get("required_level", 1)):
			result.append(spell_id)
	result.sort()
	return result

static func _unlock_rank_spells(state: Dictionary, school_id: String, rank: int) -> void:
	for spell_id in SPELLS.get_ids():
		var spell: Dictionary = SPELLS.get_spell(spell_id)
		if str(spell.get("school", "")) != school_id:
			continue
		var required_level: int = int(spell.get("required_level", 1))
		var required_rank: int = 1 if required_level <= 8 else (2 if required_level <= 13 else 3)
		if rank >= required_rank:
			_unlock_spell(state, spell_id)

static func _unlock_spell(state: Dictionary, spell_id: String) -> void:
	if SPELLS.get_spell(spell_id).is_empty():
		return
	var unlocked: Array = state.get("unlocked_spells", []) as Array
	if not unlocked.has(spell_id):
		unlocked.append(spell_id)
		unlocked.sort()
	state["unlocked_spells"] = unlocked
