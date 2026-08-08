extends RefCounted
class_name EndgameRelicObjectives

const FORMAT_VERSION: int = 1

const OBJECTIVES: Dictionary = {
	"endgame_objective:moon_key": {
		"item_id": "relic:moon_key",
		"display_name": "Moon Key",
		"preferred_band": "mid",
		"lore_role": "moon"
	},
	"endgame_objective:veil_key": {
		"item_id": "relic:veil_key",
		"display_name": "Veil Key",
		"preferred_band": "late",
		"lore_role": "veil"
	},
	"endgame_objective:ashen_seal": {
		"item_id": "relic:ashen_seal",
		"display_name": "Ashen Seal",
		"preferred_band": "late",
		"lore_role": "guardian"
	}
}

static func objective_ids() -> Array[String]:
	var result: Array[String] = []
	for objective_id in OBJECTIVES.keys():
		result.append(str(objective_id))
	result.sort()
	return result

static func get_objective(objective_id: String) -> Dictionary:
	if not OBJECTIVES.has(objective_id):
		return {}
	var result: Dictionary = (OBJECTIVES[objective_id] as Dictionary).duplicate(true)
	result["objective_id"] = objective_id
	return result

static func build_plan(graph: Dictionary, access_plan: Dictionary) -> Dictionary:
	var nodes_value: Variant = graph.get("nodes", [])
	if not nodes_value is Array:
		return {}
	var final_region: String = _region_for_role(access_plan, "final_reach")
	var candidates: Array[Dictionary] = []
	for value in nodes_value as Array:
		if not value is Dictionary:
			continue
		var node: Dictionary = value as Dictionary
		var region_id: String = str(node.get("stable_id", ""))
		if not region_id.begins_with("region:") or region_id == final_region:
			continue
		candidates.append(node.duplicate(true))
	if candidates.size() < OBJECTIVES.size():
		return {}
	candidates.sort_custom(_candidate_less)

	var world_seed: int = int(graph.get("world_seed", 0))
	var used_regions: Dictionary = {}
	var assignments: Array[Dictionary] = []
	for objective_id in objective_ids():
		var definition: Dictionary = get_objective(objective_id)
		var chosen: Dictionary = _choose_candidate(candidates, used_regions, str(definition.get("preferred_band", "")), world_seed, objective_id)
		if chosen.is_empty():
			return {}
		var region_id: String = str(chosen.get("stable_id", ""))
		used_regions[region_id] = true
		assignments.append({
			"objective_id": objective_id,
			"item_id": str(definition.get("item_id", "")),
			"region_id": region_id,
			"graph_depth": int(chosen.get("graph_depth", 0)),
			"progression_band": str(chosen.get("progression_band", "")),
			"placement_id": "endgame_relic_placement:%s:%s" % [objective_id.trim_prefix("endgame_objective:"), region_id.trim_prefix("region:").replace(":", "_")]
		})
	assignments.sort_custom(_assignment_less)
	return {
		"format_version": FORMAT_VERSION,
		"plan_id": "endgame_relic_plan:%d:%d" % [world_seed, int(graph.get("format_version", 0))],
		"world_seed": world_seed,
		"final_region_id": final_region,
		"assignments": assignments
	}

static func validate_plan(plan: Dictionary) -> bool:
	if int(plan.get("format_version", -1)) != FORMAT_VERSION:
		return false
	if not str(plan.get("plan_id", "")).begins_with("endgame_relic_plan:"):
		return false
	var assignments_value: Variant = plan.get("assignments", [])
	if not assignments_value is Array:
		return false
	var assignments: Array = assignments_value as Array
	if assignments.size() != OBJECTIVES.size():
		return false
	var seen_objectives: Dictionary = {}
	var seen_regions: Dictionary = {}
	for value in assignments:
		if not value is Dictionary:
			return false
		var assignment: Dictionary = value as Dictionary
		var objective_id: String = str(assignment.get("objective_id", ""))
		var region_id: String = str(assignment.get("region_id", ""))
		if not OBJECTIVES.has(objective_id) or seen_objectives.has(objective_id):
			return false
		if not region_id.begins_with("region:") or seen_regions.has(region_id):
			return false
		if region_id == str(plan.get("final_region_id", "")):
			return false
		if str(assignment.get("item_id", "")) != str(get_objective(objective_id).get("item_id", "")):
			return false
		seen_objectives[objective_id] = true
		seen_regions[region_id] = true
	return true

static func create_state(plan: Dictionary) -> Dictionary:
	if not validate_plan(plan):
		return {}
	return {
		"format_version": FORMAT_VERSION,
		"plan_id": str(plan.get("plan_id", "")),
		"revision": 0,
		"acquired_objective_ids": [],
		"acquisition_events": []
	}

static func validate_state(state: Dictionary, plan: Dictionary) -> bool:
	if not validate_plan(plan) or int(state.get("format_version", -1)) != FORMAT_VERSION:
		return false
	if str(state.get("plan_id", "")) != str(plan.get("plan_id", "")) or int(state.get("revision", -1)) < 0:
		return false
	var acquired_value: Variant = state.get("acquired_objective_ids", [])
	var events_value: Variant = state.get("acquisition_events", [])
	if not acquired_value is Array or not events_value is Array:
		return false
	var seen: Dictionary = {}
	for value in acquired_value as Array:
		var objective_id: String = str(value)
		if not OBJECTIVES.has(objective_id) or seen.has(objective_id):
			return false
		seen[objective_id] = true
	return not _has_duplicates(events_value as Array)

