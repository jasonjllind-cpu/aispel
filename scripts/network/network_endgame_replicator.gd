extends Node
class_name NetworkEndgameReplicator

signal snapshot_applied(revision: int)
signal snapshot_rejected(revision: int, reason: String)

const PROTOCOL: int = 1
const CAMPAIGN := preload("res://scripts/progression/campaign_progression_catalog.gd")
const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")
const CHOICES := preload("res://scripts/progression/endgame_choice_consequences.gd")
const POSTGAME := preload("res://scripts/progression/postgame_world_profile.gd")

var network_session: Node
var authoritative_snapshot: Dictionary = {}
var send_revision: int = 0
var receive_revision: int = 0

func _ready() -> void:
	add_to_group("network_endgame_replicator")
	_resolve_session()

func build_snapshot(completed_campaign: Array[String], world_milestones: Array[String], boss_state: Dictionary, relic_plan: Dictionary, relic_state: Dictionary, choice_state: Dictionary, postgame_profile: Dictionary = {}, revision: int = -1) -> Dictionary:
	var final_revision: int = revision
	if final_revision < 0:
		final_revision = send_revision + 1
		send_revision = final_revision
	var snapshot: Dictionary = {
		"protocol": PROTOCOL,
		"revision": final_revision,
		"completed_campaign": completed_campaign.duplicate(),
		"world_milestones": world_milestones.duplicate(),
		"boss_state": boss_state.duplicate(true),
		"relic_plan": relic_plan.duplicate(true),
		"relic_state": relic_state.duplicate(true),
		"choice_state": choice_state.duplicate(true),
		"postgame_profile": postgame_profile.duplicate(true)
	}
	return snapshot if validate_snapshot(snapshot) else {}

func validate_snapshot(snapshot: Dictionary) -> bool:
	if int(snapshot.get("protocol", 0)) != PROTOCOL or int(snapshot.get("revision", 0)) <= 0:
		return false
	var completed_value: Variant = snapshot.get("completed_campaign", [])
	var world_value: Variant = snapshot.get("world_milestones", [])
	var boss_value: Variant = snapshot.get("boss_state", {})
	var plan_value: Variant = snapshot.get("relic_plan", {})
	var relic_value: Variant = snapshot.get("relic_state", {})
	var choice_value: Variant = snapshot.get("choice_state", {})
	var postgame_value: Variant = snapshot.get("postgame_profile", {})
	if not completed_value is Array or not world_value is Array or not boss_value is Dictionary or not plan_value is Dictionary or not relic_value is Dictionary or not choice_value is Dictionary or not postgame_value is Dictionary:
		return false
	if not _validate_campaign(completed_value as Array) or not _validate_world_milestones(world_value as Array):
		return false
	var normalized_boss: Dictionary = BOSSES.normalize_state(boss_value)
	if normalized_boss != boss_value:
		return false
	if not RELICS.validate_plan(plan_value as Dictionary) or not RELICS.validate_state(relic_value as Dictionary, plan_value as Dictionary):
		return false
	if not CHOICES.validate_state(choice_value as Dictionary):
		return false
	if not (postgame_value as Dictionary).is_empty() and not POSTGAME.validate_profile(postgame_value as Dictionary):
		return false
	return true

func apply_authoritative_snapshot(snapshot: Dictionary, is_authority_source: bool = true) -> Dictionary:
	var revision: int = int(snapshot.get("revision", 0))
	if not is_authority_source:
		snapshot_rejected.emit(revision, "not_authority")
		return {"ok": false, "error": "not_authority"}
	if not validate_snapshot(snapshot):
		snapshot_rejected.emit(revision, "invalid_snapshot")
		return {"ok": false, "error": "invalid_snapshot"}
	if revision <= receive_revision:
		snapshot_rejected.emit(revision, "stale_revision")
		return {"ok": false, "error": "stale_revision"}
	authoritative_snapshot = snapshot.duplicate(true)
	receive_revision = revision
	snapshot_applied.emit(revision)
	return {"ok": true, "revision": revision}

func build_late_join_package(peer_id: int) -> Dictionary:
	if peer_id <= 0 or authoritative_snapshot.is_empty() or not validate_snapshot(authoritative_snapshot):
		return {}
	return {
		"protocol": PROTOCOL,
		"package_id": "endgame_late_join:%d:%d" % [peer_id, int(authoritative_snapshot.get("revision", 0))],
		"peer_id": peer_id,
		"revision": int(authoritative_snapshot.get("revision", 0)),
		"snapshot": authoritative_snapshot.duplicate(true)
	}

func apply_late_join_package(package: Dictionary) -> Dictionary:
	if int(package.get("protocol", 0)) != PROTOCOL or int(package.get("peer_id", 0)) <= 0:
		return {"ok": false, "error": "invalid_package"}
	var snapshot_value: Variant = package.get("snapshot", {})
	if not snapshot_value is Dictionary:
		return {"ok": false, "error": "invalid_package"}
	if int(package.get("revision", 0)) != int((snapshot_value as Dictionary).get("revision", -1)):
		return {"ok": false, "error": "revision_mismatch"}
	return apply_authoritative_snapshot(snapshot_value as Dictionary, true)

func broadcast_snapshot(snapshot: Dictionary) -> Dictionary:
	_resolve_session()
	if network_session == null or network_session.call("is_server_authority") != true:
		return {"ok": false, "error": "not_authority"}
	var result: Dictionary = apply_authoritative_snapshot(snapshot, true)
	if result.get("ok", false) == true and str(network_session.get("session_mode")) == "host":
		_receive_snapshot.rpc(snapshot)
	return result

func current_snapshot() -> Dictionary:
	return authoritative_snapshot.duplicate(true)

func reset() -> void:
	authoritative_snapshot.clear()
	send_revision = 0
	receive_revision = 0

func _validate_campaign(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var milestone_id: String = str(value)
		if CAMPAIGN.get_milestone(milestone_id).is_empty() or seen.has(milestone_id):
			return false
		seen[milestone_id] = true
	return true

func _validate_world_milestones(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var milestone_id: String = str(value)
		if milestone_id.is_empty() or seen.has(milestone_id):
			return false
		if not (milestone_id.begins_with("world_milestone:") or milestone_id.begins_with("dungeon_milestone:") or milestone_id.begins_with("boss_milestone:") or milestone_id.begins_with("campaign_milestone:")):
			return false
		seen[milestone_id] = true
	return true

func _resolve_session() -> void:
	if is_instance_valid(network_session):
		return
	var parent: Node = get_parent()
	if parent != null:
		network_session = parent.get_node_or_null("NetworkSession")

@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(snapshot: Dictionary) -> void:
	apply_authoritative_snapshot(snapshot, true)
