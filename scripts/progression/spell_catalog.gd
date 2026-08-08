extends RefCounted
class_name SpellCatalog

const FORMAT_VERSION: int = 1

const SPELLS: Dictionary = {
	"spell:ember_bolt": {
		"display_name": "Ember Bolt",
		"school": "pyromancy",
		"resource": "mana",
		"cost": 12,
		"cast_time": 0.35,
		"cooldown": 0.65,
		"targeting": "projectile",
		"range": 24.0,
		"tags": ["damage", "fire", "starter"],
		"requirements": {"level": 3, "rewards": ["reward:magic:first_spell_slot"]}
	},
	"spell:veil_mend": {
		"display_name": "Veil Mend",
		"school": "restoration",
		"resource": "mana",
		"cost": 18,
		"cast_time": 0.6,
		"cooldown": 4.0,
		"targeting": "self",
		"range": 0.0,
		"tags": ["healing", "support"],
		"requirements": {"level": 5, "rewards": []}
	},
	"spell:moonward": {
		"display_name": "Moonward",
		"school": "mooncraft",
		"resource": "mana",
		"cost": 22,
		"cast_time": 0.45,
		"cooldown": 7.0,
		"targeting": "self",
		"range": 0.0,
		"tags": ["defense", "ward"],
		"requirements": {"level": 8, "rewards": ["reward:magic:second_spell_slot"]}
	},
	"spell:grave_grasp": {
		"display_name": "Grave Grasp",
		"school": "necromancy",
		"resource": "mana",
		"cost": 26,
		"cast_time": 0.75,
		"cooldown": 5.5,
		"targeting": "ground_area",
		"range": 18.0,
		"tags": ["control", "shadow", "area"],
		"requirements": {"level": 12, "rewards": []}
	}
}

func has_spell(spell_id: String) -> bool:
	return SPELLS.has(spell_id)

func get_spell(spell_id: String) -> Dictionary:
	if not SPELLS.has(spell_id):
		return {}
	return (SPELLS[spell_id] as Dictionary).duplicate(true)

func spell_ids() -> Array[String]:
	var ids: Array[String] = []
	for spell_id in SPELLS.keys():
		ids.append(str(spell_id))
	ids.sort()
	return ids

func school_ids() -> Array[String]:
	var schools: Array[String] = []
	for spell_id in SPELLS.keys():
		var school: String = str((SPELLS[spell_id] as Dictionary).get("school", ""))
		if not school.is_empty() and not schools.has(school):
			schools.append(school)
	schools.sort()
	return schools

func spells_for_school(school_id: String) -> Array[String]:
	var ids: Array[String] = []
	for spell_id in SPELLS.keys():
		if str((SPELLS[spell_id] as Dictionary).get("school", "")) == school_id:
			ids.append(str(spell_id))
	ids.sort()
	return ids

func can_unlock(spell_id: String, level: int, unlocked_rewards: Array[String]) -> bool:
	var spell: Dictionary = get_spell(spell_id)
	if spell.is_empty():
		return false
	var requirements: Dictionary = spell.get("requirements", {}) as Dictionary
	if level < int(requirements.get("level", 1)):
		return false
	for required_reward in requirements.get("rewards", []) as Array:
		if not unlocked_rewards.has(str(required_reward)):
			return false
	return true

func casting_contract(spell_id: String) -> Dictionary:
	var spell: Dictionary = get_spell(spell_id)
	if spell.is_empty():
		return {}
	return {
		"format_version": FORMAT_VERSION,
		"spell_id": spell_id,
		"resource": str(spell.get("resource", "mana")),
		"cost": maxi(0, int(spell.get("cost", 0))),
		"cast_time": maxf(0.0, float(spell.get("cast_time", 0.0))),
		"cooldown": maxf(0.0, float(spell.get("cooldown", 0.0))),
		"targeting": str(spell.get("targeting", "self")),
		"range": maxf(0.0, float(spell.get("range", 0.0)))
	}

func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	for spell_id in spell_ids():
		var spell: Dictionary = get_spell(spell_id)
		if not spell_id.begins_with("spell:"):
			errors.append("invalid stable id: %s" % spell_id)
		if str(spell.get("display_name", "")).is_empty():
			errors.append("missing display name: %s" % spell_id)
		if str(spell.get("school", "")).is_empty():
			errors.append("missing school: %s" % spell_id)
		if int(spell.get("cost", -1)) < 0:
			errors.append("invalid cost: %s" % spell_id)
		if float(spell.get("cast_time", -1.0)) < 0.0 or float(spell.get("cooldown", -1.0)) < 0.0:
			errors.append("invalid timing: %s" % spell_id)
		if str(spell.get("targeting", "")).is_empty():
			errors.append("missing targeting: %s" % spell_id)
	return errors
