extends RefCounted
class_name CharacterBuildModel

const FORMAT_VERSION: int = 1
const MAX_SPELL_SLOTS: int = 3
const EQUIPMENT := preload("res://scripts/equipment/equipment_progression_catalog.gd")
const SPELLS := preload("res://scripts/magic/spell_catalog.gd")
const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")

const EQUIPMENT_SLOTS: Array[String] = ["weapon", "armor"]

static func create_build(player_id: String) -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"player_id": player_id if not player_id.is_empty() else "player:local",
		"equipment": {"weapon": {}, "armor": {}},
		"spell_slots": ["", "", ""]
	}

static func validate_build(build: Dictionary) -> bool:
	if int(build.get("format_version", -1)) != FORMAT_VERSION or str(build.get("player_id", "")).is_empty():
		return false
	var equipment_value: Variant = build.get("equipment", {})
	var spells_value: Variant = build.get("spell_slots", [])
	if not equipment_value is Dictionary or not spells_value is Array:
		return false
	var equipment: Dictionary = equipment_value as Dictionary
	for slot in EQUIPMENT_SLOTS:
		if not equipment.has(slot) or not equipment[slot] is Dictionary:
			return false
		var item: Dictionary = equipment[slot] as Dictionary
		if not item.is_empty():
			if not EQUIPMENT.validate_instance(item) or str(item.get("slot", "")) != slot:
				return false
	var spell_slots: Array = spells_value as Array
	if spell_slots.size() != MAX_SPELL_SLOTS:
		return false
	var seen_spells: Dictionary = {}
	for spell_value in spell_slots:
		var spell_id: String = str(spell_value)
		if spell_id.is_empty():
			continue
		if SPELLS.get_spell(spell_id).is_empty() or seen_spells.has(spell_id):
			return false
		seen_spells[spell_id] = true
	return true

static func equip(build: Dictionary, item: Dictionary, player_level: int) -> Dictionary:
	var result: Dictionary = build.duplicate(true)
	if not validate_build(result) or not EQUIPMENT.validate_instance(item):
		return result
	if int(item.get("item_level", 1)) > maxi(1, player_level):
		return result
	var slot: String = str(item.get("slot", ""))
	if not EQUIPMENT_SLOTS.has(slot):
		return result
	var equipment: Dictionary = result.get("equipment", {}) as Dictionary
	equipment[slot] = item.duplicate(true)
	result["equipment"] = equipment
	return result

static func unequip(build: Dictionary, slot: String) -> Dictionary:
	var result: Dictionary = build.duplicate(true)
	if not validate_build(result) or not EQUIPMENT_SLOTS.has(slot):
		return result
	var equipment: Dictionary = result.get("equipment", {}) as Dictionary
	equipment[slot] = {}
	result["equipment"] = equipment
	return result

static func assign_spell(build: Dictionary, slot_index: int, spell_id: String, player_level: int, magic_state: Dictionary) -> Dictionary:
	var result: Dictionary = build.duplicate(true)
	if not validate_build(result) or slot_index < 0 or slot_index >= MAX_SPELL_SLOTS:
		return result
	if spell_id.is_empty():
		var cleared: Array = result.get("spell_slots", []) as Array
		cleared[slot_index] = ""
		result["spell_slots"] = cleared
		return result
	if not MAGIC.available_spells(magic_state, player_level).has(spell_id):
		return result
	var slots: Array = result.get("spell_slots", []) as Array
	for index in range(slots.size()):
		if index != slot_index and str(slots[index]) == spell_id:
			slots[index] = ""
	slots[slot_index] = spell_id
	result["spell_slots"] = slots
	return result

static func derive_stats(build: Dictionary, player_level: int, magic_state: Dictionary, spent_attributes: Dictionary = {}) -> Dictionary:
	if not validate_build(build):
		return {}
	var level: int = maxi(1, player_level)
	var might: int = maxi(0, int(spent_attributes.get("might", 0)))
	var vitality: int = maxi(0, int(spent_attributes.get("vitality", 0)))
	var focus: int = maxi(0, int(spent_attributes.get("focus", 0)))
	var agility: int = maxi(0, int(spent_attributes.get("agility", 0)))
	var total_school_rank: int = 0
	if MAGIC.validate_state(magic_state):
		var schools: Dictionary = magic_state.get("schools", {}) as Dictionary
		for school_id in MAGIC.get_school_ids():
			total_school_rank += int((schools.get(school_id, {}) as Dictionary).get("rank", 0))
	var stats: Dictionary = {
		"max_health": 100.0 + float(level - 1) * 5.0 + float(vitality) * 8.0,
		"stamina": 100.0 + float(level - 1) * 2.0 + float(agility) * 5.0,
		"mana": 70.0 + float(level - 1) * 4.0 + float(focus) * 7.0 + float(total_school_rank) * 3.0,
		"damage": 10.0 + float(level - 1) * 1.35 + float(might) * 2.25,
		"armor": float(vitality) * 0.6,
		"magic_power": 5.0 + float(level - 1) * 0.8 + float(focus) * 2.0 + float(total_school_rank) * 1.75,
		"critical_chance": 0.05 + float(agility) * 0.003,
		"frost_resistance": 0.0
	}
	var equipment: Dictionary = build.get("equipment", {}) as Dictionary
	for slot in EQUIPMENT_SLOTS:
		var item: Dictionary = equipment.get(slot, {}) as Dictionary
		if item.is_empty():
			continue
		for stat_key in (item.get("stats", {}) as Dictionary).keys():
			var stat_name: String = str(stat_key)
			stats[stat_name] = float(stats.get(stat_name, 0.0)) + float((item.get("stats", {}) as Dictionary)[stat_key])
	for stat_name in stats.keys():
		stats[stat_name] = _round_stat(float(stats[stat_name]))
	return stats

static func build_snapshot(build: Dictionary, player_level: int, magic_state: Dictionary, spent_attributes: Dictionary = {}) -> Dictionary:
	if not validate_build(build):
		return {}
	var stats: Dictionary = derive_stats(build, player_level, magic_state, spent_attributes)
	var equipment: Dictionary = build.get("equipment", {}) as Dictionary
	var equipment_ids: Dictionary = {}
	for slot in EQUIPMENT_SLOTS:
		var item: Dictionary = equipment.get(slot, {}) as Dictionary
		equipment_ids[slot] = str(item.get("instance_id", ""))
	var spells: Array = (build.get("spell_slots", []) as Array).duplicate()
	var canonical: String = "%s|%d|%s|%s|%s" % [str(build.get("player_id", "")), player_level, var_to_str(equipment_ids), var_to_str(spells), var_to_str(stats)]
	return {
		"format_version": FORMAT_VERSION,
		"player_id": str(build.get("player_id", "")),
		"snapshot_id": "build:%s:%d" % [str(build.get("player_id", "")).trim_prefix("player:"), int(canonical.hash() & 0x7fffffff)],
		"player_level": player_level,
		"equipment_ids": equipment_ids,
		"spell_slots": spells,
		"derived_stats": stats
	}

static func _round_stat(value: float) -> float:
	return roundf(value * 1000.0) / 1000.0
