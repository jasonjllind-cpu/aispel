extends RefCounted
class_name BossProgressionState

const FORMAT_VERSION: int = 1

const TIERS: Dictionary = {
	"guardian": {"rank": 1, "required_guardians": 0, "reward_kind": "guardian"},
	"arch_guardian": {"rank": 2, "required_guardians": 1, "reward_kind": "guardian"},
	"final_boss": {"rank": 3, "required_guardians": 3, "reward_kind": "ending_gate"}
}

static func build_guardian_contract(region_id: String, dungeon_id: String, guardian_index: int, biome: String) -> Dictionary:
	if not region_id.begins_with("region:") or not dungeon_id.begins_with("dungeon:") or guardian_index < 0 or guardian_index > 2:
		return {}
	var tier: String = "guardian" if guardian_index == 0 else "arch_guardian"
	var boss_id: String = "boss:guardian:%s:%d" % [region_id.trim_prefix("region:").replace(":", "_"), guardian_index]
	return {
		"format_version": FORMAT_VERSION,
		"boss_id": boss_id,
		"encounter_id": "boss_encounter:%s" % boss_id.trim_prefix("boss:"),
		"region_id": region_id,
		"dungeon_id": dungeon_id,
		"tier": tier,
		"tier_rank": int((TIERS[tier] as Dictionary).get("rank", 0)),
		"guardian_index": guardian_index,
		"biome": biome,
		"victory_event_id": "boss_victory:%s" % boss_id.trim_prefix("boss:"),
		"reward_id": "boss_reward:%s" % boss_id.trim_prefix("boss:")
	}

static func build_final_boss_contract(region_id: String, campaign_id: String, ending_route: String) -> Dictionary:
	if not region_id.begins_with("region:") or campaign_id != "campaign:endgame_unlocked":
		return {}
	if not ["moon", "veil"].has(ending_route):
		return {}
	var boss_id: String = "boss:final:%s" % ending_route
	return {
		"format_version": FORMAT_VERSION,
		"boss_id": boss_id,
		"encounter_id": "boss_encounter:final:%s" % ending_route,
		"region_id": region_id,
		"dungeon_id": "",
		"tier": "final_boss",
		"tier_rank": int((TIERS["final_boss"] as Dictionary).get("rank", 0)),
		"guardian_index": -1,
		"biome": "endgame",
		"campaign_id": campaign_id,
		"ending_route": ending_route,
		"victory_event_id": "boss_victory:final:%s" % ending_route,
		"reward_id": "boss_reward:final:%s" % ending_route
	}

static func create_state(player_scope_id: String = "world") -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"scope_id": player_scope_id,
		"revision": 0,
		"defeated_boss_ids": [],
		"guardian_victory_ids": [],
		"world_milestones": [],
		"victory_events": []
	}

static func build_victory_command(contract: Dictionary, sequence: int, authority_epoch: int) -> Dictionary:
	if not validate_contract(contract) or sequence < 0 or authority_epoch < 0:
		return {}
	return {
		"format_version": FORMAT_VERSION,
		"command_id": "victory_command:%s:%d" % [str(contract.get("boss_id", "")).trim_prefix("boss:").replace(":", "_"), sequence],
		"boss_id": str(contract.get("boss_id", "")),
		"victory_event_id": str(contract.get("victory_event_id", "")),
		"tier": str(contract.get("tier", "")),
		"sequence": sequence,
		"authority_epoch": authority_epoch
	}

