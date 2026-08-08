extends RefCounted
class_name BossProgressionContract

const FORMAT_VERSION: int = 1
const STATE_ID: String = "progression:boss_victories"

const BOSSES: Dictionary = {
	"hollow_king": {
		"title": "The Hollow King",
		"role": "guardian",
		"tier": 1,
		"requires_campaign": ["campaign:convergence"],
		"requires_world": [],
		"victory_flag": "boss_milestone:hollow_king_defeated"
	},
	"blackroot_matriarch": {
		"title": "The Blackroot Matriarch",
		"role": "guardian",
		"tier": 1,
		"requires_campaign": ["campaign:convergence"],
		"requires_world": [],
		"victory_flag": "boss_milestone:blackroot_matriarch_defeated"
	},
	"stormbound_titan": {
		"title": "The Stormbound Titan",
		"role": "guardian",
		"tier": 2,
		"requires_campaign": ["campaign:convergence"],
		"requires_world": ["dungeon_milestone:one_guardian_defeated"],
		"victory_flag": "boss_milestone:stormbound_titan_defeated"
	},
	"pale_abbess": {
		"title": "The Pale Abbess",
		"role": "guardian",
		"tier": 2,
		"requires_campaign": ["campaign:convergence"],
		"requires_world": ["dungeon_milestone:one_guardian_defeated"],
		"victory_flag": "boss_milestone:pale_abbess_defeated"
	},
	"frostbound_wyrm": {
		"title": "The Frostbound Wyrm",
		"role": "guardian",
		"tier": 3,
		"requires_campaign": ["campaign:convergence"],
		"requires_world": ["dungeon_milestone:two_guardians_defeated"],
		"victory_flag": "boss_milestone:frostbound_wyrm_defeated"
	},
	"ashen_saint": {
		"title": "The Ashen Saint",
		"role": "guardian",
		"tier": 3,
		"requires_campaign": ["campaign:convergence"],
		"requires_world": ["dungeon_milestone:two_guardians_defeated"],
		"victory_flag": "boss_milestone:ashen_saint_defeated"
	},
	"eclipsed_regent": {
		"title": "The Eclipsed Regent",
		"role": "final",
		"tier": 4,
		"requires_campaign": ["campaign:endgame_unlocked"],
		"requires_world": ["dungeon_milestone:three_guardians_defeated"],
		"victory_flag": "boss_milestone:final_victory"
	}
}

static func boss_ids() -> Array[String]:
	var result: Array[String] = []
	for boss_id in BOSSES.keys():
		result.append(str(boss_id))
	result.sort()
	return result

static func get_boss(boss_id: String) -> Dictionary:
	if not BOSSES.has(boss_id):
		return {}
	var result: Dictionary = (BOSSES[boss_id] as Dictionary).duplicate(true)
	result["id"] = boss_id
	result["stable_id"] = "boss:%s" % boss_id
	return result

static func empty_state() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"state_id": STATE_ID,
		"last_sequence": 0,
		"defeated_boss_ids": [],
		"guardian_count": 0,
		"highest_guardian_tier": 0,
		"milestone_ids": [],
		"final_boss_defeated": false,
		"victory_state_id": ""
	}

static func normalize_state(value: Variant) -> Dictionary:
	var state: Dictionary = empty_state()
	if not value is Dictionary:
		return state
	var source: Dictionary = value as Dictionary
	state["last_sequence"] = maxi(0, int(source.get("last_sequence", 0)))
	state["defeated_boss_ids"] = _unique_known_boss_ids(source.get("defeated_boss_ids", []))
	state["milestone_ids"] = _unique_strings(source.get("milestone_ids", []))
	state["final_boss_defeated"] = source.get("final_boss_defeated", false) == true
	state["victory_state_id"] = str(source.get("victory_state_id", ""))
	_recalculate(state)
	return state

static func boss_access(boss_id: String, state_value: Variant, completed_campaign: Array[String], world_milestones: Array[String]) -> Dictionary:
	var boss: Dictionary = get_boss(boss_id)
	if boss.is_empty():
		return _access_decision(boss_id, false, "unknown_boss", [])
	var state: Dictionary = normalize_state(state_value)
	if (state.get("defeated_boss_ids", []) as Array).has(boss_id):
		return _access_decision(boss_id, false, "already_defeated", [])
	var missing: Array[String] = []
	for requirement in boss.get("requires_campaign", []) as Array:
		var requirement_id: String = str(requirement)
		if not completed_campaign.has(requirement_id):
			missing.append(requirement_id)
	for requirement in boss.get("requires_world", []) as Array:
		var requirement_id: String = str(requirement)
		if not world_milestones.has(requirement_id) and not (state.get("milestone_ids", []) as Array).has(requirement_id):
			missing.append(requirement_id)
	missing.sort()
	return _access_decision(boss_id, missing.is_empty(), "" if missing.is_empty() else "progression_locked", missing)

