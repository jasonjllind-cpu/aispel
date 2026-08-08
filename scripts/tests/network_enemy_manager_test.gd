extends SceneTree

const ENEMY_MANAGER_SCRIPT := preload("res://scripts/network/network_enemy_manager.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var manager := Node.new()
	manager.set_script(ENEMY_MANAGER_SCRIPT)
	root.add_child(manager)

	var enemy := CharacterBody3D.new()
	enemy.set_script(ENEMY_SCRIPT)
	enemy.set("persistent_id", "enemy:replication:test")
	enemy.set("max_health", 60)
	enemy.position = Vector3(3, 1, -4)
	enemy.rotation.y = 0.8
	root.add_child(enemy)

	var batch: Dictionary = manager.call("build_enemy_batch")
	var states: Array = batch.get("states", []) as Array
	if states.size() != 1 or str((states[0] as Dictionary).get("id", "")) != "enemy:replication:test":
		_fail("Server enemy batch did not contain the stable enemy")
		return
	enemy.position = Vector3(20, 2, 20)
	enemy.rotation.y = 0.0
	enemy.set("health", 12)
	var applied: Dictionary = manager.call("apply_enemy_batch", batch)
	if applied.get("ok", false) != true or int(applied.get("applied", 0)) != 1:
		_fail("Valid enemy snapshot batch was rejected")
		return
	if enemy.global_position != Vector3(3, 1, -4) or int(enemy.get("health")) != 60:
		_fail("Enemy transform/health did not restore from authoritative snapshot")
		return
	var stale: Dictionary = manager.call("apply_enemy_batch", batch)
	if str(stale.get("error", "")) != "stale_sequence":
		_fail("Stale enemy batch was not rejected")
		return
	var invalid: Dictionary = manager.call("apply_enemy_batch", {
		"protocol": 1,
		"sequence": 2,
		"states": [{"id": "enemy:bad", "position": "not_vector"}]
	})
	if str(invalid.get("error", "")) != "invalid_enemy_state":
		_fail("Malformed enemy snapshot was accepted")
		return

	print("NETWORK_ENEMY_MANAGER_OK sequence=1 health=60")
	quit(0)

func _fail(message: String) -> void:
	printerr("NETWORK_ENEMY_MANAGER_FAILED: %s" % message)
	quit(1)
