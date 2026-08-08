extends RefCounted
class_name SpellCatalog

const FORMAT_VERSION: int = 1

const SPELLS: Dictionary = {
	"moon_bolt": {"school": "moon", "required_level": 3, "resource": "mana", "cost": 12, "cooldown": 0.8, "cast_time": 0.15, "range": 18.0, "power": 22.0, "targeting": "projectile", "tags": ["damage", "ranged"]},
	"moon_ward": {"school": "moon", "required_level": 5, "resource": "mana", "cost": 18, "cooldown": 6.0, "cast_time": 0.25, "range": 0.0, "power": 30.0, "targeting": "self", "tags": ["ward", "defense"]},
	"ember_dart": {"school": "ember", "required_level": 4, "resource": "mana", "cost": 14, "cooldown": 0.9, "cast_time": 0.12, "range": 16.0, "power": 26.0, "targeting": "projectile", "tags": ["damage", "fire"]},
	"cinder_ring": {"school": "ember", "required_level": 8, "resource": "mana", "cost": 28, "cooldown": 7.0, "cast_time": 0.35, "range": 5.5, "power": 34.0, "targeting": "area_self", "tags": ["damage", "area", "fire"]},
	"frost_lance": {"school": "frost", "required_level": 6, "resource": "mana", "cost": 17, "cooldown": 1.2, "cast_time": 0.18, "range": 20.0, "power": 28.0, "targeting": "projectile", "tags": ["damage", "frost", "slow"]},
	"ice_skin": {"school": "frost", "required_level": 10, "resource": "mana", "cost": 24, "cooldown": 9.0, "cast_time": 0.30, "range": 0.0, "power": 38.0, "targeting": "self", "tags": ["defense", "frost"]},
	"thorn_grasp": {"school": "thorn", "required_level": 7, "resource": "mana", "cost": 19, "cooldown": 3.5, "cast_time": 0.22, "range": 13.0, "power": 24.0, "targeting": "single_target", "tags": ["control", "nature"]},
	"blackwood_mend": {"school": "thorn", "required_level": 9, "resource": "mana", "cost": 26, "cooldown": 8.0, "cast_time": 0.40, "range": 0.0, "power": 42.0, "targeting": "self", "tags": ["heal", "nature"]},
	"storm_spear": {"school": "storm", "required_level": 11, "resource": "mana", "cost": 24, "cooldown": 1.8, "cast_time": 0.20, "range": 22.0, "power": 36.0, "targeting": "projectile", "tags": ["damage", "storm"]},
	"wind_step": {"school": "storm", "required_level": 12, "resource": "stamina", "cost": 22, "cooldown": 5.0, "cast_time": 0.0, "range": 7.0, "power": 0.0, "targeting": "directional", "tags": ["movement", "storm"]},
	"veil_touch": {"school": "veil", "required_level": 13, "resource": "mana", "cost": 23, "cooldown": 2.6, "cast_time": 0.20, "range": 10.0, "power": 32.0, "targeting": "single_target", "tags": ["damage", "spirit"]},
	"pale_silence": {"school": "veil", "required_level": 16, "resource": "mana", "cost": 34, "cooldown": 10.0, "cast_time": 0.45, "range": 8.0, "power": 0.0, "targeting": "area_target", "tags": ["control", "spirit", "area"]}
}

static func get_spell(spell_id: String) -> Dictionary:
	var value: Variant = SPELLS.get(spell_id, {})
	if not value is Dictionary:
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["id"] = spell_id
	return result

static func get_ids() -> Array[String]:
	var result: Array[String] = []
	for key in SPELLS.keys():
		result.append(str(key))
	result.sort()
	return result

static func get_school_ids() -> Array[String]:
	var schools: Array[String] = []
	for spell_id in get_ids():
		var school: String = str(get_spell(spell_id).get("school", ""))
		if not school.is_empty() and not schools.has(school):
			schools.append(school)
	schools.sort()
	return schools

static func validate_spell(spell: Dictionary) -> bool:
	var targeting: String = str(spell.get("targeting", ""))
	return not str(spell.get("id", "")).is_empty() \
		and not str(spell.get("school", "")).is_empty() \
		and int(spell.get("required_level", 0)) > 0 \
		and ["mana", "stamina"].has(str(spell.get("resource", ""))) \
		and int(spell.get("cost", 0)) > 0 \
		and float(spell.get("cooldown", -1.0)) >= 0.0 \
		and float(spell.get("cast_time", -1.0)) >= 0.0 \
		and float(spell.get("range", -1.0)) >= 0.0 \
		and float(spell.get("power", -1.0)) >= 0.0 \
		and ["projectile", "self", "area_self", "single_target", "directional", "area_target"].has(targeting) \
		and spell.get("tags", []) is Array and not (spell.get("tags", []) as Array).is_empty()

