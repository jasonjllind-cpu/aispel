extends RefCounted
class_name QuestChainCatalog

const FORMAT_VERSION: int = 1

const CHAINS: Dictionary = {
	"frontier_oath": {
		"entry_nodes": ["frontier:arrival"],
		"nodes": {
			"frontier:arrival": {"required_level": 1, "requires": [], "next": ["frontier:warden", "frontier:scavenger"], "reward_ids": ["xp:120"], "tags": ["exploration"]},
			"frontier:warden": {"required_level": 2, "requires": ["frontier:arrival"], "next": ["frontier:moon_shrine"], "reward_ids": ["xp:180", "reputation:wardens:5"], "tags": ["combat", "wardens"]},
			"frontier:scavenger": {"required_level": 2, "requires": ["frontier:arrival"], "next": ["frontier:moon_shrine"], "reward_ids": ["xp:180", "loot:uncommon"], "tags": ["exploration", "relic"]},
			"frontier:moon_shrine": {"required_level": 3, "requires_any": ["frontier:warden", "frontier:scavenger"], "requires": [], "next": ["frontier:crypt"], "reward_ids": ["xp:240", "spell:moon_bolt"], "tags": ["magic", "shrine"]},
			"frontier:crypt": {"required_level": 4, "requires": ["frontier:moon_shrine"], "next": [], "reward_ids": ["xp:360", "equipment:rare"], "tags": ["dungeon", "boss"]}
		}
	},
	"blackwood_pact": {
		"entry_nodes": ["blackwood:edge"],
		"nodes": {
			"blackwood:edge": {"required_level": 5, "requires": [], "next": ["blackwood:hunt"], "reward_ids": ["xp:260"], "tags": ["exploration"]},
			"blackwood:hunt": {"required_level": 6, "requires": ["blackwood:edge"], "next": ["blackwood:chapel", "blackwood:witch"], "reward_ids": ["xp:320"], "tags": ["combat"]},
			"blackwood:chapel": {"required_level": 7, "requires": ["blackwood:hunt"], "next": ["blackwood:root_crypt"], "reward_ids": ["xp:380", "reputation:wardens:8"], "tags": ["chapel", "wardens"]},
			"blackwood:witch": {"required_level": 7, "requires": ["blackwood:hunt"], "next": ["blackwood:root_crypt"], "reward_ids": ["xp:380", "spell:thorn_grasp"], "tags": ["witch", "magic"]},
			"blackwood:root_crypt": {"required_level": 8, "requires_any": ["blackwood:chapel", "blackwood:witch"], "requires": [], "next": [], "reward_ids": ["xp:520", "equipment:rare"], "tags": ["dungeon", "boss"]}
		}
	}
}

static func get_chain_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in CHAINS.keys():
		ids.append(str(key))
	ids.sort()
	return ids

static func get_chain(chain_id: String) -> Dictionary:
	if not CHAINS.has(chain_id):
		return {}
	return (CHAINS[chain_id] as Dictionary).duplicate(true)

static func get_node(chain_id: String, node_id: String) -> Dictionary:
	var chain: Dictionary = get_chain(chain_id)
	var nodes: Dictionary = chain.get("nodes", {}) as Dictionary
	if not nodes.has(node_id):
		return {}
	var result: Dictionary = (nodes[node_id] as Dictionary).duplicate(true)
	result["id"] = node_id
	result["chain_id"] = chain_id
	result["progression_id"] = "quest:%s:%s" % [chain_id, node_id.replace(":", "_")]
	return result

static func validate_all() -> Dictionary:
	var errors: Array[String] = []
	for chain_id in get_chain_ids():
		_validate_chain(chain_id, errors)
	return {"valid": errors.is_empty(), "errors": errors}

static func available_nodes(chain_id: String, player_level: int, completed_nodes: Array[String]) -> Array[String]:
	var chain: Dictionary = get_chain(chain_id)
	if chain.is_empty():
		return []
	var nodes: Dictionary = chain.get("nodes", {}) as Dictionary
	var available: Array[String] = []
	for node_key in nodes.keys():
		var node_id: String = str(node_key)
		if completed_nodes.has(node_id):
			continue
		var node: Dictionary = nodes[node_key] as Dictionary
		if player_level < int(node.get("required_level", 1)):
			continue
		if not _requirements_met(node, completed_nodes):
			continue
		available.append(node_id)
	available.sort()
	return available

static func build_completion_event(chain_id: String, node_id: String, sequence: int) -> Dictionary:
	var node: Dictionary = get_node(chain_id, node_id)
	if node.is_empty() or sequence < 0:
		return {}
	return {
		"format_version": FORMAT_VERSION,
		"event_id": "quest_complete:%s:%d" % [str(node.get("progression_id", "")).trim_prefix("quest:"), sequence],
		"progression_id": str(node.get("progression_id", "")),
		"chain_id": chain_id,
		"node_id": node_id,
		"reward_ids": (node.get("reward_ids", []) as Array).duplicate(),
		"sequence": sequence
	}

static func _requirements_met(node: Dictionary, completed_nodes: Array[String]) -> bool:
	for requirement in node.get("requires", []) as Array:
		if not completed_nodes.has(str(requirement)):
			return false
	var any_requirements: Array = node.get("requires_any", []) as Array
	if not any_requirements.is_empty():
		var matched: bool = false
		for requirement in any_requirements:
			if completed_nodes.has(str(requirement)):
				matched = true
				break
		if not matched:
			return false
	return true

static func _validate_chain(chain_id: String, errors: Array[String]) -> void:
	var chain: Dictionary = get_chain(chain_id)
	var nodes: Dictionary = chain.get("nodes", {}) as Dictionary
	var entry_nodes: Array = chain.get("entry_nodes", []) as Array
	if nodes.is_empty() or entry_nodes.is_empty():
		errors.append("%s: missing nodes or entry nodes" % chain_id)
		return
	for entry_value in entry_nodes:
		if not nodes.has(str(entry_value)):
			errors.append("%s: missing entry %s" % [chain_id, str(entry_value)])
	for node_key in nodes.keys():
		var node_id: String = str(node_key)
		var node: Dictionary = nodes[node_key] as Dictionary
		if int(node.get("required_level", 0)) <= 0:
			errors.append("%s:%s invalid required level" % [chain_id, node_id])
		for link_key in ["requires", "requires_any", "next"]:
			for linked_value in node.get(link_key, []) as Array:
				if not nodes.has(str(linked_value)):
					errors.append("%s:%s missing %s link %s" % [chain_id, node_id, link_key, str(linked_value)])
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	for node_key in nodes.keys():
		if _has_cycle(str(node_key), nodes, visiting, visited):
			errors.append("%s: cycle detected" % chain_id)
		break

static func _has_cycle(node_id: String, nodes: Dictionary, visiting: Dictionary, visited: Dictionary) -> bool:
	if bool(visiting.get(node_id, false)):
		return true
	if bool(visited.get(node_id, false)):
		return false
	visiting[node_id] = true
	var node: Dictionary = nodes[node_id] as Dictionary
	for next_value in node.get("next", []) as Array:
		var next_id: String = str(next_value)
		if nodes.has(next_id) and _has_cycle(next_id, nodes, visiting, visited):
			return true
	visiting.erase(node_id)
	visited[node_id] = true
	return false