static func acquire(state: Dictionary, plan: Dictionary, objective_id: String, source_region_id: String, sequence: int) -> Dictionary:
	var result: Dictionary = {"accepted": false, "reason": "invalid_state", "state": state.duplicate(true), "event": {}}
	if not validate_state(state, plan):
		return result
	var assignment: Dictionary = assignment_for_objective(plan, objective_id)
	if assignment.is_empty():
		result["reason"] = "unknown_objective"
		return result
	if str(assignment.get("region_id", "")) != source_region_id:
		result["reason"] = "wrong_region"
		return result
	var acquired: Array = state.get("acquired_objective_ids", []) as Array
	if acquired.has(objective_id):
		result["reason"] = "already_acquired"
		return result
	if sequence < 0:
		result["reason"] = "invalid_sequence"
		return result
	var next: Dictionary = state.duplicate(true)
	var next_acquired: Array = next.get("acquired_objective_ids", []) as Array
	next_acquired.append(objective_id)
	next_acquired.sort()
	next["acquired_objective_ids"] = next_acquired
	var event_id: String = "endgame_relic_acquired:%s:%d" % [objective_id.trim_prefix("endgame_objective:"), sequence]
	var events: Array = next.get("acquisition_events", []) as Array
	events.append(event_id)
	events.sort()
	next["acquisition_events"] = events
	next["revision"] = int(next.get("revision", 0)) + 1
	result["accepted"] = true
	result["reason"] = ""
	result["state"] = next
	result["event"] = {
		"format_version": FORMAT_VERSION,
		"event_id": event_id,
		"objective_id": objective_id,
		"item_id": str(assignment.get("item_id", "")),
		"region_id": source_region_id,
		"sequence": sequence
	}
	return result

static func endgame_ready(state: Dictionary, plan: Dictionary) -> bool:
	if not validate_state(state, plan):
		return false
	var acquired: Array = state.get("acquired_objective_ids", []) as Array
	for objective_id in objective_ids():
		if not acquired.has(objective_id):
			return false
	return true

static func missing_objectives(state: Dictionary, plan: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if not validate_state(state, plan):
		return objective_ids()
	var acquired: Array = state.get("acquired_objective_ids", []) as Array
	for objective_id in objective_ids():
		if not acquired.has(objective_id):
			result.append(objective_id)
	return result

static func recovery_grants(state: Dictionary, plan: Dictionary, inventory: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not validate_state(state, plan):
		return result
	var acquired: Array = state.get("acquired_objective_ids", []) as Array
	for objective_id in acquired:
		var assignment: Dictionary = assignment_for_objective(plan, str(objective_id))
		if assignment.is_empty():
			continue
		var item_id: String = str(assignment.get("item_id", ""))
		if int(inventory.get(item_id, 0)) > 0:
			continue
		result.append({
			"recovery_id": "endgame_recovery:%s" % str(objective_id).trim_prefix("endgame_objective:"),
			"objective_id": str(objective_id),
			"item_id": item_id,
			"amount": 1
		})
	result.sort_custom(_recovery_less)
	return result

static func assignment_for_objective(plan: Dictionary, objective_id: String) -> Dictionary:
	for value in plan.get("assignments", []) as Array:
		if value is Dictionary and str((value as Dictionary).get("objective_id", "")) == objective_id:
			return (value as Dictionary).duplicate(true)
	return {}

static func _region_for_role(access_plan: Dictionary, role: String) -> String:
	for value in access_plan.get("assignments", []) as Array:
		if value is Dictionary and str((value as Dictionary).get("role", "")) == role:
			return str((value as Dictionary).get("region_id", ""))
	return ""

static func _choose_candidate(candidates: Array[Dictionary], used_regions: Dictionary, preferred_band: String, world_seed: int, objective_id: String) -> Dictionary:
	var preferred: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	for candidate in candidates:
		var region_id: String = str(candidate.get("stable_id", ""))
		if used_regions.has(region_id):
			continue
		fallback.append(candidate)
		if str(candidate.get("progression_band", "")) == preferred_band:
			preferred.append(candidate)
	var pool: Array[Dictionary] = preferred if not preferred.is_empty() else fallback
	if pool.is_empty():
		return {}
	var index: int = int(abs(("%d:%s" % [world_seed, objective_id]).hash())) % pool.size()
	return pool[index].duplicate(true)

static func _candidate_less(a: Dictionary, b: Dictionary) -> bool:
	var depth_a: int = int(a.get("graph_depth", 0))
	var depth_b: int = int(b.get("graph_depth", 0))
	if depth_a == depth_b:
		return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
	return depth_a < depth_b

static func _assignment_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("objective_id", "")) < str(b.get("objective_id", ""))

static func _recovery_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("recovery_id", "")) < str(b.get("recovery_id", ""))

static func _has_duplicates(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var key: String = str(value)
		if seen.has(key):
			return true
		seen[key] = true
	return false
