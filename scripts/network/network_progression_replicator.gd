extends Node
class_name NetworkProgressionReplicator

signal snapshot_applied(player_id: String, revision: int)
signal delta_applied(player_id: String, revision: int, kind: String)
signal delta_rejected(player_id: String, revision: int, reason: String)

const PROTOCOL: int = 1
const ALLOWED_KINDS := {
	"progression": true,
	"magic": true,
	"build": true,
	"quests": true
}
const ALLOWED_CLIENT_ACTIONS := {
	"equip": true,
	"unequip": true,
	"assign_spell": true,
	"quest_choice": true
}

const PLAYER_PROGRESSION := preload("res://scripts/progression/player_progression_state.gd")
const MAGIC_PROGRESS := preload("res://scripts/progression/magic_school_progression.gd")
const CHARACTER_BUILD := preload("res://scripts/progression/character_build_model.gd")

var network_session: Node
var authoritative_states: Dictionary = {}
var send_revision_by_player: Dictionary = {}
var receive_revision_by_player: Dictionary = {}

func _ready() -> void:
	add_to_group("network_progression_replicator")
	_resolve_session()

func build_player_snapshot(player_id: String, progression: Dictionary, magic: Dictionary, build: Dictionary, completed_quests: Array[String], revision: int = -1) -> Dictionary:
	if player_id.is_empty():
		return {}
	var final_revision: int = revision
	if final_revision < 0:
		final_revision = int(send_revision_by_player.get(player_id, 0)) + 1
		send_revision_by_player[player_id] = final_revision
	var snapshot: Dictionary = {
		"protocol": PROTOCOL,
		"player_id": player_id,
		"revision": final_revision,
		"progression": progression.duplicate(true),
		"magic": magic.duplicate(true),
		"build": build.duplicate(true),
		"completed_quests": completed_quests.duplicate()
	}
	if not validate_snapshot(snapshot):
		return {}
	return snapshot

func validate_snapshot(snapshot: Dictionary) -> bool:
	if int(snapshot.get("protocol", 0)) != PROTOCOL:
		return false
	var player_id: String = str(snapshot.get("player_id", ""))
	if player_id.is_empty() or int(snapshot.get("revision", 0)) <= 0:
		return false
	var progression_value: Variant = snapshot.get("progression", {})
	var magic_value: Variant = snapshot.get("magic", {})
	var build_value: Variant = snapshot.get("build", {})
	var quests_value: Variant = snapshot.get("completed_quests", [])
	if not progression_value is Dictionary or not magic_value is Dictionary or not build_value is Dictionary or not quests_value is Array:
		return false
	var progression: Dictionary = progression_value as Dictionary
	if str(progression.get("player_id", "")) != player_id or not _validate_progression(progression):
		return false
	var magic: Dictionary = magic_value as Dictionary
	if str(magic.get("player_id", "")) != player_id or not MAGIC_PROGRESS.validate_state(magic):
		return false
	var build: Dictionary = build_value as Dictionary
	if str(build.get("player_id", "")) != player_id or not CHARACTER_BUILD.validate_build(build):
		return false
	return _validate_completed_quests(quests_value as Array)

func register_authoritative_snapshot(snapshot: Dictionary) -> Dictionary:
	if not validate_snapshot(snapshot):
		return {"ok": false, "error": "invalid_snapshot"}
	var player_id: String = str(snapshot.get("player_id", ""))
	var revision: int = int(snapshot.get("revision", 0))
	var previous: int = int(receive_revision_by_player.get(player_id, 0))
	if revision <= previous:
		return {"ok": false, "error": "stale_revision"}
	authoritative_states[player_id] = snapshot.duplicate(true)
	receive_revision_by_player[player_id] = revision
	snapshot_applied.emit(player_id, revision)
	return {"ok": true, "player_id": player_id, "revision": revision}

func build_delta(player_id: String, kind: String, payload: Variant, revision: int = -1) -> Dictionary:
	if player_id.is_empty() or not ALLOWED_KINDS.has(kind):
		return {}
	var final_revision: int = revision
	if final_revision < 0:
		final_revision = int(send_revision_by_player.get(player_id, 0)) + 1
		send_revision_by_player[player_id] = final_revision
	var delta: Dictionary = {
		"protocol": PROTOCOL,
		"player_id": player_id,
		"revision": final_revision,
		"kind": kind,
		"payload": _duplicate_variant(payload)
	}
	if not _validate_delta_payload(delta):
		return {}
	return delta

func apply_delta(delta: Dictionary) -> Dictionary:
	var player_id: String = str(delta.get("player_id", ""))
	var revision: int = int(delta.get("revision", 0))
	var validation: Dictionary = validate_delta(delta)
	if validation.get("ok", false) != true:
		delta_rejected.emit(player_id, revision, str(validation.get("error", "invalid_delta")))
		return validation
	var current_value: Variant = authoritative_states.get(player_id, {})
	if not current_value is Dictionary or (current_value as Dictionary).is_empty():
		return {"ok": false, "error": "missing_snapshot"}
	var current: Dictionary = (current_value as Dictionary).duplicate(true)
	var kind: String = str(delta.get("kind", ""))
	var payload: Variant = delta.get("payload", null)
	match kind:
		"progression": current["progression"] = (payload as Dictionary).duplicate(true)
		"magic": current["magic"] = (payload as Dictionary).duplicate(true)
		"build": current["build"] = (payload as Dictionary).duplicate(true)
		"quests": current["completed_quests"] = (payload as Array).duplicate()
	current["revision"] = revision
	if not validate_snapshot(current):
		return {"ok": false, "error": "invalid_resulting_snapshot"}
	authoritative_states[player_id] = current
	receive_revision_by_player[player_id] = revision
	delta_applied.emit(player_id, revision, kind)
	return {"ok": true, "player_id": player_id, "revision": revision, "kind": kind}

