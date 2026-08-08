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
	func set_authoritative_health(peer_id: int, health: int) -> void:
		var state: Dictionary = state_for_peer(peer_id)
		state["health"] = health
		states[peer_id] = state

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
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
	players.states[4] = {"position": Vector3.ZERO, "health": 80}
	players.states[5] = {"position": Vector3(50, 0, 0), "health": 100}
	root.add_child(players)

	# Keep combat outside the tree so only explicitly injected dependencies run.
	var combat := Node.new()
	combat.set_script(COMBAT_AUTHORITY_SCRIPT)
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
		_fail(combat, root, world_state, "Valid server-authoritative attack did not apply expected damage")
		return
	var persisted: Dictionary = world_state.call("get_entity_state", "enemy:test:warden")
	if int(persisted.get("health", -1)) != 34 or persisted.get("dead", true) == true:
		_fail(combat, root, world_state, "Enemy combat state was not persisted for replication")
		return
	var far_attack: Dictionary = combat.call("execute_attack", 5, "enemy:test:warden")
	if str(far_attack.get("error", "")) != "target_out_of_range":
		_fail(combat, root, world_state, "Out-of-range peer attack was not rejected")
		return
	var unknown: Dictionary = combat.call("execute_attack", 4, "enemy:missing")
	if str(unknown.get("error", "")) != "target_not_found":
		_fail(combat, root, world_state, "Unknown stable enemy ID was not rejected")
		return
	var remote_damage: Dictionary = combat.call("damage_player", 4, 13)
	if remote_damage.get("ok", false) != true or int((players.states[4] as Dictionary).get("health", -1)) != 67:
		_fail(combat, root, world_state, "Server did not own remote player damage")
		return

	print("NETWORK_COMBAT_AUTHORITY_OK enemy_health=34 remote_health=67")
	combat.free()
	root.queue_free()
	world_state.queue_free()
	await process_frame
	quit(0)

func _fail(combat: Node, root: Node, world_state: Node, message: String) -> void:
	printerr("NETWORK_COMBAT_AUTHORITY_FAILED: %s" % message)
	combat.free()
	root.queue_free()
	world_state.queue_free()
	quit(1)
