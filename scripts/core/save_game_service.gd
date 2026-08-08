extends RefCounted
class_name SaveGameService

const SAVE_FORMAT_VERSION: int = 1
const DEFAULT_SLOT: String = "slot_1"
const SAVE_DIRECTORY: String = "user://saves"
const SAVE_EXTENSION: String = ".rfsave"

func save_world(world_state: Node, slot_id: String = DEFAULT_SLOT) -> Dictionary:
	if world_state == null or not world_state.has_method("snapshot"):
		return _error("invalid_world_state", "WorldState does not expose snapshot().")
	var snapshot_value: Variant = world_state.call("snapshot")
	if not snapshot_value is Dictionary:
		return _error("invalid_snapshot", "WorldState snapshot is not a Dictionary.")
	return write_snapshot(snapshot_value as Dictionary, slot_id)

func load_world(world_state: Node, slot_id: String = DEFAULT_SLOT) -> Dictionary:
	if world_state == null or not world_state.has_method("restore_snapshot"):
		return _error("invalid_world_state", "WorldState does not expose restore_snapshot().")
	var result: Dictionary = read_snapshot(slot_id)
	if not result.get("ok", false):
		return result
	var snapshot_value: Variant = result.get("snapshot", {})
	if not snapshot_value is Dictionary:
		return _error("invalid_snapshot", "Decoded save snapshot is not a Dictionary.")
	world_state.call("restore_snapshot", snapshot_value as Dictionary)
	return {
		"ok": true,
		"slot_id": _sanitize_slot_id(slot_id),
		"path": str(result.get("path", "")),
		"snapshot_version": int((snapshot_value as Dictionary).get("version", 0))
	}

func write_snapshot(snapshot: Dictionary, slot_id: String = DEFAULT_SLOT) -> Dictionary:
	var normalized_slot: String = _sanitize_slot_id(slot_id)
	var directory_error: Error = _ensure_save_directory()
	if directory_error != OK:
		return _error("directory_error", "Could not create save directory (%d)." % directory_error)

	var payload: String = Marshalls.variant_to_base64(snapshot, false)
	if payload.is_empty():
		return _error("encode_error", "Could not encode world snapshot.")
	var checksum: String = _sha256(payload)
	var envelope := {
		"format": "RETRO_FANTASY_SAVE",
		"format_version": SAVE_FORMAT_VERSION,
		"snapshot_version": int(snapshot.get("version", 0)),
		"payload": payload,
		"checksum": checksum
	}
	var json_text: String = JSON.stringify(envelope)
	var final_path: String = slot_path(normalized_slot)
	var temp_path: String = "%s.tmp" % final_path
	var backup_path: String = "%s.bak" % final_path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _error("write_error", "Could not open temporary save file for writing.")
	file.store_string(json_text)
	file.flush()
	file.close()

	# Verify exactly what reached disk before replacing the previous valid slot.
	var verify_result: Dictionary = _read_envelope(temp_path)
	if not verify_result.get("ok", false):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return verify_result

	var absolute_final: String = ProjectSettings.globalize_path(final_path)
	var absolute_temp: String = ProjectSettings.globalize_path(temp_path)
	var absolute_backup: String = ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(final_path):
		var backup_error: Error = DirAccess.rename_absolute(absolute_final, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temp)
			return _error("backup_error", "Could not protect previous save (%d)." % backup_error)
	var rename_error: Error = DirAccess.rename_absolute(absolute_temp, absolute_final)
	if rename_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_final)
		return _error("rename_error", "Could not commit temporary save (%d)." % rename_error)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	return {
		"ok": true,
		"slot_id": normalized_slot,
		"path": final_path,
		"snapshot_version": int(snapshot.get("version", 0)),
		"checksum": checksum
	}

func read_snapshot(slot_id: String = DEFAULT_SLOT) -> Dictionary:
	var normalized_slot: String = _sanitize_slot_id(slot_id)
	var path: String = slot_path(normalized_slot)
	var result: Dictionary = _read_envelope(path)
	if not result.get("ok", false):
		return result
	var envelope: Dictionary = result.get("envelope", {})
	var payload: String = str(envelope.get("payload", ""))
	var decoded: Variant = Marshalls.base64_to_variant(payload, false)
	if not decoded is Dictionary:
		return _error("decode_error", "Save payload did not decode to a world snapshot.")
	return {
		"ok": true,
		"slot_id": normalized_slot,
		"path": path,
		"snapshot": (decoded as Dictionary).duplicate(true),
		"snapshot_version": int(envelope.get("snapshot_version", 0)),
		"checksum": str(envelope.get("checksum", ""))
	}

func delete_slot(slot_id: String = DEFAULT_SLOT) -> bool:
	var path: String = slot_path(slot_id)
	var temp_path: String = "%s.tmp" % path
	var backup_path: String = "%s.bak" % path
	var ok := true
	for candidate in [path, temp_path, backup_path]:
		if FileAccess.file_exists(candidate):
			ok = DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate)) == OK and ok
	return ok

func slot_exists(slot_id: String = DEFAULT_SLOT) -> bool:
	return FileAccess.file_exists(slot_path(slot_id))

func slot_path(slot_id: String = DEFAULT_SLOT) -> String:
	return "%s/%s%s" % [SAVE_DIRECTORY, _sanitize_slot_id(slot_id), SAVE_EXTENSION]

func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("not_found", "Save slot does not exist.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("read_error", "Could not open save file.")
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _error("invalid_format", "Save file is not a valid envelope.")
	var envelope: Dictionary = parsed as Dictionary
	if str(envelope.get("format", "")) != "RETRO_FANTASY_SAVE":
		return _error("invalid_format", "Unknown save format.")
	if int(envelope.get("format_version", 0)) != SAVE_FORMAT_VERSION:
		return _error("unsupported_version", "Unsupported save format version.")
	var payload: String = str(envelope.get("payload", ""))
	var expected_checksum: String = str(envelope.get("checksum", ""))
	if payload.is_empty() or expected_checksum.is_empty() or _sha256(payload) != expected_checksum:
		return _error("checksum_mismatch", "Save file checksum is invalid.")
	return {"ok": true, "envelope": envelope}

func _ensure_save_directory() -> Error:
	var absolute_path: String = ProjectSettings.globalize_path(SAVE_DIRECTORY)
	return DirAccess.make_dir_recursive_absolute(absolute_path)

func _sanitize_slot_id(slot_id: String) -> String:
	var source: String = slot_id.strip_edges().to_lower()
	if source.is_empty():
		source = DEFAULT_SLOT
	var result := ""
	for character in source:
		if character.is_valid_identifier() or character.is_valid_int() or character == "-":
			result += character
		elif character == " " or character == ".":
			result += "_"
	if result.is_empty():
		return DEFAULT_SLOT
	return result.left(48)

func _sha256(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()

func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