func validate_delta(delta: Dictionary) -> Dictionary:
	if int(delta.get("protocol", 0)) != PROTOCOL:
		return {"ok": false, "error": "unsupported_protocol"}
	var player_id: String = str(delta.get("player_id", ""))
	if player_id.is_empty():
		return {"ok": false, "error": "missing_player_id"}
	var revision: int = int(delta.get("revision", 0))
	if revision <= int(receive_revision_by_player.get(player_id, 0)):
		return {"ok": false, "error": "stale_revision"}
	if not ALLOWED_KINDS.has(str(delta.get("kind", ""))):
		return {"ok": false, "error": "kind_not_allowed"}
	if not _validate_delta_payload(delta):
		return {"ok": false, "error": "invalid_payload"}
	return {"ok": true}

func validate_client_action(peer_id: int, action: String, payload: Dictionary) -> Dictionary:
	_resolve_session()
	if peer_id <= 0 or not ALLOWED_CLIENT_ACTIONS.has(action):
		return {"ok": false, "error": "action_not_allowed"}
	if network_session == null:
		return {"ok": false, "error": "network_session_missing"}
	var record: Dictionary = network_session.call("peer_record", peer_id)
	if record.is_empty():
		return {"ok": false, "error": "unknown_peer"}
	var player_id: String = str(record.get("player_id", ""))
	if str(payload.get("player_id", player_id)) != player_id:
		return {"ok": false, "error": "ownership_mismatch"}
	match action:
		"equip":
			if str(payload.get("instance_id", "")).is_empty():
				return {"ok": false, "error": "missing_instance_id"}
		"unequip":
			if not ["weapon", "armor"].has(str(payload.get("slot", ""))):
				return {"ok": false, "error": "invalid_slot"}
		"assign_spell":
			if int(payload.get("slot_index", -1)) < 0 or int(payload.get("slot_index", -1)) >= CHARACTER_BUILD.MAX_SPELL_SLOTS:
				return {"ok": false, "error": "invalid_spell_slot"}
			if not str(payload.get("spell_id", "")).is_empty() and SPELLS_LOOKUP(str(payload.get("spell_id", ""))).is_empty():
				return {"ok": false, "error": "unknown_spell"}
		"quest_choice":
			if not str(payload.get("progression_id", "")).begins_with("quest:"):
				return {"ok": false, "error": "invalid_quest_id"}
	return {"ok": true, "player_id": player_id}

func player_snapshot(player_id: String) -> Dictionary:
	var value: Variant = authoritative_states.get(player_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func broadcast_snapshot(snapshot: Dictionary) -> Dictionary:
	_resolve_session()
	if network_session == null or network_session.call("is_server_authority") != true:
		return {"ok": false, "error": "not_authority"}
	var result: Dictionary = register_authoritative_snapshot(snapshot)
	if result.get("ok", false) == true and str(network_session.get("session_mode")) == "host":
		_receive_snapshot.rpc(snapshot)
	return result

func broadcast_delta(delta: Dictionary) -> Dictionary:
	_resolve_session()
	if network_session == null or network_session.call("is_server_authority") != true:
		return {"ok": false, "error": "not_authority"}
	var result: Dictionary = apply_delta(delta)
	if result.get("ok", false) == true and str(network_session.get("session_mode")) == "host":
		_receive_delta.rpc(delta)
	return result

func reset_player(player_id: String) -> void:
	authoritative_states.erase(player_id)
	send_revision_by_player.erase(player_id)
	receive_revision_by_player.erase(player_id)

func _validate_progression(data: Dictionary) -> bool:
	var state: RefCounted = PLAYER_PROGRESSION.new()
	return bool(state.call("load_dict", data))

func _validate_completed_quests(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var quest_id: String = str(value)
		if not quest_id.begins_with("quest:") or seen.has(quest_id):
			return false
		seen[quest_id] = true
	return true

func _validate_delta_payload(delta: Dictionary) -> bool:
	var kind: String = str(delta.get("kind", ""))
	var player_id: String = str(delta.get("player_id", ""))
	var payload: Variant = delta.get("payload", null)
	match kind:
		"progression":
			return payload is Dictionary and str((payload as Dictionary).get("player_id", "")) == player_id and _validate_progression(payload as Dictionary)
		"magic":
			return payload is Dictionary and str((payload as Dictionary).get("player_id", "")) == player_id and MAGIC_PROGRESS.validate_state(payload as Dictionary)
		"build":
			return payload is Dictionary and str((payload as Dictionary).get("player_id", "")) == player_id and CHARACTER_BUILD.validate_build(payload as Dictionary)
		"quests":
			return payload is Array and _validate_completed_quests(payload as Array)
		_:
			return false

func _resolve_session() -> void:
	if is_instance_valid(network_session):
		return
	var parent := get_parent()
	if parent != null:
		network_session = parent.get_node_or_null("NetworkSession")

func _duplicate_variant(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func SPELLS_LOOKUP(spell_id: String) -> Dictionary:
	const SPELLS := preload("res://scripts/magic/spell_catalog.gd")
	return SPELLS.get_spell(spell_id)

@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(snapshot: Dictionary) -> void:
	register_authoritative_snapshot(snapshot)

@rpc("authority", "call_remote", "reliable")
func _receive_delta(delta: Dictionary) -> void:
	apply_delta(delta)
