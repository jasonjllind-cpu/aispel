extends RefCounted
class_name PostgameWorldProfile

const FORMAT_VERSION: int = 1
const STATE_ID: String = "postgame:profile"

const ENDING_MODIFIERS: Dictionary = {
	"ending:moon_restored": [
		"world_modifier:moonlit_roads",
		"world_modifier:restored_shrines",
		"world_modifier:calmer_dead"
	],
	"ending:veil_bound": [
		"world_modifier:veil_bloom",
		"world_modifier:restless_echoes",
		"world_modifier:grave_passages"
	]
}

static func build_profile(world_seed: int, ending_id: String, completed_choice_ids: Array[String], boss_state: Dictionary, completion_sequence: int) -> Dictionary:
	if world_seed == 0 or not ENDING_MODIFIERS.has(ending_id) or completion_sequence < 0:
		return {}
	var modifiers: Array[String] = []
	for value in ENDING_MODIFIERS[ending_id] as Array:
		modifiers.append(str(value))
	var guardian_count: int = (boss_state.get("guardian_victory_ids", []) as Array).size() if boss_state.get("guardian_victory_ids", []) is Array else 0
	if guardian_count >= 3:
		modifiers.append("world_modifier:guardian_echoes")
	if completed_choice_ids.has("choice:roadfolk_covenant"):
		modifiers.append("world_modifier:open_caravan_routes")
	if completed_choice_ids.has("choice:blackwood_mercy"):
		modifiers.append("world_modifier:blackwood_truce")
	modifiers = _unique_strings(modifiers)
	return {
		"format_version": FORMAT_VERSION,
		"profile_id": "postgame:%s:%d:%d" % [ending_id.trim_prefix("ending:"), abs(world_seed), completion_sequence],
		"world_seed": abs(world_seed),
		"ending_id": ending_id,
		"completion_sequence": completion_sequence,
		"completed_choice_ids": _unique_strings(completed_choice_ids),
		"guardian_count": guardian_count,
		"modifier_ids": modifiers,
		"postgame_unlocked": true,
		"new_game_plus_unlocked": true
	}

static func validate_profile(profile: Dictionary) -> bool:
	if int(profile.get("format_version", -1)) != FORMAT_VERSION:
		return false
	var ending_id: String = str(profile.get("ending_id", ""))
	if not ENDING_MODIFIERS.has(ending_id):
		return false
	if not str(profile.get("profile_id", "")).begins_with("postgame:%s:" % ending_id.trim_prefix("ending:")):
		return false
	if int(profile.get("world_seed", 0)) <= 0 or int(profile.get("completion_sequence", -1)) < 0:
		return false
	if profile.get("postgame_unlocked", false) != true or profile.get("new_game_plus_unlocked", false) != true:
		return false
	var modifiers_value: Variant = profile.get("modifier_ids", [])
	var choices_value: Variant = profile.get("completed_choice_ids", [])
	if not modifiers_value is Array or not choices_value is Array:
		return false
	if _has_duplicates(modifiers_value as Array) or _has_duplicates(choices_value as Array):
		return false
	for required in ENDING_MODIFIERS[ending_id] as Array:
		if not (modifiers_value as Array).has(str(required)):
			return false
	return true

static func build_region_modifier_plan(profile: Dictionary, graph: Dictionary, max_regions: int = 8) -> Dictionary:
	if not validate_profile(profile):
		return {}
	var nodes_value: Variant = graph.get("nodes", [])
	if not nodes_value is Array:
		return {}
	var nodes: Array[Dictionary] = []
	for value in nodes_value as Array:
		if value is Dictionary and str((value as Dictionary).get("stable_id", "")).begins_with("region:"):
			nodes.append((value as Dictionary).duplicate(true))
	if nodes.is_empty():
		return {}
	nodes.sort_custom(_node_less)
	var count: int = mini(maxi(1, max_regions), nodes.size())
	var assignments: Array[Dictionary] = []
	var modifiers: Array = profile.get("modifier_ids", []) as Array
	for index in range(count):
		var node_index: int = _stable_index(int(profile.get("world_seed", 0)), str(profile.get("ending_id", "")), index, nodes.size())
		var attempts: int = 0
		while attempts < nodes.size() and _region_already_assigned(assignments, str(nodes[node_index].get("stable_id", ""))):
			node_index = (node_index + 1) % nodes.size()
			attempts += 1
		if attempts >= nodes.size():
			break
		var node: Dictionary = nodes[node_index]
		var modifier_id: String = str(modifiers[index % modifiers.size()])
		assignments.append({
			"assignment_id": "postgame_region_modifier:%s:%s" % [str(node.get("stable_id", "")).trim_prefix("region:").replace(":", "_"), modifier_id.trim_prefix("world_modifier:")],
			"region_id": str(node.get("stable_id", "")),
			"modifier_id": modifier_id,
			"biome": str(node.get("biome", "")),
			"graph_depth": int(node.get("graph_depth", 0))
		})
	assignments.sort_custom(_assignment_less)
	return {
		"format_version": FORMAT_VERSION,
		"plan_id": "postgame_region_plan:%s" % str(profile.get("profile_id", "")).trim_prefix("postgame:").replace(":", "_"),
		"profile_id": str(profile.get("profile_id", "")),
		"assignments": assignments
	}

static func validate_region_plan(plan: Dictionary, profile: Dictionary) -> bool:
	if not validate_profile(profile) or int(plan.get("format_version", -1)) != FORMAT_VERSION:
		return false
	if str(plan.get("profile_id", "")) != str(profile.get("profile_id", "")):
		return false
	var assignments_value: Variant = plan.get("assignments", [])
	if not assignments_value is Array or (assignments_value as Array).is_empty():
		return false
	var seen_regions: Dictionary = {}
	for value in assignments_value as Array:
		if not value is Dictionary:
			return false
		var assignment: Dictionary = value as Dictionary
		var region_id: String = str(assignment.get("region_id", ""))
		var modifier_id: String = str(assignment.get("modifier_id", ""))
		if not region_id.begins_with("region:") or seen_regions.has(region_id):
			return false
		if not (profile.get("modifier_ids", []) as Array).has(modifier_id):
			return false
		seen_regions[region_id] = true
	return true

static func apply_to_world_state(world_state: Node, profile: Dictionary) -> bool:
	if world_state == null or not validate_profile(profile):
		return false
	if not world_state.has_method("set_entity_state") or not world_state.has_method("set_flag"):
		return false
	world_state.call("set_entity_state", STATE_ID, profile.duplicate(true))
	world_state.call("set_flag", "postgame:active", true)
	world_state.call("set_flag", str(profile.get("ending_id", "")), true)
	for modifier_id in profile.get("modifier_ids", []) as Array:
		world_state.call("set_flag", str(modifier_id), true)
	return true

static func _stable_index(seed: int, ending_id: String, index: int, size: int) -> int:
	if size <= 0:
		return 0
	return int(abs(("%d:%s:%d" % [seed, ending_id, index]).hash())) % size

static func _node_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))

static func _assignment_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("region_id", "")) < str(b.get("region_id", ""))

static func _region_already_assigned(assignments: Array[Dictionary], region_id: String) -> bool:
	for assignment in assignments:
		if str(assignment.get("region_id", "")) == region_id:
			return true
	return false

static func _unique_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text: String = str(value)
		if not text.is_empty() and not result.has(text):
			result.append(text)
	result.sort()
	return result

static func _has_duplicates(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var key: String = str(value)
		if seen.has(key):
			return true
		seen[key] = true
	return false
