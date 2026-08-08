extends SceneTree

const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const DUNGEON_SYSTEM_SCRIPT := preload("res://scripts/dungeon/dungeon_system.gd")
const DUNGEON_GENERATOR_SCRIPT := preload("res://scripts/dungeon/dungeon_generator.gd")

func _init() -> void:
	var world := Node3D.new()
	world.name = "TestWorld"
	get_root().add_child(world)

	var world_state := Node.new()
	world_state.set_script(WORLD_STATE_SCRIPT)
	world_state.name = "WorldState"
	get_root().add_child(world_state)

	var system := Node.new()
	system.set_script(DUNGEON_SYSTEM_SCRIPT)
	world.add_child(system)
	system.set("world", world)
	system.set("world_state", world_state)
	var generator: RefCounted = DUNGEON_GENERATOR_SCRIPT.new()
	generator.call("configure", 8242601)
	system.set("generator", generator)

	var failed := false
	system.call("_spawn_world_portals")
	var entrance := world.get_node_or_null("DungeonEntrance_moon_catacombs")
	if entrance == null:
		failed = _fail("World entrance portal was not created") or failed
	elif str(entrance.get_meta("stable_id", "")) != "portal:moon_catacombs:enter":
		failed = _fail("Entrance portal stable ID mismatch") or failed

	var dungeon_value: Variant = system.call("_ensure_dungeon_instance", "moon_catacombs")
	if not dungeon_value is Node3D:
		failed = _fail("Dungeon runtime instance was not created") or failed
	else:
		var dungeon := dungeon_value as Node3D
		var layout_value: Variant = dungeon.get_meta("layout", {})
		if not layout_value is Dictionary:
			failed = _fail("Dungeon runtime lost generated layout data") or failed
		if dungeon.get_node_or_null("DungeonExit") == null:
			failed = _fail("Dungeon exit portal missing") or failed
		var boss := dungeon.get_node_or_null("Boss_hollow_king")
		if boss == null:
			failed = _fail("Dungeon boss was not instantiated") or failed
		elif str(boss.get("persistent_id")) != "boss:hollow_king":
			failed = _fail("Dungeon boss persistent ID mismatch") or failed
		system.call("on_boss_defeated", "moon_catacombs", "hollow_king", dungeon.global_position)
		var boss_state: Dictionary = world_state.call("get_entity_state", "boss:hollow_king")
		if not bool(boss_state.get("dead", false)):
			failed = _fail("Dungeon boss defeat was not persisted") or failed
		if dungeon.get_node_or_null("loot_dungeon_moon_catacombs_boss_reward") == null:
			failed = _fail("Dungeon boss reward was not spawned") or failed

	if failed:
		printerr("DUNGEON_RUNTIME_FLOW_FAILED")
		quit(1)
		return
	print("DUNGEON_RUNTIME_FLOW_OK dungeon=moon_catacombs boss=hollow_king")
	quit(0)

func _fail(message: String) -> bool:
	printerr("DUNGEON_RUNTIME_FLOW_FAILED: %s" % message)
	return true
