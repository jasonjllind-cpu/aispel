extends RefCounted
class_name EndgameChoiceConsequences

const FORMAT_VERSION: int = 1
const FACTIONS := preload("res://scripts/npc/faction_catalog.gd")

const CHOICES: Dictionary = {
	"choice:moon_oath": {
		"exclusive_group": "ending_oath",
		"ending_routes": ["moon"],
		"faction_delta": {"moon_wardens": 30, "veil_mourners": -15},
		"world_flags": ["choice:moon_oath"]
	},
	"choice:veil_bargain": {
		"exclusive_group": "ending_oath",
		"ending_routes": ["veil"],
		"faction_delta": {"veil_mourners": 30, "moon_wardens": -15},
		"world_flags": ["choice:veil_bargain"]
	},
	"choice:roadfolk_covenant": {
		"exclusive_group": "",
		"ending_routes": ["moon", "veil"],
		"faction_delta": {"roadfolk": 20},
		"world_flags": ["choice:roadfolk_covenant"]
	},
	"choice:blackwood_mercy": {
		"exclusive_group": "",
		"ending_routes": ["moon", "veil"],
		"faction_delta": {"blackwood_watchers": 20},
		"world_flags": ["choice:blackwood_mercy"]
	}
}

static func choice_ids() -> Array[String]:
	var result: Array[String] = []
	for choice_id in CHOICES.keys():
		result.append(str(choice_id))
	result.sort()
	return result

static func get_choice(choice_id: String) -> Dictionary:
	if not CHOICES.has(choice_id):
		return {}
	var result: Dictionary = (CHOICES[choice_id] as Dictionary).duplicate(true)
	result["choice_id"] = choice_id
	return result

static func create_state(scope_id: String = "world") -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"scope_id": scope_id,
		"revision": 0,
		"committed_choice_ids": [],
		"choice_events": [],
		"faction_deltas": {},
		"world_flags": []
	}

static func validate_state(state: Dictionary) -> bool:
	if int(state.get("format_version", -1)) != FORMAT_VERSION or int(state.get("revision", -1)) < 0:
		return false
	var choices_value: Variant = state.get("committed_choice_ids", [])
	var events_value: Variant = state.get("choice_events", [])
	var deltas_value: Variant = state.get("faction_deltas", {})
	var flags_value: Variant = state.get("world_flags", [])
	if not choices_value is Array or not events_value is Array or not deltas_value is Dictionary or not flags_value is Array:
		return false
	if _has_duplicates(choices_value as Array) or _has_duplicates(events_value as Array) or _has_duplicates(flags_value as Array):
		return false
	var exclusive_groups: Dictionary = {}
	for value in choices_value as Array:
		var choice_id: String = str(value)
		var choice: Dictionary = get_choice(choice_id)
		if choice.is_empty():
			return false
		var group: String = str(choice.get("exclusive_group", ""))
		if not group.is_empty():
			if exclusive_groups.has(group):
				return false
			exclusive_groups[group] = choice_id
	for faction_id in (deltas_value as Dictionary).keys():
		if FACTIONS.get_faction(str(faction_id)).is_empty():
			return false
	return true

