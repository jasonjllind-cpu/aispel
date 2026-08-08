extends RefCounted
class_name EndgameProgressionBundle

const FORMAT_VERSION: int = 1
const CAMPAIGN := preload("res://scripts/progression/campaign_progression_catalog.gd")
const ACCESS := preload("res://scripts/progression/endgame_region_access.gd")
const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")
const CHOICES := preload("res://scripts/progression/endgame_choice_consequences.gd")
const POSTGAME := preload("res://scripts/progression/postgame_world_profile.gd")
const SAVE := preload("res://scripts/progression/endgame_save_codec.gd")
const NETWORK := preload("res://scripts/network/network_endgame_replicator.gd")

static func create(graph: Dictionary) -> Dictionary:
	var world_seed: int = int(graph.get("world_seed", 0))
	if world_seed <= 0:
		return {}
	var access_plan: Dictionary = ACCESS.build_access_plan(graph)
	if not ACCESS.validate_plan(access_plan):
		return {}
	var relic_plan: Dictionary = RELICS.build_plan(graph, access_plan)
	if not RELICS.validate_plan(relic_plan):
		return {}
	var bundle: Dictionary = {
		"format_version": FORMAT_VERSION,
		"world_seed": world_seed,
		"revision": 0,
		"sequence": 0,
		"completed_campaign": [],
		"world_milestones": [],
		"access_plan": access_plan,
		"boss_state": BOSSES.empty_state(),
		"relic_plan": relic_plan,
		"relic_state": RELICS.create_state(relic_plan),
		"choice_state": CHOICES.create_state("world:%d" % world_seed),
		"postgame_profile": {}
	}
	return bundle if validate(bundle) else {}

static func validate(bundle: Dictionary) -> bool:
	if int(bundle.get("format_version", -1)) != FORMAT_VERSION or int(bundle.get("world_seed", 0)) <= 0:
		return false
	if int(bundle.get("revision", -1)) < 0 or int(bundle.get("sequence", -1)) < 0:
		return false
	var campaign_value: Variant = bundle.get("completed_campaign", [])
	var world_value: Variant = bundle.get("world_milestones", [])
	var access_value: Variant = bundle.get("access_plan", {})
	var boss_value: Variant = bundle.get("boss_state", {})
	var relic_plan_value: Variant = bundle.get("relic_plan", {})
	var relic_state_value: Variant = bundle.get("relic_state", {})
	var choice_value: Variant = bundle.get("choice_state", {})
	var postgame_value: Variant = bundle.get("postgame_profile", {})
	if not campaign_value is Array or not world_value is Array or not access_value is Dictionary or not boss_value is Dictionary:
		return false
	if not relic_plan_value is Dictionary or not relic_state_value is Dictionary or not choice_value is Dictionary or not postgame_value is Dictionary:
		return false
	if not _validate_campaign(campaign_value as Array) or not _validate_world_milestones(world_value as Array):
		return false
	if not ACCESS.validate_plan(access_value as Dictionary):
		return false
	if int((access_value as Dictionary).get("world_seed", 0)) != int(bundle.get("world_seed", 0)):
		return false
	if BOSSES.normalize_state(boss_value) != boss_value:
		return false
	if not RELICS.validate_plan(relic_plan_value as Dictionary) or int((relic_plan_value as Dictionary).get("world_seed", 0)) != int(bundle.get("world_seed", 0)):
		return false
	if not RELICS.validate_state(relic_state_value as Dictionary, relic_plan_value as Dictionary):
		return false
	if not CHOICES.validate_state(choice_value as Dictionary):
		return false
	if not (postgame_value as Dictionary).is_empty() and not POSTGAME.validate_profile(postgame_value as Dictionary):
		return false
	return true

static func add_world_milestone(bundle: Dictionary, milestone_id: String) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result) or not _valid_world_milestone(milestone_id):
		return result
	var milestones: Array = result.get("world_milestones", []) as Array
	if milestones.has(milestone_id):
		return result
	milestones.append(milestone_id)
	milestones.sort()
	result["world_milestones"] = milestones
	_touch(result)
	return result

static func complete_campaign(bundle: Dictionary, milestone_id: String, external_state_ids: Array[String] = []) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result) or CAMPAIGN.get_milestone(milestone_id).is_empty():
		return result
	var completed: Array[String] = _to_string_array(result.get("completed_campaign", []) as Array)
	if completed.has(milestone_id):
		return result
	var state_ids: Array[String] = _combined_requirement_ids(result, external_state_ids)
	var available: Array[String] = CAMPAIGN.available_milestones(completed, state_ids)
	if not available.has(milestone_id):
		return result
	completed.append(milestone_id)
	completed.sort()
	result["completed_campaign"] = completed
	_touch(result)
	return result

