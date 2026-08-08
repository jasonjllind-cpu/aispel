extends SceneTree

const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const DUNGEON_GENERATOR_SCRIPT := preload("res://scripts/dungeon/dungeon_generator.gd")
const DUNGEON_SYSTEM_SCRIPT := preload("res://scripts/dungeon/dungeon_system.gd")

func _init() -> void:
	var world := Node3D.new()
	world.name = "DungeonRuntimeWorld"
	get_root().add_child(world)

	var world_state := Node.new()
	world_state.set_script(WORLD_STATE_SCRIPT)
	world_state.name = "DungeonWorldState"
	get_root().add_child(world_state)

	# Keep the system outside the SceneTree in this contract test. This avoids
	# scheduling its production deferred installer while we inject dependencies
	# explicitly, and prevents shutdown-time lifecycle callbacks from racing quit().
	var system := Node.new()
	system.set_script(DUNGEON_SYSTEM_SCRIPT)
	system.set("world", world)
	system.set("world_state", world_state)
	var generator = DUNGEON_GENERATOR_SCRIPT.new()
	generator.configure(int(world_state.get("world_seed")))
	system.set("generator", generator)

	if not _test_portal(system, world):
		quit(1)
		return
	if not _test_instance(system, world_state):
		quit(1)
		return

	print("DUNGEON_RUNTIME_OK dungeon=moon_catacombs")
	quit(0)

func _test_portal(system: Node, world: Node3D) -> bool:
	system.call("_spawn_world_portals")
	var portal := world.get_node_or_null("DungeonEntrance_moon_catacombs")
	if portal == null or not portal is Area3D:
		return _fail("Dungeon world entrance was not created")
	if str(portal.get_meta("stable_id", "")) != "portal:moon_catacombs:enter":
		return _fail("Dungeon entrance stable ID is invalid")
	if not _has_collision(portal):
		return _fail("Dungeon entrance has no collision")
	return true

func _test_instance(system: Node, world_state: Node) -> bool:
	var root_value: Variant = system.call("_ensure_dungeon_instance", "moon_catacombs")
	if not root_value is Node3D:
		return _fail("Dungeon runtime instance was not created")
	var root := root_value as Node3D
	if str(root.get_meta("dungeon_id", "")) != "moon_catacombs":
		return _fail("Dungeon instance ID metadata is invalid")
	var layout_value: Variant = root.get_meta("layout", {})
	if not layout_value is Dictionary or (layout_value as Dictionary).is_empty():
		return _fail("Dungeon instance did not retain its deterministic layout")
	if root.get_node_or_null("DungeonExit") == null:
		return _fail("Dungeon exit portal is missing")
	if DisplayServer.get_name() == "headless" and _contains_mesh_instance(root):
		return _fail("Client dungeon mesh leaked into headless runtime")
	if _count_collisions(root) < 10:
		return _fail("Dungeon runtime did not create enough collision geometry")
	var boss := root.get_node_or_null("Boss_hollow_king")
	if boss == null:
		return _fail("Hollow King boss was not spawned")
	if str(boss.get("persistent_id")) != "boss:hollow_king":
		return _fail("Dungeon boss persistent ID is invalid")
	var treasure := root.get_node_or_null("loot_dungeon_moon_catacombs_treasure")
	if treasure == null:
		return _fail("Dungeon treasure loot was not spawned")
	if int(treasure.get("amount")) != 5:
		return _fail("Dungeon treasure amount did not use catalog reward data")

	var boss_position: Vector3 = boss.global_position
	system.call("on_boss_defeated", "moon_catacombs", "hollow_king", boss_position)
	var boss_state: Dictionary = world_state.call("get_entity_state", "boss:hollow_king")
	if boss_state.get("dead", false) != true:
		return _fail("Boss defeat was not persisted")
	if world_state.call("get_flag", "dungeon:moon_catacombs:boss_defeated", false) != true:
		return _fail("Dungeon completion flag was not persisted")
	var reward := root.get_node_or_null("loot_dungeon_moon_catacombs_boss_reward")
	if reward == null or int(reward.get("amount")) != 5:
		return _fail("Boss reward was not spawned from dungeon catalog data")
	return true

func _has_collision(node: Node) -> bool:
	for child in node.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			return true
	return false

func _contains_mesh_instance(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child in node.get_children():
		if _contains_mesh_instance(child):
			return true
	return false

func _count_collisions(node: Node) -> int:
	var count := 1 if node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collisions(child)
	return count

func _fail(message: String) -> bool:
	printerr("DUNGEON_RUNTIME_FAILED: %s" % message)
	return false