static func apply_authoritative_victory(state: Dictionary, contract: Dictionary, command: Dictionary, is_authority: bool, expected_authority_epoch: int) -> Dictionary:
	var result: Dictionary = {"accepted": false, "reason": "invalid_state", "state": state.duplicate(true), "emitted_milestones": []}
	if not validate_state(state) or not validate_contract(contract):
		return result
	if not is_authority:
		result["reason"] = "not_authority"
		return result
	if int(command.get("format_version", -1)) != FORMAT_VERSION or str(command.get("boss_id", "")) != str(contract.get("boss_id", "")):
		result["reason"] = "contract_mismatch"
		return result
	if str(command.get("victory_event_id", "")) != str(contract.get("victory_event_id", "")):
		result["reason"] = "event_mismatch"
		return result
	if int(command.get("authority_epoch", -1)) != expected_authority_epoch:
		result["reason"] = "stale_authority_epoch"
		return result
	var defeated: Array = state.get("defeated_boss_ids", []) as Array
	var boss_id: String = str(contract.get("boss_id", ""))
	if defeated.has(boss_id):
		result["reason"] = "already_defeated"
		return result
	if str(contract.get("tier", "")) == "final_boss" and (state.get("guardian_victory_ids", []) as Array).size() < 3:
		result["reason"] = "guardian_gate"
		return result

	var next: Dictionary = state.duplicate(true)
	var next_defeated: Array = next.get("defeated_boss_ids", []) as Array
	next_defeated.append(boss_id)
	next_defeated.sort()
	next["defeated_boss_ids"] = next_defeated
	var events: Array = next.get("victory_events", []) as Array
	events.append(str(contract.get("victory_event_id", "")))
	events.sort()
	next["victory_events"] = events
	var emitted: Array[String] = []
	if ["guardian", "arch_guardian"].has(str(contract.get("tier", ""))):
		var guardians: Array = next.get("guardian_victory_ids", []) as Array
		guardians.append(str(contract.get("victory_event_id", "")))
		guardians.sort()
		next["guardian_victory_ids"] = guardians
		emitted = _guardian_milestones(guardians.size())
		var world: Array = next.get("world_milestones", []) as Array
		for milestone_id in emitted:
			if not world.has(milestone_id):
				world.append(milestone_id)
		world.sort()
		next["world_milestones"] = world
	else:
		var ending_route: String = str(contract.get("ending_route", ""))
		var final_milestone: String = "boss_milestone:final_%s_defeated" % ending_route
		emitted.append(final_milestone)
		var world: Array = next.get("world_milestones", []) as Array
		world.append(final_milestone)
		world.sort()
		next["world_milestones"] = world
	next["revision"] = int(next.get("revision", 0)) + 1
	return {"accepted": true, "reason": "", "state": next, "emitted_milestones": emitted}

static func validate_contract(contract: Dictionary) -> bool:
	var tier: String = str(contract.get("tier", ""))
	return int(contract.get("format_version", -1)) == FORMAT_VERSION \
		and str(contract.get("boss_id", "")).begins_with("boss:") \
		and str(contract.get("encounter_id", "")).begins_with("boss_encounter:") \
		and str(contract.get("region_id", "")).begins_with("region:") \
		and TIERS.has(tier) \
		and int(contract.get("tier_rank", -1)) == int((TIERS[tier] as Dictionary).get("rank", -2)) \
		and str(contract.get("victory_event_id", "")).begins_with("boss_victory:") \
		and str(contract.get("reward_id", "")).begins_with("boss_reward:")

static func validate_state(state: Dictionary) -> bool:
	if int(state.get("format_version", -1)) != FORMAT_VERSION or int(state.get("revision", -1)) < 0:
		return false
	for key in ["defeated_boss_ids", "guardian_victory_ids", "world_milestones", "victory_events"]:
		if not state.get(key, []) is Array or _has_duplicates(state.get(key, []) as Array):
			return false
	return true

static func _guardian_milestones(count: int) -> Array[String]:
	var result: Array[String] = []
	if count >= 1:
		result.append("dungeon_milestone:one_guardian_defeated")
	if count >= 2:
		result.append("dungeon_milestone:two_guardians_defeated")
	if count >= 3:
		result.append("dungeon_milestone:three_guardians_defeated")
	return result

static func _has_duplicates(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var key: String = str(value)
		if seen.has(key):
			return true
		seen[key] = true
	return false
