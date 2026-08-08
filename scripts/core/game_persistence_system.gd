extends Node
class_name GamePersistenceSystem

const SAVE_SERVICE_SCRIPT := preload("res://scripts/core/save_game_service.gd")
const AUTOSAVE_SLOT: String = "autosave"
const SESSION_FORMAT: String = "RETRO_FANTASY_SESSION"
const SESSION_VERSION: int = 1
const STATE_DEBOUNCE_SECONDS: float = 1.5
const PERIODIC_SAVE_SECONDS: float = 20.0
const MAX_RESTORE_RETRIES: int = 8

var service: RefCounted = SAVE_SERVICE_SCRIPT.new()
var world: Node3D
var world_state: Node
var player: Node
var dungeon_system: Node
var dirty: bool = false
var suppress_dirty: bool = false
var dirty_elapsed: float = 0.0
var periodic_elapsed: float = 0.0
var last_save_ok: bool = false
var last_error: String = ""
var pending_session: Dictionary = {}
var restore_retry_count: int = 0
var restore_retry_queued: bool = false

func _ready() -> void:
	add_to_group("persistence_system")
	set_process(false)
	call_deferred("_install")

func _install() -> void:
	# This node is intentionally placed before world-generation children in the
	# main scene. Restoring WorldState here makes the stored seed authoritative
	# before deferred procedural installers sample it.
	world = get_parent() as Node3D
	world_state = get_node_or_null("/root/WorldState")
	if world == null or world_state == null:
		return
	_resolve_dungeon_system()
	_load_world_state_early()
	if world_state.has_signal("state_changed"):
		world_state.connect("state_changed", Callable(self, "_on_world_state_changed"))
	await get_tree().process_frame
	await get_tree().process_frame
	player = _find_player()
	_apply_pending_session()
	set_process(true)

func _process(delta: float) -> void:
	periodic_elapsed += delta
	if dirty:
		dirty_elapsed += delta
		if dirty_elapsed >= STATE_DEBOUNCE_SECONDS:
			save_now()
			return
	if periodic_elapsed >= PERIODIC_SAVE_SECONDS:
		save_now()

func save_now(slot_id: String = AUTOSAVE_SLOT) -> Dictionary:
	if world_state == null:
		world_state = get_node_or_null("/root/WorldState")
	if player == null or not is_instance_valid(player):
		player = _find_player()
	if world_state == null or player == null:
		return _record_error({"ok": false, "error": "runtime_not_ready", "message": "WorldState or player is not ready."})
	var session: Dictionary = capture_session()
	var result: Dictionary = service.call("write_snapshot", session, slot_id)
	last_save_ok = result.get("ok", false) == true
	last_error = "" if last_save_ok else str(result.get("error", "save_failed"))
	if last_save_ok:
		dirty = false
		dirty_elapsed = 0.0
		periodic_elapsed = 0.0
	return result

func load_now(slot_id: String = AUTOSAVE_SLOT) -> Dictionary:
	var result: Dictionary = service.call("read_snapshot", slot_id)
	if result.get("ok", false) != true:
		return _record_error(result)
	var value: Variant = result.get("snapshot", {})
	if not value is Dictionary:
		return _record_error({"ok": false, "error": "invalid_session", "message": "Save payload is not a session."})
	var session: Dictionary = value as Dictionary
	if str(session.get("session_format", "")) != SESSION_FORMAT:
		return _record_error({"ok": false, "error": "invalid_session", "message": "Save payload has no supported session format."})
	suppress_dirty = true
	_restore_world_snapshot(session)
	pending_session = session.duplicate(true)
	restore_retry_count = 0
	_apply_pending_session()
	suppress_dirty = false
	dirty = false
	dirty_elapsed = 0.0
	periodic_elapsed = 0.0
	last_save_ok = true
	last_error = ""
	return {"ok": true, "slot_id": slot_id, "session_version": int(session.get("session_version", 0))}

func capture_session() -> Dictionary:
	var world_snapshot: Dictionary = {}
	if world_state != null and world_state.has_method("snapshot"):
		world_snapshot = world_state.call("snapshot")
	return {
		"version": SESSION_VERSION,
		"session_format": SESSION_FORMAT,
		"session_version": SESSION_VERSION,
		"saved_unix": int(Time.get_unix_time_from_system()),
		"world_state": world_snapshot,
		"player": _capture_player(),
		"runtime": {
			"active_dungeon_id": _active_dungeon_id()
		}
	}

func has_autosave() -> bool:
	return service.call("slot_exists", AUTOSAVE_SLOT)

func clear_autosave() -> bool:
	return service.call("delete_slot", AUTOSAVE_SLOT)

func request_autosave() -> void:
	if suppress_dirty:
		return
	dirty = true
	dirty_elapsed = 0.0