static func apply_choice(state: Dictionary, choice_id: String, sequence: int) -> Dictionary:
	var result: Dictionary = {"accepted": false, "reason": "invalid_state", "state": state.duplicate(true), "event": {}}
	if not validate_state(state):
		return result
	var choice: Dictionary = get_choice(choice_id)
	if choice.is_empty():
		result["reason"] = "unknown_choice"
		return result
	if sequence < 0:
		result["reason"] = "invalid_sequence"
		return result
	var committed: Array = state.get("committed_choice_ids", []) as Array
	if committed.has(choice_id):
		result["reason"] = "already_committed"
		return result
	var exclusive_group: String = str(choice.get("exclusive_group", ""))
	if not exclusive_group.is_empty():
		for existing_id in committed:
			var existing: Dictionary = get_choice(str(existing_id))
			if str(existing.get("exclusive_group", "")) == exclusive_group:
				result["reason"] = "exclusive_choice_conflict"
				return result

	var next: Dictionary = state.duplicate(true)
	var next_committed: Array = next.get("committed_choice_ids", []) as Array
	next_committed.append(choice_id)
	next_committed.sort()
	next["committed_choice_ids"] = next_committed
	var deltas: Dictionary = next.get("faction_deltas", {}) as Dictionary
	for faction_id in (choice.get("faction_delta", {}) as Dictionary).keys():
		deltas[str(faction_id)] = clampi(int(deltas.get(str(faction_id), 0)) + int((choice.get("faction_delta", {}) as Dictionary).get(faction_id, 0)), -100, 100)
	next["faction_deltas"] = deltas
	var flags: Array = next.get("world_flags", []) as Array
	for flag_value in choice.get("world_flags", []) as Array:
		var flag_id: String = str(flag_value)
		if not flags.has(flag_id):
			flags.append(flag_id)
	flags.sort()
	next["world_flags"] = flags
	var event_id: String = "endgame_choice:%s:%d" % [choice_id.trim_prefix("choice:"), sequence]
	var events: Array = next.get("choice_events", []) as Array
	events.append(event_id)
	events.sort()
	next["choice_events"] = events
	next["revision"] = int(next.get("revision", 0)) + 1
	result["accepted"] = true
	result["reason"] = ""
	result["state"] = next
	result["event"] = {
		"format_version": FORMAT_VERSION,
		"event_id": event_id,
		"choice_id": choice_id,
		"sequence": sequence,
		"faction_delta": (choice.get("faction_delta", {}) as Dictionary).duplicate(true),
		"world_flags": (choice.get("world_flags", []) as Array).duplicate()
	}
	return result

static func ending_route_decision(route: String, state: Dictionary, base_reputation: Dictionary = {}, mastery_ids: Array[String] = []) -> Dictionary:
	if not ["moon", "veil"].has(route):
		return {"allowed": false, "reason": "unknown_route", "route": route}
	if not validate_state(state):
		return {"allowed": false, "reason": "invalid_state", "route": route}
	var committed: Array = state.get("committed_choice_ids", []) as Array
	var oath_choice: String = ""
	for choice_id in committed:
		var choice: Dictionary = get_choice(str(choice_id))
		if str(choice.get("exclusive_group", "")) == "ending_oath":
			oath_choice = str(choice_id)
			break
	if not oath_choice.is_empty():
		var routes: Array = get_choice(oath_choice).get("ending_routes", []) as Array
		if not routes.has(route):
			return {"allowed": false, "reason": "opposing_oath", "route": route, "oath_choice": oath_choice}
		return {"allowed": true, "reason": "", "route": route, "source": oath_choice}

	var mastery_id: String = "magic_mastery:%s" % route
	if mastery_ids.has(mastery_id):
		return {"allowed": true, "reason": "", "route": route, "source": mastery_id}
	var faction_id: String = "moon_wardens" if route == "moon" else "veil_mourners"
	var total_reputation: int = int(base_reputation.get(faction_id, 0)) + int((state.get("faction_deltas", {}) as Dictionary).get(faction_id, 0))
	if total_reputation >= 40:
		return {"allowed": true, "reason": "", "route": route, "source": "faction:%s" % faction_id, "reputation": total_reputation}
	return {"allowed": false, "reason": "route_prerequisite_missing", "route": route, "required_any": ["choice:%s_%s" % [route, "oath" if route == "moon" else "bargain"], mastery_id, "faction:%s:trusted" % faction_id]}

static func compatible_ending_routes(state: Dictionary, base_reputation: Dictionary = {}, mastery_ids: Array[String] = []) -> Array[String]:
	var result: Array[String] = []
	for route in ["moon", "veil"]:
		if ending_route_decision(route, state, base_reputation, mastery_ids).get("allowed", false) == true:
			result.append(route)
	return result

static func effective_reputation(state: Dictionary, faction_id: String, base_reputation: int = 0) -> int:
	if not validate_state(state) or FACTIONS.get_faction(faction_id).is_empty():
		return clampi(base_reputation, -100, 100)
	return clampi(base_reputation + int((state.get("faction_deltas", {}) as Dictionary).get(faction_id, 0)), -100, 100)

static func _has_duplicates(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var key: String = str(value)
		if seen.has(key):
			return true
		seen[key] = true
	return false
