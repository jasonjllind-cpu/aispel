extends SceneTree

const DUNGEON_CATALOG := preload("res://scripts/dungeon/dungeon_catalog.gd")
const DUNGEON_GENERATOR_SCRIPT := preload("res://scripts/dungeon/dungeon_generator.gd")

func _init() -> void:
	var failed := false
	failed = not _test_catalog() or failed
	failed = not _test_deterministic_layout() or failed
	failed = not _test_layout_contract() or failed
	if failed:
		printerr("DUNGEON_FOUNDATION_FAILED")
		quit(1)
		return
	print("DUNGEON_FOUNDATION_OK dungeons=%d" % DUNGEON_CATALOG.get_dungeon_ids().size())
	quit(0)

func _test_catalog() -> bool:
	var ids: Array[String] = DUNGEON_CATALOG.get_dungeon_ids()
	if not ids.has("moon_catacombs"):
		return _fail("Moon Catacombs is missing from the dungeon catalog")
	var definition: Dictionary = DUNGEON_CATALOG.get_dungeon("moon_catacombs")
	if str(definition.get("region_id", "")) != "starting_valley":
		return _fail("Moon Catacombs region link is invalid")
	if int(definition.get("room_count", 0)) < 4:
		return _fail("Moon Catacombs room count is invalid")
	if str(definition.get("boss_id", "")) != "hollow_king":
		return _fail("Moon Catacombs boss contract is invalid")
	if int(definition.get("reward_amount", 0)) != 5:
		return _fail("Moon Catacombs reward contract is invalid")
	return true

func _test_deterministic_layout() -> bool:
	var generator = DUNGEON_GENERATOR_SCRIPT.new()
	generator.configure(8242601)
	var first: Dictionary = generator.generate_layout("moon_catacombs")
	var second: Dictionary = generator.generate_layout("moon_catacombs")
	if first != second:
		return _fail("Same seed did not reproduce the same dungeon layout")
	generator.configure(8242602)
	var changed: Dictionary = generator.generate_layout("moon_catacombs")
	if int(first.get("layout_seed", 0)) == int(changed.get("layout_seed", 0)):
		return _fail("Different world seeds produced the same dungeon layout seed")
	if first == changed:
		return _fail("Different world seeds produced identical dungeon data")
	return true

func _test_layout_contract() -> bool:
	var generator = DUNGEON_GENERATOR_SCRIPT.new()
	generator.configure(8242601)
	var layout: Dictionary = generator.generate_layout("moon_catacombs")
	if layout.is_empty():
		return _fail("Dungeon generator returned no layout")
	var rooms_value: Variant = layout.get("rooms", [])
	var connections_value: Variant = layout.get("connections", [])
	var encounters_value: Variant = layout.get("encounters", [])
	var loot_value: Variant = layout.get("loot", [])
	if not rooms_value is Array or not connections_value is Array or not encounters_value is Array or not loot_value is Array:
		return _fail("Dungeon layout collections have invalid types")
	var rooms: Array = rooms_value as Array
	var connections: Array = connections_value as Array
	var encounters: Array = encounters_value as Array
	var loot: Array = loot_value as Array
	var definition: Dictionary = DUNGEON_CATALOG.get_dungeon("moon_catacombs")
	if rooms.size() != int(definition.get("room_count", 0)):
		return _fail("Generated room count does not match catalog")
	if connections.size() != rooms.size() - 1:
		return _fail("Dungeon progression graph is not a connected room chain")
	if rooms.is_empty() or str((rooms[0] as Dictionary).get("type", "")) != "entrance":
		return _fail("Dungeon entrance room is missing")
	if str((rooms[rooms.size() - 1] as Dictionary).get("type", "")) != "boss":
		return _fail("Dungeon boss room is not the final room")
	if str((rooms[rooms.size() - 2] as Dictionary).get("type", "")) != "treasure":
		return _fail("Dungeon treasure room is not placed before the boss")
	if int(layout.get("boss_room_index", -1)) != rooms.size() - 1:
		return _fail("Dungeon boss room index is invalid")

	var cells: Dictionary = {}
	for i in range(rooms.size()):
		if not rooms[i] is Dictionary:
			return _fail("Dungeon room is not a dictionary")
		var room: Dictionary = rooms[i] as Dictionary
		if str(room.get("id", "")) != "room:moon_catacombs:%d" % i:
			return _fail("Dungeon room stable ID mismatch")
		var cell: Variant = room.get("cell", null)
		if cells.has(cell):
			return _fail("Dungeon generator placed two rooms in the same cell")
		cells[cell] = true

	for i in range(connections.size()):
		var connection: Dictionary = connections[i] as Dictionary
		if int(connection.get("from", -1)) != i or int(connection.get("to", -1)) != i + 1:
			return _fail("Dungeon connection chain is invalid")

	for encounter_value in encounters:
		var encounter: Dictionary = encounter_value as Dictionary
		var room_index: int = int(encounter.get("room_index", -1))
		if room_index <= 0 or room_index >= rooms.size() - 1:
			return _fail("Dungeon encounter leaked into entrance or boss room")
		if str((rooms[room_index] as Dictionary).get("type", "")) == "treasure":
			return _fail("Dungeon encounter leaked into treasure room")
		if not str(encounter.get("id", "")).begins_with("enemy:dungeon:moon_catacombs:"):
			return _fail("Dungeon encounter stable ID is invalid")

	if loot.size() != 1:
		return _fail("Expected exactly one deterministic treasure reward")
	var treasure: Dictionary = loot[0] as Dictionary
	if str(treasure.get("id", "")) != "loot:dungeon:moon_catacombs:treasure":
		return _fail("Dungeon loot stable ID is invalid")
	if int(treasure.get("room_index", -1)) != rooms.size() - 2:
		return _fail("Dungeon loot is not attached to the treasure room")
	if str(treasure.get("item_name", "")) != str(definition.get("reward_item", "")):
		return _fail("Dungeon loot item does not match catalog")
	if int(treasure.get("amount", 0)) != int(definition.get("reward_amount", 0)):
		return _fail("Dungeon loot amount does not match catalog")
	return true

func _fail(message: String) -> bool:
	printerr("DUNGEON_FOUNDATION_FAILED: %s" % message)
	return false