static func acquire_relic(bundle: Dictionary, objective_id: String, source_region_id: String) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result):
		return result
	var next_sequence: int = int(result.get("sequence", 0)) + 1
	var acquisition: Dictionary = RELICS.acquire(result.get("relic_state", {}) as Dictionary, result.get("relic_plan", {}) as Dictionary, objective_id, source_region_id, next_sequence)
	if acquisition.get("accepted", false) != true:
		return result
	result["relic_state"] = (acquisition.get("state", {}) as Dictionary).duplicate(true)
	result["sequence"] = next_sequence
	result["revision"] = int(result.get("revision", 0)) + 1
	return result

static func commit_choice(bundle: Dictionary, choice_id: String) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result):
		return result
	var next_sequence: int = int(result.get("sequence", 0)) + 1
	var choice_result: Dictionary = CHOICES.apply_choice(result.get("choice_state", {}) as Dictionary, choice_id, next_sequence)
	if choice_result.get("accepted", false) != true:
		return result
	result["choice_state"] = (choice_result.get("state", {}) as Dictionary).duplicate(true)
	result["sequence"] = next_sequence
	result["revision"] = int(result.get("revision", 0)) + 1
	return result

static func record_boss_victory(bundle: Dictionary, boss_id: String, authority_peer_id: int, sender_peer_id: int) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result):
		return result
	if boss_id == "eclipsed_regent" and not RELICS.endgame_ready(result.get("relic_state", {}) as Dictionary, result.get("relic_plan", {}) as Dictionary):
		return result
	var access: Dictionary = BOSSES.boss_access(boss_id, result.get("boss_state", {}), _to_string_array(result.get("completed_campaign", []) as Array), _to_string_array(result.get("world_milestones", []) as Array))
	if access.get("allowed", false) != true:
		return result
	var next_sequence: int = int(result.get("sequence", 0)) + 1
	var victory: Dictionary = BOSSES.record_authoritative_victory(result.get("boss_state", {}), boss_id, authority_peer_id, sender_peer_id, next_sequence)
	if victory.get("ok", false) != true:
		return result
	result["boss_state"] = (victory.get("state", {}) as Dictionary).duplicate(true)
	var event: Dictionary = victory.get("event", {}) as Dictionary
	var milestones: Array = result.get("world_milestones", []) as Array
	for milestone_value in event.get("milestones_added", []) as Array:
		var milestone_id: String = str(milestone_value)
		if _valid_world_milestone(milestone_id) and not milestones.has(milestone_id):
			milestones.append(milestone_id)
	milestones.sort()
	result["world_milestones"] = milestones
	result["sequence"] = next_sequence
	result["revision"] = int(result.get("revision", 0)) + 1
	return result

static func finish_ending(bundle: Dictionary, route: String, external_state_ids: Array[String] = []) -> Dictionary:
	var result: Dictionary = bundle.duplicate(true)
	if not validate(result) or not ["moon", "veil"].has(route):
		return result
	if result.get("postgame_profile", {}) is Dictionary and not (result.get("postgame_profile", {}) as Dictionary).is_empty():
		return result
	var boss_state: Dictionary = result.get("boss_state", {}) as Dictionary
	if boss_state.get("final_boss_defeated", false) != true:
		return result
	if not RELICS.endgame_ready(result.get("relic_state", {}) as Dictionary, result.get("relic_plan", {}) as Dictionary):
		return result
	var route_decision: Dictionary = CHOICES.ending_route_decision(route, result.get("choice_state", {}) as Dictionary, {}, external_state_ids)
	if route_decision.get("allowed", false) != true:
		return result
	var milestone_id: String = "campaign:ending_%s" % route
	var completed_result: Dictionary = complete_campaign(result, milestone_id, external_state_ids)
	if not (_to_string_array(completed_result.get("completed_campaign", []) as Array)).has(milestone_id):
		return result
	result = completed_result
	var ending_id: String = str(CAMPAIGN.get_milestone(milestone_id).get("ending_id", ""))
	var choices: Array[String] = _to_string_array((result.get("choice_state", {}) as Dictionary).get("committed_choice_ids", []) as Array)
	var next_sequence: int = int(result.get("sequence", 0)) + 1
	var profile: Dictionary = POSTGAME.build_profile(int(result.get("world_seed", 0)), ending_id, choices, result.get("boss_state", {}) as Dictionary, next_sequence)
	if not POSTGAME.validate_profile(profile):
		return result
	result["postgame_profile"] = profile
	result["sequence"] = next_sequence
	result["revision"] = int(result.get("revision", 0)) + 1
	return result

