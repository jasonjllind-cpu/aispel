extends RefCounted
class_name QuestChainGraph

const FORMAT_VERSION: int = 1

const QUESTS: Dictionary = {
	"quest:blackwood_whispers": {
		"title": "Whispers in Blackwood",
		"prerequisites_all": [],
		"prerequisites_any": [],
		"branch_group": "",
		"objectives": [
			{"id": "objective:blackwood:discover", "type": "discover_region", "target_id": "blackwood", "required": 1}
		],
		"rewards": ["reward:quest:blackwood_complete"]
	},
	"quest:fallen_chapel_echoes": {
		"title": "Echoes of the Fallen Chapel",
		"prerequisites_all": ["quest:blackwood_whispers"],
		"prerequisites_any": [],
		"branch_group": "",
		"objectives": [
			{"id": "objective:chapel:discover", "type": "discover_location", "target_id": "fallen_chapel", "required": 1},
			{"id": "objective:chapel:relic", "type": "collect_item", "target_id": "Moon Shard", "required": 2}
		],
		"rewards": ["reward:quest:chapel_choice"]
	},
	"quest:moon_oath": {
		"title": "Oath Beneath the Moon",
		"prerequisites_all": ["quest:fallen_chapel_echoes"],
		"prerequisites_any": [],
		"branch_group": "chapel_allegiance",
		"objectives": [
			{"id": "objective:moon:shrine", "type": "activate_landmark", "target_id": "moon_shrine", "required": 1}
		],
		"rewards": ["reward:magic:moon_path"]
	},
	"quest:veil_bargain": {
		"title": "A Bargain at the Veil",
		"prerequisites_all": ["quest:fallen_chapel_echoes"],
		"prerequisites_any": [],
		"branch_group": "chapel_allegiance",
		"objectives": [
			{"id": "objective:veil:pale_ring", "type": "discover_location", "target_id": "pale_ring", "required": 1}
		],
		"rewards": ["reward:magic:veil_path"]
	},
	"quest:rekindle_beacon": {
		"title": "Rekindle the Windscar Beacon",
		"prerequisites_all": [],
		"prerequisites_any": ["quest:moon_oath", "quest:veil_bargain"],
		"branch_group": "",
		"objectives": [
			{"id": "objective:windscar:beacon", "type": "activate_landmark", "target_id": "windscar_beacon", "required": 1}
		],
		"rewards": ["reward:quest:beacon_rekindled"]
	}
}

static func get_quest(quest_id: String) -> Dictionary:
	var value: Variant = QUESTS.get(quest_id, {})
	if not value is Dictionary:
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["id"] = quest_id
	result["progression_id"] = progression_id(quest_id)
	return result

static func get_quest_ids() -> Array[String]:
	var result: Array[String] = []
	for quest_id in QUESTS.keys():
		result.append(str(quest_id))
	result.sort()
	return result

static func progression_id(quest_id: String) -> String:
	if not QUESTS.has(quest_id):
		return ""
	return "progression:%s" % quest_id

static func can_start(quest_id: String, completed: Array[String], active: Array[String] = [], branch_choices: Dictionary = {}) -> bool:
	var quest: Dictionary = get_quest(quest_id)
	if quest.is_empty() or completed.has(quest_id) or active.has(quest_id):
		return false
	for prerequisite in quest.get("prerequisites_all", []) as Array:
		if not completed.has(str(prerequisite)):
			return false
	var any_requirements: Array = quest.get("prerequisites_any", []) as Array
	if not any_requirements.is_empty():
		var any_met: bool = false
		for prerequisite in any_requirements:
			if completed.has(str(prerequisite)):
				any_met = true
				break
		if not any_met:
			return false
	var branch_group: String = str(quest.get("branch_group", ""))
	if not branch_group.is_empty():
		var chosen: String = str(branch_choices.get(branch_group, ""))
		if not chosen.is_empty() and chosen != quest_id:
			return false
	return true

static func available_quests(completed: Array[String], active: Array[String] = [], branch_choices: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	for quest_id in get_quest_ids():
		if can_start(quest_id, completed, active, branch_choices):
			result.append(quest_id)
	return result

static func choose_branch(quest_id: String, branch_choices: Dictionary) -> Dictionary:
	var result: Dictionary = branch_choices.duplicate(true)
	var quest: Dictionary = get_quest(quest_id)
	if quest.is_empty():
		return result
	var branch_group: String = str(quest.get("branch_group", ""))
	if branch_group.is_empty():
		return result
	var existing: String = str(result.get(branch_group, ""))
	if existing.is_empty() or existing == quest_id:
		result[branch_group] = quest_id
	return result

static func objective_ids(quest_id: String) -> Array[String]:
	var result: Array[String] = []
	for objective in get_quest(quest_id).get("objectives", []) as Array:
		if objective is Dictionary:
			result.append(str((objective as Dictionary).get("id", "")))
	result.sort()
	return result

static func validate_graph() -> Array[String]:
	var errors: Array[String] = []
	var ids: Array[String] = get_quest_ids()
	var objective_ids_seen: Dictionary = {}
	for quest_id in ids:
		if not quest_id.begins_with("quest:"):
			errors.append("invalid quest id: %s" % quest_id)
		var quest: Dictionary = get_quest(quest_id)
		if str(quest.get("title", "")).is_empty():
			errors.append("missing title: %s" % quest_id)
		for key in ["prerequisites_all", "prerequisites_any"]:
			for prerequisite in quest.get(key, []) as Array:
				if not QUESTS.has(str(prerequisite)):
					errors.append("unknown prerequisite %s -> %s" % [quest_id, prerequisite])
		for objective_id in objective_ids(quest_id):
			if not objective_id.begins_with("objective:"):
				errors.append("invalid objective id: %s" % objective_id)
			if objective_ids_seen.has(objective_id):
				errors.append("duplicate objective id: %s" % objective_id)
			objective_ids_seen[objective_id] = true
	if _has_cycle():
		errors.append("quest graph contains cycle")
	return errors

static func _has_cycle() -> bool:
	var indegree: Dictionary = {}
	var outgoing: Dictionary = {}
	for quest_id in get_quest_ids():
		indegree[quest_id] = 0
		outgoing[quest_id] = []
	for quest_id in get_quest_ids():
		var quest: Dictionary = get_quest(quest_id)
		var prerequisites: Array[String] = []
		for prerequisite in quest.get("prerequisites_all", []) as Array:
			prerequisites.append(str(prerequisite))
		for prerequisite in quest.get("prerequisites_any", []) as Array:
			if not prerequisites.has(str(prerequisite)):
				prerequisites.append(str(prerequisite))
		for prerequisite in prerequisites:
			indegree[quest_id] = int(indegree[quest_id]) + 1
			(outgoing[prerequisite] as Array).append(quest_id)
	var queue: Array[String] = []
	for quest_id in get_quest_ids():
		if int(indegree[quest_id]) == 0:
			queue.append(quest_id)
	var visited: int = 0
	while not queue.is_empty():
		var current: String = queue.pop_front()
		visited += 1
		for next_id in outgoing[current] as Array:
			indegree[str(next_id)] = int(indegree[str(next_id)]) - 1
			if int(indegree[str(next_id)]) == 0:
				queue.append(str(next_id))
	return visited != QUESTS.size()