static func can_cast(spell_id: String, caster_state: Dictionary, now_ms: int) -> Dictionary:
	var spell: Dictionary = get_spell(spell_id)
	if not validate_spell(spell):
		return _denied("unknown_spell")
	if int(caster_state.get("level", 0)) < int(spell.get("required_level", 1)):
		return _denied("level_locked")
	var unlocked_value: Variant = caster_state.get("unlocked_spells", [])
	if not unlocked_value is Array or not (unlocked_value as Array).has(spell_id):
		return _denied("not_unlocked")
	var resource_name: String = str(spell.get("resource", "mana"))
	var resources: Dictionary = caster_state.get("resources", {}) as Dictionary
	if int(resources.get(resource_name, 0)) < int(spell.get("cost", 0)):
		return _denied("insufficient_resource")
	var cooldowns: Dictionary = caster_state.get("cooldowns", {}) as Dictionary
	var ready_at_ms: int = int(cooldowns.get(spell_id, 0))
	if now_ms < ready_at_ms:
		return {"allowed": false, "reason": "cooldown", "ready_at_ms": ready_at_ms}
	return {"allowed": true, "reason": "", "ready_at_ms": now_ms}

static func build_cast_command(spell_id: String, caster_state: Dictionary, now_ms: int, sequence: int, target: Dictionary = {}) -> Dictionary:
	var gate: Dictionary = can_cast(spell_id, caster_state, now_ms)
	if not bool(gate.get("allowed", false)):
		return {"accepted": false, "reason": str(gate.get("reason", "denied")), "command": {}}
	var spell: Dictionary = get_spell(spell_id)
	var caster_id: String = str(caster_state.get("player_id", ""))
	if caster_id.is_empty() or sequence < 0:
		return {"accepted": false, "reason": "invalid_caster_sequence", "command": {}}
	if not _target_contract_valid(str(spell.get("targeting", "")), target):
		return {"accepted": false, "reason": "invalid_target_contract", "command": {}}
	var cooldown_ms: int = roundi(float(spell.get("cooldown", 0.0)) * 1000.0)
	var command_id: String = "cast:%s:%d:%s" % [caster_id.trim_prefix("player:"), sequence, spell_id]
	return {
		"accepted": true,
		"reason": "",
		"command": {
			"format_version": FORMAT_VERSION,
			"command_id": command_id,
			"caster_id": caster_id,
			"spell_id": spell_id,
			"school": str(spell.get("school", "")),
			"resource": str(spell.get("resource", "")),
			"resource_cost": int(spell.get("cost", 0)),
			"issued_at_ms": now_ms,
			"ready_at_ms": now_ms + cooldown_ms,
			"cast_time_ms": roundi(float(spell.get("cast_time", 0.0)) * 1000.0),
			"targeting": str(spell.get("targeting", "")),
			"target": target.duplicate(true),
			"range": float(spell.get("range", 0.0)),
			"power": float(spell.get("power", 0.0)),
			"tags": (spell.get("tags", []) as Array).duplicate()
		}
	}

static func apply_cast_cost(command: Dictionary, caster_state: Dictionary) -> Dictionary:
	var result: Dictionary = caster_state.duplicate(true)
	var resources: Dictionary = result.get("resources", {}) as Dictionary
	var cooldowns: Dictionary = result.get("cooldowns", {}) as Dictionary
	var resource_name: String = str(command.get("resource", ""))
	var cost: int = int(command.get("resource_cost", 0))
	resources[resource_name] = maxi(0, int(resources.get(resource_name, 0)) - cost)
	cooldowns[str(command.get("spell_id", ""))] = int(command.get("ready_at_ms", 0))
	result["resources"] = resources
	result["cooldowns"] = cooldowns
	return result

static func _target_contract_valid(targeting: String, target: Dictionary) -> bool:
	match targeting:
		"self", "area_self":
			return target.is_empty() or str(target.get("type", "self")) == "self"
		"projectile", "directional":
			return target.has("direction") and target.get("direction") is Vector3 and (target.get("direction") as Vector3).length_squared() > 0.001
		"single_target":
			return not str(target.get("entity_id", "")).is_empty()
		"area_target":
			return target.has("position") and target.get("position") is Vector3
		_:
			return false

static func _denied(reason: String) -> Dictionary:
	return {"allowed": false, "reason": reason, "ready_at_ms": 0}