static func network_snapshot(bundle: Dictionary, replicator: Node = null) -> Dictionary:
	if not validate(bundle):
		return {}
	var network: Node = replicator
	var owned_network: bool = false
	if network == null:
		network = Node.new()
		network.set_script(NETWORK)
		owned_network = true
	var snapshot: Dictionary = network.call(
		"build_snapshot",
		_to_string_array(bundle.get("completed_campaign", []) as Array),
		_to_string_array(bundle.get("world_milestones", []) as Array),
		bundle.get("boss_state", {}) as Dictionary,
		bundle.get("relic_plan", {}) as Dictionary,
		bundle.get("relic_state", {}) as Dictionary,
		bundle.get("choice_state", {}) as Dictionary,
		bundle.get("postgame_profile", {}) as Dictionary,
		maxi(1, int(bundle.get("revision", 0)))
	) as Dictionary
	if owned_network:
		network.free()
	return snapshot

static func save_envelope(bundle: Dictionary) -> Dictionary:
	var snapshot: Dictionary = network_snapshot(bundle)
	return SAVE.encode(snapshot, int(bundle.get("sequence", 0))) if not snapshot.is_empty() else {}

static func restore_envelope(envelope: Dictionary, graph: Dictionary) -> Dictionary:
	var snapshot: Dictionary = SAVE.decode(envelope)
	if snapshot.is_empty():
		return {}
	return restore_network_snapshot(snapshot, graph)

static func restore_network_snapshot(snapshot: Dictionary, graph: Dictionary) -> Dictionary:
	var base: Dictionary = create(graph)
	if base.is_empty():
		return {}
	var deterministic_relic_plan: Dictionary = base.get("relic_plan", {}) as Dictionary
	if var_to_str(deterministic_relic_plan) != var_to_str(snapshot.get("relic_plan", {})):
		return {}
	base["completed_campaign"] = (snapshot.get("completed_campaign", []) as Array).duplicate()
	base["world_milestones"] = (snapshot.get("world_milestones", []) as Array).duplicate()
	base["boss_state"] = (snapshot.get("boss_state", {}) as Dictionary).duplicate(true)
	base["relic_state"] = (snapshot.get("relic_state", {}) as Dictionary).duplicate(true)
	base["choice_state"] = (snapshot.get("choice_state", {}) as Dictionary).duplicate(true)
	base["postgame_profile"] = (snapshot.get("postgame_profile", {}) as Dictionary).duplicate(true)
	base["revision"] = int(snapshot.get("revision", 1))
	base["sequence"] = maxi(int(base.get("sequence", 0)), int((base.get("boss_state", {}) as Dictionary).get("last_sequence", 0)), int((base.get("relic_state", {}) as Dictionary).get("revision", 0)), int((base.get("choice_state", {}) as Dictionary).get("revision", 0)))
	return base if validate(base) else {}

static func region_access(bundle: Dictionary, region_id: String) -> Dictionary:
	if not validate(bundle):
		return {"allowed": false, "reason": "invalid_bundle"}
	return ACCESS.evaluate_region(bundle.get("access_plan", {}) as Dictionary, region_id, _to_string_array(bundle.get("completed_campaign", []) as Array), _to_string_array(bundle.get("world_milestones", []) as Array))

static func _combined_requirement_ids(bundle: Dictionary, external_state_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in bundle.get("world_milestones", []) as Array:
		_append_unique(result, str(value))
	for value in external_state_ids:
		_append_unique(result, str(value))
	var choice_state: Dictionary = bundle.get("choice_state", {}) as Dictionary
	for value in choice_state.get("committed_choice_ids", []) as Array:
		_append_unique(result, str(value))
	for value in choice_state.get("world_flags", []) as Array:
		_append_unique(result, str(value))
	result.sort()
	return result

static func _validate_campaign(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var milestone_id: String = str(value)
		if CAMPAIGN.get_milestone(milestone_id).is_empty() or seen.has(milestone_id):
			return false
		seen[milestone_id] = true
	return true

static func _validate_world_milestones(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var milestone_id: String = str(value)
		if not _valid_world_milestone(milestone_id) or seen.has(milestone_id):
			return false
		seen[milestone_id] = true
	return true

static func _valid_world_milestone(milestone_id: String) -> bool:
	return milestone_id.begins_with("world_milestone:") or milestone_id.begins_with("dungeon_milestone:") or milestone_id.begins_with("boss_milestone:") or milestone_id.begins_with("campaign_milestone:")

static func _touch(bundle: Dictionary) -> void:
	bundle["sequence"] = int(bundle.get("sequence", 0)) + 1
	bundle["revision"] = int(bundle.get("revision", 0)) + 1

static func _append_unique(values: Array[String], value: String) -> void:
	if not value.is_empty() and not values.has(value):
		values.append(value)

static func _to_string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result