static func record_authoritative_victory(state_value: Variant, boss_id: String, authority_peer_id: int, sender_peer_id: int, sequence: int) -> Dictionary:
	var state: Dictionary = normalize_state(state_value)
	if authority_peer_id <= 0 or sender_peer_id != authority_peer_id:
		return _result(false, "not_authority", state, {})
	var boss: Dictionary = get_boss(boss_id)
	if boss.is_empty():
		return _result(false, "unknown_boss", state, {})
	if sequence <= int(state.get("last_sequence", 0)):
		return _result(false, "stale_sequence", state, {})
	var defeated: Array = state.get("defeated_boss_ids", []) as Array
	if defeated.has(boss_id):
		return _result(false, "already_defeated", state, {})

	defeated.append(boss_id)
	defeated.sort()
	state["defeated_boss_ids"] = defeated
	state["last_sequence"] = sequence
	_recalculate(state)
	var added_milestones: Array[String] = _milestones_for_victory(state, boss)
	var milestone_ids: Array = state.get("milestone_ids", []) as Array
	for milestone_id in added_milestones:
		if not milestone_ids.has(milestone_id):
			milestone_ids.append(milestone_id)
	milestone_ids.sort()
	state["milestone_ids"] = milestone_ids
	if str(boss.get("role", "")) == "final":
		state["final_boss_defeated"] = true
		state["victory_state_id"] = "victory:endgame:%s:%d" % [boss_id, sequence]

	var event: Dictionary = {
		"format_version": FORMAT_VERSION,
		"event_id": "boss_victory:%s:%d" % [boss_id, sequence],
		"boss_id": boss_id,
		"boss_stable_id": "boss:%s" % boss_id,
		"role": str(boss.get("role", "")),
		"tier": int(boss.get("tier", 0)),
		"authority_peer_id": authority_peer_id,
		"sequence": sequence,
		"victory_flag": str(boss.get("victory_flag", "")),
		"milestones_added": added_milestones.duplicate()
	}
	return _result(true, "", state, event)

static func apply_result_to_world_state(world_state: Node, result: Dictionary) -> bool:
	if world_state == null or result.get("ok", false) != true:
		return false
	if not world_state.has_method("set_entity_state") or not world_state.has_method("set_flag"):
		return false
	var state_value: Variant = result.get("state", {})
	if not state_value is Dictionary:
		return false
	var state: Dictionary = (state_value as Dictionary).duplicate(true)
	world_state.call("set_entity_state", STATE_ID, state)
	var event_value: Variant = result.get("event", {})
	if event_value is Dictionary:
		var event: Dictionary = event_value as Dictionary
		var victory_flag: String = str(event.get("victory_flag", ""))
		if not victory_flag.is_empty():
			world_state.call("set_flag", victory_flag, true)
		for milestone in event.get("milestones_added", []) as Array:
			world_state.call("set_flag", str(milestone), true)
		var victory_state_id: String = str(state.get("victory_state_id", ""))
		if not victory_state_id.is_empty():
			world_state.call("set_flag", victory_state_id, true)
	return true

static func validate_contract() -> Dictionary:
	var errors: Array[String] = []
	var guardian_tiers: Dictionary = {}
	var final_count: int = 0
	for boss_id in boss_ids():
		var boss: Dictionary = get_boss(boss_id)
		var role: String = str(boss.get("role", ""))
		var tier: int = int(boss.get("tier", 0))
		if tier <= 0:
			errors.append("invalid boss tier: %s" % boss_id)
		if role == "guardian":
			guardian_tiers[tier] = int(guardian_tiers.get(tier, 0)) + 1
		elif role == "final":
			final_count += 1
		else:
			errors.append("invalid boss role: %s" % boss_id)
		if str(boss.get("victory_flag", "")).is_empty():
			errors.append("missing victory flag: %s" % boss_id)
	if final_count != 1:
		errors.append("expected exactly one final boss")
	for tier in [1, 2, 3]:
		if int(guardian_tiers.get(tier, 0)) <= 0:
			errors.append("missing guardian tier %d" % tier)
	return {"valid": errors.is_empty(), "errors": errors}

static func _recalculate(state: Dictionary) -> void:
	var guardian_count: int = 0
	var highest_tier: int = 0
	var defeated: Array = state.get("defeated_boss_ids", []) as Array
	for boss_id_value in defeated:
		var boss: Dictionary = get_boss(str(boss_id_value))
		if str(boss.get("role", "")) == "guardian":
			guardian_count += 1
			highest_tier = maxi(highest_tier, int(boss.get("tier", 0)))
	state["guardian_count"] = guardian_count
	state["highest_guardian_tier"] = highest_tier

static func _milestones_for_victory(state: Dictionary, boss: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var victory_flag: String = str(boss.get("victory_flag", ""))
	if not victory_flag.is_empty():
		result.append(victory_flag)
	var count: int = int(state.get("guardian_count", 0))
	if count >= 1:
		result.append("dungeon_milestone:one_guardian_defeated")
	if count >= 2:
		result.append("dungeon_milestone:two_guardians_defeated")
	if count >= 3:
		result.append("dungeon_milestone:three_guardians_defeated")
	if str(boss.get("role", "")) == "final":
		result.append("campaign_milestone:final_boss_defeated")
	return _unique_strings(result)

static func _access_decision(boss_id: String, allowed: bool, reason: String, missing: Array[String]) -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"decision_id": "boss_access:%s" % boss_id,
		"boss_id": boss_id,
		"allowed": allowed,
		"reason": reason,
		"missing_requirements": missing.duplicate()
	}

static func _result(ok: bool, error: String, state: Dictionary, event: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"error": error,
		"state": state.duplicate(true),
		"event": event.duplicate(true)
	}

static func _unique_known_boss_ids(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value as Array:
			var boss_id: String = str(item)
			if BOSSES.has(boss_id) and not result.has(boss_id):
				result.append(boss_id)
	result.sort()
	return result

static func _unique_strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value as Array:
			var text: String = str(item)
			if not text.is_empty() and not result.has(text):
				result.append(text)
	result.sort()
	return result
