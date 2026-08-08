extends RefCounted
class_name EndgameSaveCodec

const CURRENT_VERSION: int = 2
const LEGACY_VERSION: int = 1
const CAMPAIGN := preload("res://scripts/progression/campaign_progression_catalog.gd")
const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")
const CHOICES := preload("res://scripts/progression/endgame_choice_consequences.gd")
const POSTGAME := preload("res://scripts/progression/postgame_world_profile.gd")

static func encode(snapshot: Dictionary, save_sequence: int = 0) -> Dictionary:
	if not validate_snapshot(snapshot):
		return {}
	var payload: Dictionary = {
		"version": CURRENT_VERSION,
		"save_sequence": maxi(0, save_sequence),
		"snapshot": snapshot.duplicate(true),
		"recovered": false
	}
	payload["checksum"] = _checksum(payload)
	return payload

static func validate(payload: Dictionary) -> bool:
	if int(payload.get("version", -1)) != CURRENT_VERSION or int(payload.get("save_sequence", -1)) < 0:
		return false
	var snapshot_value: Variant = payload.get("snapshot", {})
	if not snapshot_value is Dictionary or not validate_snapshot(snapshot_value as Dictionary):
		return false
	var checksum: int = int(payload.get("checksum", -1))
	return checksum >= 0 and checksum == _checksum(payload)

static func decode(payload: Dictionary) -> Dictionary:
	var migrated: Dictionary = migrate(payload)
	if migrated.is_empty() or not validate(migrated):
		return {}
	return (migrated.get("snapshot", {}) as Dictionary).duplicate(true)

static func migrate(payload: Dictionary) -> Dictionary:
	var version: int = int(payload.get("version", LEGACY_VERSION))
	if version == CURRENT_VERSION:
		return payload.duplicate(true) if validate(payload) else {}
	if version != LEGACY_VERSION:
		return {}
	var snapshot: Dictionary = _legacy_snapshot(payload)
	if not validate_snapshot(snapshot):
		return {}
	var migrated: Dictionary = {
		"version": CURRENT_VERSION,
		"save_sequence": maxi(0, int(payload.get("save_sequence", 0))),
		"snapshot": snapshot,
		"recovered": false,
		"migrated_from": LEGACY_VERSION
	}
	migrated["checksum"] = _checksum(migrated)
	return migrated

static func recover(payload: Dictionary, baseline_snapshot: Dictionary, recovery_sequence: int) -> Dictionary:
	var migrated: Dictionary = migrate(payload)
	if not migrated.is_empty() and validate(migrated):
		return migrated
	if not validate_snapshot(baseline_snapshot):
		return {}
	var recovered: Dictionary = {
		"version": CURRENT_VERSION,
		"save_sequence": maxi(0, recovery_sequence),
		"snapshot": baseline_snapshot.duplicate(true),
		"recovered": true,
		"recovery_reason": _recovery_reason(payload)
	}
	recovered["checksum"] = _checksum(recovered)
	return recovered

static func build_legacy_v1(snapshot: Dictionary, save_sequence: int = 0) -> Dictionary:
	if not validate_snapshot(snapshot):
		return {}
	return {
		"version": LEGACY_VERSION,
		"save_sequence": maxi(0, save_sequence),
		"campaign_ids": (snapshot.get("completed_campaign", []) as Array).duplicate(),
		"world_ids": (snapshot.get("world_milestones", []) as Array).duplicate(),
		"bosses": (snapshot.get("boss_state", {}) as Dictionary).duplicate(true),
		"relic_plan": (snapshot.get("relic_plan", {}) as Dictionary).duplicate(true),
		"relics": (snapshot.get("relic_state", {}) as Dictionary).duplicate(true),
		"choices": (snapshot.get("choice_state", {}) as Dictionary).duplicate(true)
	}

static func validate_snapshot(snapshot: Dictionary) -> bool:
	var completed_value: Variant = snapshot.get("completed_campaign", [])
	var world_value: Variant = snapshot.get("world_milestones", [])
	var boss_value: Variant = snapshot.get("boss_state", {})
	var plan_value: Variant = snapshot.get("relic_plan", {})
	var relic_value: Variant = snapshot.get("relic_state", {})
	var choice_value: Variant = snapshot.get("choice_state", {})
	var postgame_value: Variant = snapshot.get("postgame_profile", {})
	if not completed_value is Array or not world_value is Array or not boss_value is Dictionary or not plan_value is Dictionary or not relic_value is Dictionary or not choice_value is Dictionary or not postgame_value is Dictionary:
		return false
	if _has_duplicates(completed_value as Array) or _has_duplicates(world_value as Array):
		return false
	for milestone in completed_value as Array:
		if CAMPAIGN.get_milestone(str(milestone)).is_empty():
			return false
	var normalized_boss: Dictionary = BOSSES.normalize_state(boss_value)
	if normalized_boss != boss_value:
		return false
	if not RELICS.validate_plan(plan_value as Dictionary) or not RELICS.validate_state(relic_value as Dictionary, plan_value as Dictionary):
		return false
	if not CHOICES.validate_state(choice_value as Dictionary):
		return false
	if not (postgame_value as Dictionary).is_empty() and not POSTGAME.validate_profile(postgame_value as Dictionary):
		return false
	return true

static func _legacy_snapshot(payload: Dictionary) -> Dictionary:
	var campaign_value: Variant = payload.get("campaign_ids", [])
	var world_value: Variant = payload.get("world_ids", [])
	var boss_value: Variant = payload.get("bosses", {})
	var plan_value: Variant = payload.get("relic_plan", {})
	var relic_value: Variant = payload.get("relics", {})
	var choice_value: Variant = payload.get("choices", {})
	if not campaign_value is Array or not world_value is Array or not boss_value is Dictionary or not plan_value is Dictionary or not relic_value is Dictionary or not choice_value is Dictionary:
		return {}
	return {
		"completed_campaign": (campaign_value as Array).duplicate(),
		"world_milestones": (world_value as Array).duplicate(),
		"boss_state": BOSSES.normalize_state(boss_value),
		"relic_plan": (plan_value as Dictionary).duplicate(true),
		"relic_state": (relic_value as Dictionary).duplicate(true),
		"choice_state": (choice_value as Dictionary).duplicate(true),
		"postgame_profile": {}
	}

static func _checksum(payload: Dictionary) -> int:
	var canonical: Dictionary = payload.duplicate(true)
	canonical.erase("checksum")
	return int(var_to_str(canonical).hash() & 0x7fffffff)

static func _recovery_reason(payload: Dictionary) -> String:
	if payload.is_empty():
		return "missing_payload"
	var version: int = int(payload.get("version", -1))
	if version != CURRENT_VERSION and version != LEGACY_VERSION:
		return "unsupported_version"
	if version == CURRENT_VERSION and int(payload.get("checksum", -1)) != _checksum(payload):
		return "checksum_mismatch"
	return "invalid_payload"

static func _has_duplicates(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var key: String = str(value)
		if seen.has(key):
			return true
		seen[key] = true
	return false