func _load_world_state_early() -> void:
	if not service.call("slot_exists", AUTOSAVE_SLOT):
		return
	var result: Dictionary = service.call("read_snapshot", AUTOSAVE_SLOT)
	if result.get("ok", false) != true:
		last_error = str(result.get("error", "load_failed"))
		return
	var value: Variant = result.get("snapshot", {})
	if not value is Dictionary:
		return
	var session: Dictionary = value as Dictionary
	if str(session.get("session_format", "")) != SESSION_FORMAT:
		return
	suppress_dirty = true
	_restore_world_snapshot(session)
	pending_session = session.duplicate(true)
	restore_retry_count = 0
	suppress_dirty = false

func _restore_world_snapshot(session: Dictionary) -> void:
	if world_state == null or not world_state.has_method("restore_snapshot"):
		return
	var value: Variant = session.get("world_state", {})
	if value is Dictionary:
		world_state.call("restore_snapshot", value as Dictionary)

func _apply_pending_session() -> void:
	if pending_session.is_empty():
		return
	if player == null or not is_instance_valid(player):
		player = _find_player()
	if player == null:
		_queue_restore_retry()
		return
	var runtime_value: Variant = pending_session.get("runtime", {})
	var dungeon_id := ""
	if runtime_value is Dictionary:
		dungeon_id = str((runtime_value as Dictionary).get("active_dungeon_id", ""))
	if not dungeon_id.is_empty() and not _restore_dungeon_runtime(dungeon_id):
		_queue_restore_retry()
		return
	var player_value: Variant = pending_session.get("player", {})
	if player_value is Dictionary:
		_apply_player(player_value as Dictionary)
	pending_session.clear()
	restore_retry_count = 0
	restore_retry_queued = false

func _queue_restore_retry() -> void:
	if restore_retry_queued or restore_retry_count >= MAX_RESTORE_RETRIES:
		return
	restore_retry_queued = true
	call_deferred("_retry_pending_session")

func _retry_pending_session() -> void:
	restore_retry_queued = false
	restore_retry_count += 1
	if get_tree() != null:
		await get_tree().process_frame
	_apply_pending_session()

func _capture_player() -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {}
	var node3d := player as Node3D
	return {
		"position": node3d.global_position,
		"rotation": node3d.rotation,
		"health": int(player.get("health")),
		"max_health": int(player.get("max_health")),
		"inventory": _dictionary_copy(player.get("inventory")),
		"equipped_weapon": str(player.get("equipped_weapon")),
		"equipped_armor": str(player.get("equipped_armor")),
		"spawn_position": player.get("spawn_position")
	}

func _apply_player(data: Dictionary) -> void:
	if player == null or not player is Node3D:
		return
	var node3d := player as Node3D
	var position_value: Variant = data.get("position", node3d.global_position)
	if position_value is Vector3:
		node3d.global_position = position_value as Vector3
	var rotation_value: Variant = data.get("rotation", node3d.rotation)
	if rotation_value is Vector3:
		node3d.rotation = rotation_value as Vector3
	player.set("max_health", max(1, int(data.get("max_health", player.get("max_health")))))
	player.set("health", clampi(int(data.get("health", player.get("health"))), 1, int(player.get("max_health"))))
	player.set("inventory", _dictionary_copy(data.get("inventory", {})))
	player.set("equipped_weapon", str(data.get("equipped_weapon", "Rusty Sword")))
	player.set("equipped_armor", str(data.get("equipped_armor", "")))
	var spawn_value: Variant = data.get("spawn_position", node3d.global_position)
	if spawn_value is Vector3:
		player.set("spawn_position", spawn_value as Vector3)
	player.set("velocity", Vector3.ZERO)
	if player.has_method("_update_equipment_visuals"):
		player.call("_update_equipment_visuals")
	if player.has_method("_refresh_hud"):
		player.call("_refresh_hud")

func _resolve_dungeon_system() -> Node:
	if is_instance_valid(dungeon_system):
		return dungeon_system
	if world != null:
		dungeon_system = world.get_node_or_null("DungeonSystem")
	return dungeon_system

func _restore_dungeon_runtime(dungeon_id: String) -> bool:
	var system: Node = _resolve_dungeon_system()
	if system == null:
		return false
	var generator_value: Variant = system.get("generator")
	if generator_value == null:
		return false
	if system.has_method("_ensure_dungeon_instance"):
		var instance_value: Variant = system.call("_ensure_dungeon_instance", dungeon_id)
		if not instance_value is Node3D:
			return false
	system.set("active_dungeon_id", dungeon_id)
	return true

func _active_dungeon_id() -> String:
	var system: Node = _resolve_dungeon_system()
	if system == null:
		return ""
	var value: Variant = system.get("active_dungeon_id")
	return str(value) if value != null else ""

func _find_player() -> Node:
	if get_tree() == null:
		return null
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	return players[0] if not players.is_empty() else null

func _on_world_state_changed(_kind: String, _stable_id: String) -> void:
	request_autosave()

func _record_error(result: Dictionary) -> Dictionary:
	last_save_ok = false
	last_error = str(result.get("error", "unknown"))
	return result

func _dictionary_copy(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
