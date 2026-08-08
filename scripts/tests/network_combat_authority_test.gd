extends SceneTree

const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const NETWORK_SESSION_SCRIPT := preload("res://scripts/network/network_session.gd")
const COMBAT_AUTHORITY_SCRIPT := preload("res://scripts/network/network_combat_authority.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")

class MockPlayerManager:
	extends Node
	var states: Dictionary = {}
	func state_for_peer(peer_id: int) -> Dictionary:
		var value: Variant = states.get(peer_id, {})
		return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var world_state := Node.new()
	world_state.set_script(WORLD_STATE_SCRIPT)
	world_state.name = "CombatWorldState"
	get_root().add_child(world_state)

	var session := Node.new()
	session.set_script(NETWORK_SESSION_SCRIPT)
	session.name = "NetworkSession"
	root.add_child(session)
	session.call("register_peer_for_test", 4)
	session.call("register_peer_for_test", 5)

	var players := MockPlayerManager.new()
	players.name = "NetworkPlayerManager"
	players.states[4] = {"position": Vector3.ZERO}
	players.states[5] = {"position": Vector3(50, 0, 0)}
	root.add_child(players)

	var combat := Node.new()
	combat.set_script(COMBAT_AUTHORITY_SCRIPT)
	root.add_child(combat)
	combat.set("network_session", session)
	combat.set("player_manager", players)
	combat.set("world_state", world_state)

	var enemy := CharacterBody3D.new()
	enemy.set_script(ENEMY_SCRIPT)
	enemy.set("persistent_id", "enemy:test:warden")
	enemy.set("max_health", 50)
	enemy.position = Vector3(2.0, 0, 0)
	root.add_child(enemy)

	var hit: Dictionary = combat.call("execute_attack", 4, "enemy:test:warden")
	if hit.get("ok", false) != true or int(hit.get("damage", 0)) != 16 or int(enemy.get("health")) != 34:
		_fail("Valid server-authoritative attack did not apply expected damage")
		return
	var persisted: Dictionary = world_state.call("get_entity_state", "enemy:test:warden")
	if int(persisted.get("health", -1)) != 34 or persisted.get("dead", true) == true:
		_fail("Enemy combat state was not persisted for replication")
		return
	var far_attack: Dictionary = combat.call("execute_attack", 5, "enemy:test:warden")
	if str(far_attack.get("error", "")) != "target_out_of_range":
		_fail("Out-of-range peer attack was not rejected")
		return
	var unknown: Dictionary = combat.call("execute_attack", 4, "enemy:missing")
	if str(unknown.get("error", "")) != "target_not_found":
		_fail("Unknown stable enemy ID was not rejected")
		return

	print("NETWORK_COMBAT_AUTHORITY_OK health=34 damage=16")
	quit(0)

func _fail(message: String) -> void:
	printerr("NETWORK_COMBAT_AUTHORITY_FAILED: %s" % message)
	quit(1)
