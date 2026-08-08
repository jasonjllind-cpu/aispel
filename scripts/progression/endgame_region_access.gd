extends RefCounted
class_name EndgameRegionAccess

const FORMAT_VERSION: int = 1
const CAMPAIGN := preload("res://scripts/progression/campaign_progression_catalog.gd")

const ROLE_REQUIREMENTS: Dictionary = {
	"convergence_gate": {
		"campaign_all": ["campaign:convergence"],
		"world_any": ["world_milestone:windscar_beacon", "world_milestone:veilmoor_pale_ring"]
	},
	"guardian_reach": {
		"campaign_all": ["campaign:convergence"],
		"world_any": ["dungeon_milestone:one_guardian_defeated", "dungeon_milestone:two_guardians_defeated", "dungeon_milestone:three_guardians_defeated"]
	},
	"final_reach": {
		"campaign_all": ["campaign:endgame_unlocked"],
		"world_any": ["dungeon_milestone:three_guardians_defeated"]
	}
}

static func build_access_plan(graph: Dictionary) -> Dictionary:
	var nodes_value: Variant = graph.get("nodes", [])
	if not nodes_value is Array:
		return {}
	var nodes: Array = nodes_value as Array
	if nodes.size() < 3:
		return {}
	var candidates: Array[Dictionary] = []
	for value in nodes:
		if not value is Dictionary:
			continue
		var node: Dictionary = value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		var depth: int = int(node.get("graph_depth", -1))
		if stable_id.is_empty() or depth < 0:
			continue
		candidates.append(node)
	if candidates.size() < 3:
		return {}
	candidates.sort_custom(_deeper_then_id)

	var final_node: Dictionary = candidates[0]
	var guardian_node: Dictionary = _pick_distinct(candidates, [str(final_node.get("stable_id", ""))], 1)
	if guardian_node.is_empty():
		return {}
	var convergence_node: Dictionary = _pick_distinct(candidates, [str(final_node.get("stable_id", "")), str(guardian_node.get("stable_id", ""))], 2)
	if convergence_node.is_empty():
		return {}

	var assignments: Array[Dictionary] = [
		_assignment("convergence_gate", convergence_node),
		_assignment("guardian_reach", guardian_node),
		_assignment("final_reach", final_node)
	]
	assignments.sort_custom(_assignment_less)
	return {
		"format_version": FORMAT_VERSION,
		"world_seed": int(graph.get("world_seed", 0)),
		"graph_format_version": int(graph.get("format_version", 0)),
		"plan_id": "endgame_access:%d:%d" % [int(graph.get("world_seed", 0)), int(graph.get("format_version", 0))],
		"assignments": assignments
	}

static func evaluate_region(plan: Dictionary, region_id: String, completed_campaign: Array[String], world_milestones: Array[String]) -> Dictionary:
	if not validate_plan(plan):
		return _decision(region_id, "", false, "invalid_plan", [])
	var assignment: Dictionary = assignment_for_region(plan, region_id)
	if assignment.is_empty():
		return _decision(region_id, "open_world", true, "", [])
	var role: String = str(assignment.get("role", ""))
	var definition: Dictionary = ROLE_REQUIREMENTS.get(role, {}) as Dictionary
	var missing: Array[String] = []
	for requirement in definition.get("campaign_all", []) as Array:
		var requirement_id: String = str(requirement)
		if not completed_campaign.has(requirement_id):
			missing.append(requirement_id)
	var world_any: Array = definition.get("world_any", []) as Array
	if not world_any.is_empty():
		var matched: bool = false
		for requirement in world_any:
			if world_milestones.has(str(requirement)):
				matched = true
				break
		if not matched:
			for requirement in world_any:
				missing.append(str(requirement))
	var allowed: bool = missing.is_empty()
	return _decision(region_id, role, allowed, "" if allowed else "progression_locked", missing)

static func assignment_for_region(plan: Dictionary, region_id: String) -> Dictionary:
	for value in plan.get("assignments", []) as Array:
		if value is Dictionary and str((value as Dictionary).get("region_id", "")) == region_id:
			return (value as Dictionary).duplicate(true)
	return {}

static func region_for_role(plan: Dictionary, role: String) -> String:
	for value in plan.get("assignments", []) as Array:
		if value is Dictionary and str((value as Dictionary).get("role", "")) == role:
			return str((value as Dictionary).get("region_id", ""))
	return ""

static func validate_plan(plan: Dictionary) -> bool:
	if int(plan.get("format_version", -1)) != FORMAT_VERSION:
		return false
	if not str(plan.get("plan_id", "")).begins_with("endgame_access:"):
		return false
	var assignments_value: Variant = plan.get("assignments", [])
	if not assignments_value is Array:
		return false
	var assignments: Array = assignments_value as Array
	if assignments.size() != ROLE_REQUIREMENTS.size():
		return false
	var roles: Dictionary = {}
	var regions: Dictionary = {}
	for value in assignments:
		if not value is Dictionary:
			return false
		var assignment: Dictionary = value as Dictionary
		var role: String = str(assignment.get("role", ""))
		var region_id: String = str(assignment.get("region_id", ""))
		if not ROLE_REQUIREMENTS.has(role) or roles.has(role):
			return false
		if not region_id.begins_with("region:") or regions.has(region_id):
			return false
		if int(assignment.get("graph_depth", -1)) < 0:
			return false
		roles[role] = true
		regions[region_id] = true
	return true

static func campaign_contract_valid() -> bool:
	for role in ROLE_REQUIREMENTS.keys():
		var definition: Dictionary = ROLE_REQUIREMENTS[role] as Dictionary
		for campaign_id in definition.get("campaign_all", []) as Array:
			if CAMPAIGN.get_milestone(str(campaign_id)).is_empty():
				return false
	return true

static func _assignment(role: String, node: Dictionary) -> Dictionary:
	return {
		"access_id": "region_access:%s:%s" % [role, str(node.get("stable_id", "")).trim_prefix("region:").replace(":", "_")],
		"role": role,
		"region_id": str(node.get("stable_id", "")),
		"graph_depth": int(node.get("graph_depth", -1)),
		"progression_band": str(node.get("progression_band", "")),
		"biome": str(node.get("biome", ""))
	}

static func _pick_distinct(candidates: Array[Dictionary], excluded_ids: Array[String], preferred_offset: int) -> Dictionary:
	var offset: int = clampi(preferred_offset, 0, maxi(0, candidates.size() - 1))
	for index in range(offset, candidates.size()):
		var candidate: Dictionary = candidates[index]
		if not excluded_ids.has(str(candidate.get("stable_id", ""))):
			return candidate
	for candidate in candidates:
		if not excluded_ids.has(str(candidate.get("stable_id", ""))):
			return candidate
	return {}

static func _decision(region_id: String, role: String, allowed: bool, reason: String, missing: Array[String]) -> Dictionary:
	missing.sort()
	return {
		"format_version": FORMAT_VERSION,
		"decision_id": "access_decision:%s:%s" % [region_id.trim_prefix("region:").replace(":", "_"), role],
		"region_id": region_id,
		"role": role,
		"allowed": allowed,
		"reason": reason,
		"missing_requirements": missing
	}

static func _deeper_then_id(a: Dictionary, b: Dictionary) -> bool:
	var depth_a: int = int(a.get("graph_depth", -1))
	var depth_b: int = int(b.get("graph_depth", -1))
	if depth_a == depth_b:
		return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
	return depth_a > depth_b

static func _assignment_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("role", "")) < str(b.get("role", ""))
