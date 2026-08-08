extends SceneTree

const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const SAVE_SERVICE_SCRIPT := preload("res://scripts/core/save_game_service.gd")
const TEST_SLOT := "ci_roundtrip"

func _init() -> void:
	var service = SAVE_SERVICE_SCRIPT.new()
	service.delete_slot(TEST_SLOT)

	var state := Node.new()
	state.set_script(WORLD_STATE_SCRIPT)
	get_root().add_child(state)
	state.set("world_seed", 424242)
	state.set("current_region_id", "blackwood")
	state.call("mark_region_discovered", "starting_valley")
	state.call("mark_region_discovered", "blackwood")
	state.call("set_flag", "dungeon:moon_catacombs:boss_defeated", true)
	state.call("set_entity_state", "quest:whispers_in_blackwood", {"status": "completed", "reward_amount": 2})
	state.call("set_entity_state", "faction:moon_wardens", {"reputation": 20})
	state.call("set_entity_state", "loot:dungeon:moon_catacombs:treasure", {"collected": true})

	var before: Dictionary = state.call("snapshot")
	var save_result: Dictionary = service.save_world(state, TEST_SLOT)
	if not save_result.get("ok", false):
		_fail("Save failed: %s" % str(save_result.get("error", "unknown")))
		return
	if not service.slot_exists(TEST_SLOT):
		_fail("Save slot was not committed")
		return

	state.call("new_world", 999)
	state.call("set_flag", "mutated", true)
	var load_result: Dictionary = service.load_world(state, TEST_SLOT)
	if not load_result.get("ok", false):
		_fail("Load failed: %s" % str(load_result.get("error", "unknown")))
		return
	var after: Dictionary = state.call("snapshot")
	if before != after:
		_fail("World snapshot changed during save/load roundtrip")
		return

	var path: String = service.slot_path(TEST_SLOT)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		_fail("Could not reopen save for corruption test")
		return
	var text: String = file.get_as_text()
	file.seek(0)
	file.store_string(text.replace("\"checksum\":\"", "\"checksum\":\"corrupt"))
	file.resize(file.get_position())
	file.close()
	var corrupt_result: Dictionary = service.read_snapshot(TEST_SLOT)
	if corrupt_result.get("ok", false) or str(corrupt_result.get("error", "")) != "checksum_mismatch":
		_fail("Checksum corruption was not rejected")
		return

	service.delete_slot(TEST_SLOT)
	print("SAVE_GAME_SERVICE_OK snapshot_version=%d" % int(before.get("version", 0)))
	quit(0)

func _fail(message: String) -> void:
	printerr("SAVE_GAME_SERVICE_FAILED: %s" % message)
	var service = SAVE_SERVICE_SCRIPT.new()
	service.delete_slot(TEST_SLOT)
	quit(1)
