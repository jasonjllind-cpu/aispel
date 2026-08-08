extends RefCounted
class_name CampaignProgressionCatalog

const FORMAT_VERSION: int = 1
const QUESTS := preload("res://scripts/progression/quest_chain_catalog.gd")

const MILESTONES: Dictionary = {
	"campaign:frontier_oath": {
		"chapter": 1,
		"requires_all": ["quest:frontier_oath:frontier_crypt"],
		"requires_any": [],
		"next": ["campaign:blackwood_pact"],
		"rewards": ["campaign_reward:chapter_1_complete"]
	},
	"campaign:blackwood_pact": {
		"chapter": 2,
		"requires_all": ["campaign:frontier_oath", "quest:blackwood_pact:blackwood_root_crypt"],
		"requires_any": [],
		"next": ["campaign:convergence"],
		"rewards": ["campaign_reward:chapter_2_complete"]
	},
	"campaign:convergence": {
		"chapter": 3,
		"requires_all": ["campaign:blackwood_pact"],
		"requires_any": ["world_milestone:windscar_beacon", "world_milestone:veilmoor_pale_ring"],
		"next": ["campaign:endgame_unlocked"],
		"rewards": ["campaign_reward:convergence_complete"]
	},
	"campaign:endgame_unlocked": {
		"chapter": 4,
		"requires_all": ["campaign:convergence", "dungeon_milestone:three_guardians_defeated"],
		"requires_any": [],
		"next": ["campaign:ending_moon", "campaign:ending_veil"],
		"rewards": ["campaign_reward:endgame_access"]
	},
	"campaign:ending_moon": {
		"chapter": 5,
		"requires_all": ["campaign:endgame_unlocked"],
		"requires_any": ["choice:moon_oath", "magic_mastery:moon"],
		"next": [],
		"ending_id": "ending:moon_restored",
		"rewards": ["campaign_reward:victory_moon"]
	},
	"campaign:ending_veil": {
		"chapter": 5,
		"requires_all": ["campaign:endgame_unlocked"],
		"requires_any": ["choice:veil_bargain", "magic_mastery:veil"],
		"next": [],
		"ending_id": "ending:veil_bound",
		"rewards": ["campaign_reward:victory_veil"]
	}
}

static func milestone_ids() -> Array[String]:
	var result: Array[String] = []
	for milestone_id in MILESTONES.keys():
		result.append(str(milestone_id))
	result.sort()
	return result

static func get_milestone(milestone_id: String) -> Dictionary:
	if not MILESTONES.has(milestone_id):
		return {}
	var result: Dictionary = (MILESTONES[milestone_id] as Dictionary).duplicate(true)
	result["id"] = milestone_id
	return result

static func available_milestones(completed_ids: Array[String], world_state_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var state: Dictionary = _state_index(completed_ids, world_state_ids)
	for milestone_id in milestone_ids():
		if completed_ids.has(milestone_id):
			continue
		if requirements_met(milestone_id, state):
			result.append(milestone_id)
	result.sort()
	return result

static func requirements_met(milestone_id: String, state_index: Dictionary) -> bool:
	var milestone: Dictionary = get_milestone(milestone_id)
	if milestone.is_empty():
		return false
	for requirement in milestone.get("requires_all", []) as Array:
		if not bool(state_index.get(str(requirement), false)):
			return false
	var any_requirements: Array = milestone.get("requires_any", []) as Array
	if not any_requirements.is_empty():
		var matched: bool = false
		for requirement in any_requirements:
			if bool(state_index.get(str(requirement), false)):
				matched = true
				break
		if not matched:
			return false
	return true

static func completion_event(milestone_id: String, sequence: int) -> Dictionary:
	var milestone: Dictionary = get_milestone(milestone_id)
	if milestone.is_empty() or sequence < 0:
		return {}
	return {
		"format_version": FORMAT_VERSION,
		"event_id": "campaign_complete:%s:%d" % [milestone_id.trim_prefix("campaign:"), sequence],
		"milestone_id": milestone_id,
		"chapter": int(milestone.get("chapter", 0)),
		"ending_id": str(milestone.get("ending_id", "")),
		"reward_ids": (milestone.get("rewards", []) as Array).duplicate(),
		"sequence": sequence
	}

static func ending_ids() -> Array[String]:
	var result: Array[String] = []
	for milestone_id in milestone_ids():
		var ending_id: String = str(get_milestone(milestone_id).get("ending_id", ""))
		if not ending_id.is_empty():
			result.append(ending_id)
	result.sort()
	return result

static func validate_catalog() -> Dictionary:
	var errors: Array[String] = []
	var known_quest_ids: Dictionary = _known_quest_progression_ids()
	for milestone_id in milestone_ids():
		var milestone: Dictionary = get_milestone(milestone_id)
		if not milestone_id.begins_with("campaign:"):
			errors.append("invalid campaign id: %s" % milestone_id)
		if int(milestone.get("chapter", 0)) <= 0:
			errors.append("invalid chapter: %s" % milestone_id)
		for next_id in milestone.get("next", []) as Array:
			if not MILESTONES.has(str(next_id)):
				errors.append("missing next milestone %s -> %s" % [milestone_id, str(next_id)])
		for key in ["requires_all", "requires_any"]:
			for requirement in milestone.get(key, []) as Array:
				var requirement_id: String = str(requirement)
				if requirement_id.begins_with("campaign:") and not MILESTONES.has(requirement_id):
					errors.append("missing campaign prerequisite %s -> %s" % [milestone_id, requirement_id])
				if requirement_id.begins_with("quest:") and not known_quest_ids.has(requirement_id):
					errors.append("missing quest prerequisite %s -> %s" % [milestone_id, requirement_id])
		for reward in milestone.get("rewards", []) as Array:
			if not str(reward).begins_with("campaign_reward:"):
				errors.append("invalid campaign reward: %s" % str(reward))
	if _has_cycle():
		errors.append("campaign milestone graph contains cycle")
	var endings: Array[String] = ending_ids()
	if endings.size() < 2:
		errors.append("campaign requires at least two ending routes")
	return {"valid": errors.is_empty(), "errors": errors}

static func _known_quest_progression_ids() -> Dictionary:
	var result: Dictionary = {}
	for chain_id in QUESTS.get_chain_ids():
		var chain: Dictionary = QUESTS.get_chain(chain_id)
		for node_id in (chain.get("nodes", {}) as Dictionary).keys():
			var node: Dictionary = QUESTS.get_node(chain_id, str(node_id))
			result[str(node.get("progression_id", ""))] = true
	return result

static func _state_index(completed_ids: Array[String], world_state_ids: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for value in completed_ids:
		result[value] = true
	for value in world_state_ids:
		result[value] = true
	return result

static func _has_cycle() -> bool:
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	for milestone_id in milestone_ids():
		if _visit_cycle(milestone_id, visiting, visited):
			return true
	return false

static func _visit_cycle(milestone_id: String, visiting: Dictionary, visited: Dictionary) -> bool:
	if bool(visiting.get(milestone_id, false)):
		return true
	if bool(visited.get(milestone_id, false)):
		return false
	visiting[milestone_id] = true
	for next_id in get_milestone(milestone_id).get("next", []) as Array:
		if _visit_cycle(str(next_id), visiting, visited):
			return true
	visiting.erase(milestone_id)
	visited[milestone_id] = true
	return false
