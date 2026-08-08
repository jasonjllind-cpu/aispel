extends SceneTree

const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const PERSISTENCE_SCRIPT := preload("res://scripts/core/game_persistence_system.gd")
const TEST_SLOT := "ci_full_session"

class MockPlayer:
	extends Node3D
	var health: int = 73
	var max_health: int = 120
	var inventory: Dictionary = {"Rusty Sword": 1, "Moon Shard": 4, "Ancient Coin": 9}
	var equipped_weapon: String = "Rusty Sword"
	var equipped_armor: String = "Warden Mail"
	var spawn_position: Vector3 = Vector3(4, 2, -3)
	var velocity: Vector3 = Vector3.ZERO

	func _update_equipment_visuals() -> void:
		pass

	func _refresh_hud() -> void:
		pass

func _init() -> void:
	var world := Node3D.new()
	world.name = "PersistenceTestWorld"
	get_root().add_child(world)

	var state := Node.new()
	state.set_script(WORLD_STATE_SCRIPT)
	state.name = "PersistenceWorldState"
	get_root().add_child(state)
	state.set("world_seed", 515151)
	state.call("mark_region_discovered", "blackwood")
	state.call("set_flag", "dungeon:moon_catacombs:boss_defeated", true)
	state.call("set_entity_state", "boss:hollow_king", {"dead": true})

	var player := MockPlayer.new()
	player.global_position = Vector3(24.5, 3.0, -81.25)
	player.rotation = Vector3(0.0, 1.25, 0.0)
	world.add_child(player)

	var persistence := Node.new()
	persistence.set_script(PERSISTENCE_SCRIPT)
	world.add_child(persistence)
	persistence.set("world", world)
	persistence.set("world_state", state)
	persistence.set("player", player)
	var service: RefCounted = persistence.get("service")
	service.call("delete_slot", TEST_SLOT)

	var expected_position: Vector3 = player.global_position
	var expected_rotation: Vector3 = player.rotation
	var expected_inventory: Dictionary = player.inventory.duplicate(true)
	var expected_world: Dictionary = state.call("snapshot")

	var save_result: Dictionary = persistence.call("save_now", TEST_SLOT)
	if not save_result.get("ok", false):
		_fail(persistence, TEST_SLOT, "Full session save failed: %s" % str(save_result.get("error", "unknown")))
		return

	state.call("new_world", 999)
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.health = 1
	player.max_health = 10
	player.inventory = {"Ancient Coin": 1}
	player.equipped_weapon = ""
	player.equipped_armor = ""
	player.spawn_position = Vector3.ZERO

	var load_result: Dictionary = persistence.call("load_now", TEST_SLOT)
	if not load_result.get("ok", false):
		_fail(persistence, TEST_SLOT, "Full session load failed: %s" % str(load_result.get("error", "unknown")))
		return
	if state.call("snapshot") != expected_world:
		_fail(persistence, TEST_SLOT, "WorldState did not roundtrip through full session save")
		return
	if player.global_position != expected_position or player.rotation != expected_rotation:
		_fail(persistence, TEST_SLOT, "Player transform did not restore")
		return
	if player.health != 73 or player.max_health != 120:
		_fail(persistence, TEST_SLOT, "Player health did not restore")
		return
	if player.inventory != expected_inventory:
		_fail(persistence, TEST_SLOT, "Player inventory did not restore")
		return
	if player.equipped_weapon != "Rusty Sword" or player.equipped_armor != "Warden Mail":
		_fail(persistence, TEST_SLOT, "Player equipment did not restore")
		return
	if player.spawn_position != Vector3(4, 2, -3):
		_fail(persistence, TEST_SLOT, "Player checkpoint did not restore")
		return

	service.call("delete_slot", TEST_SLOT)
	print("GAME_PERSISTENCE_OK seed=%d inventory=%d" % [int(state.get("world_seed")), player.inventory.size()])
	quit(0)

func _fail(persistence: Node, slot_id: String, message: String) -> void:
	printerr("GAME_PERSISTENCE_FAILED: %s" % message)
	var service: RefCounted = persistence.get("service")
	service.call("delete_slot", slot_id)
	quit(1)
