extends RefCounted
class_name WorldDistributionPlanner

const FORMAT_VERSION: int = 1
const SETTLEMENT_DIVISOR: int = 12
const LANDMARK_DIVISOR: int = 9

static func build(world_seed: int, nodes: Array) -> Dictionary:
	var nodes_by_id: Dictionary = _index_nodes(nodes)
	var settlement_target: int = 0
	if nodes_by_id.size() >= 8:
		settlement_target = maxi(1, floori(float(nodes_by_id.size()) / float(SETTLEMENT_DIVISOR)))
	var landmark_target: int = maxi(1, settlement_target)
	if nodes_by_id.size() >= 10:
		landmark_target = maxi(2, floori(float(nodes_by_id.size()) / float(LANDMARK_DIVISOR)))

	var settlements: Array[String] = _select_settlements(world_seed, nodes_by_id, settlement_target)
	var blocked: Dictionary = {}
	for stable_id in settlements:
		blocked[stable_id] = true
	var landmarks: Array[String] = _select_landmarks(world_seed, nodes_by_id, landmark_target, blocked)

	var placements: Array[Dictionary] = []
	var settlement_set: Dictionary = {}
	var landmark_set: Dictionary = {}
	for stable_id in settlements:
		settlement_set[stable_id] = true
		placements.append(_placement(stable_id, "settlement", nodes_by_id[stable_id] as Dictionary))
	for stable_id in landmarks:
		landmark_set[stable_id] = true
		placements.append(_placement(stable_id, "major_landmark", nodes_by_id[stable_id] as Dictionary))
	placements.sort_custom(_stable_id_less)

	var annotated_nodes: Array[Dictionary] = []
	for stable_id_value in nodes_by_id.keys():
		var stable_id: String = str(stable_id_value)
		var node: Dictionary = (nodes_by_id[stable_id] as Dictionary).duplicate(true)
		var role: String = "exploration"
		if node.get("anchor", false) == true:
			role = "authored_anchor"
		elif settlement_set.has(stable_id):
			role = "settlement"
		elif landmark_set.has(stable_id):
			role = "major_landmark"
		node["distribution_role"] = role
		node["distribution_id"] = ""
		if role == "settlement" or role == "major_landmark":
			node["distribution_id"] = "distribution:%s" % stable_id
		annotated_nodes.append(node)
	annotated_nodes.sort_custom(_node_less)

	return {
		"format_version": FORMAT_VERSION,
		"nodes": annotated_nodes,
		"placements": placements,
		"settlement_count": settlements.size(),
		"landmark_count": landmarks.size(),
		"constraints": {
			"settlements_not_adjacent": true,
			"major_landmarks_not_adjacent": true,
			"settlement_landmark_overlap": false
		}
	}

static func _select_settlements(world_seed: int, nodes_by_id: Dictionary, target_count: int) -> Array[String]:
	var ranked: Array[Dictionary] = []
	for stable_id_value in nodes_by_id.keys():
		var stable_id: String = str(stable_id_value)
		var node: Dictionary = nodes_by_id[stable_id] as Dictionary
		if node.get("anchor", false) == true:
			continue
		var profile: Dictionary = node.get("content_profile", {}) as Dictionary
		var affinity: float = float(profile.get("settlement_affinity", 0.5))
		var depth: int = maxi(0, int(node.get("graph_depth", 0)))
		var score: float = _stable_score(world_seed, stable_id, "settlement") - affinity * 0.65 + float(depth) * 0.025
		ranked.append({"stable_id": stable_id, "score": score})
	ranked.sort_custom(_score_less)
	return _select_spaced(ranked, nodes_by_id, target_count, {})

static func _select_landmarks(world_seed: int, nodes_by_id: Dictionary, target_count: int, blocked: Dictionary) -> Array[String]:
	var ranked: Array[Dictionary] = []
	for stable_id_value in nodes_by_id.keys():
		var stable_id: String = str(stable_id_value)
		if blocked.has(stable_id):
			continue
		var node: Dictionary = nodes_by_id[stable_id] as Dictionary
		if node.get("anchor", false) == true:
			continue
		var depth: int = maxi(0, int(node.get("graph_depth", 0)))
		var profile: Dictionary = node.get("content_profile", {}) as Dictionary
		var secret_chance: float = float(profile.get("secret_chance", 0.18))
		var score: float = _stable_score(world_seed, stable_id, "landmark") - secret_chance * 0.35 - float(depth) * 0.018
		ranked.append({"stable_id": stable_id, "score": score, "biome": str(node.get("biome", ""))})
	ranked.sort_custom(_score_less)

	var selected: Array[String] = []
	var used_biomes: Dictionary = {}
	for entry in ranked:
		if selected.size() >= target_count:
			break
		var stable_id: String = str(entry.get("stable_id", ""))
		var biome: String = str(entry.get("biome", ""))
		if used_biomes.has(biome) or _touches_any(stable_id, selected, nodes_by_id):
			continue
		selected.append(stable_id)
		used_biomes[biome] = true
	for entry in ranked:
		if selected.size() >= target_count:
			break
		var stable_id: String = str(entry.get("stable_id", ""))
		if selected.has(stable_id) or _touches_any(stable_id, selected, nodes_by_id):
			continue
		selected.append(stable_id)
	selected.sort()
	return selected

static func _select_spaced(ranked: Array[Dictionary], nodes_by_id: Dictionary, target_count: int, blocked: Dictionary) -> Array[String]:
	var selected: Array[String] = []
	for entry in ranked:
		if selected.size() >= target_count:
			break
		var stable_id: String = str(entry.get("stable_id", ""))
		if blocked.has(stable_id) or _touches_any(stable_id, selected, nodes_by_id):
			continue
		selected.append(stable_id)
	selected.sort()
	return selected

static func _touches_any(stable_id: String, selected: Array[String], nodes_by_id: Dictionary) -> bool:
	if not nodes_by_id.has(stable_id):
		return true
	var node: Dictionary = nodes_by_id[stable_id] as Dictionary
	var neighbours: Array = node.get("neighbor_ids", []) as Array
	for selected_id in selected:
		if selected_id == stable_id or neighbours.has(selected_id):
			return true
	return false

static func _placement(stable_id: String, placement_type: String, node: Dictionary) -> Dictionary:
	var module_id: String = "settlement_hub"
	if placement_type == "major_landmark":
		module_id = str(node.get("landmark_module", ""))
	return {
		"stable_id": "placement:%s:%s" % [placement_type, stable_id],
		"region_id": stable_id,
		"type": placement_type,
		"biome": str(node.get("biome", "green_highlands")),
		"graph_depth": int(node.get("graph_depth", 0)),
		"module": module_id
	}

static func _index_nodes(nodes: Array) -> Dictionary:
	var result: Dictionary = {}
	for node_value in nodes:
		if node_value is Dictionary:
			var node: Dictionary = node_value as Dictionary
			var stable_id: String = str(node.get("stable_id", ""))
			if not stable_id.is_empty():
				result[stable_id] = node
	return result

static func _stable_score(world_seed: int, stable_id: String, score_namespace: String) -> float:
	var raw: int = int(("%d:%s:%s:v%d" % [world_seed, score_namespace, stable_id, FORMAT_VERSION]).hash() & 0x7fffffff)
	return float(raw) / float(0x7fffffff)

static func _score_less(a: Dictionary, b: Dictionary) -> bool:
	var score_a: float = float(a.get("score", INF))
	var score_b: float = float(b.get("score", INF))
	if is_equal_approx(score_a, score_b):
		return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
	return score_a < score_b

static func _stable_id_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))

static func _node_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
