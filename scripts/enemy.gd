extends CharacterBody3D

@export var enemy_name := "Hollow Warden"
@export var move_speed := 2.4
@export var detection_range := 13.0
@export var stop_range := 1.55
@export var max_health := 46
@export var attack_damage := 13
@export var attack_cooldown := 1.15
@export var persistent_id := ""

var gravity := 18.0
var target: Node3D
var health := 46
var attack_timer := 0.0
var stagger_timer := 0.0
var walk_phase := 0.0
var dead := false
var network_session: Node

func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	if not persistent_id.is_empty():
		set_meta("stable_id", persistent_id)

func _physics_process(delta: float) -> void:
	# In co-op the host/server owns enemy simulation. Clients only display
	# snapshots supplied by NetworkEnemyManager.
	if _is_network_client():
		velocity = Vector3.ZERO
		return
	if dead:
		return
	attack_timer = max(attack_timer - delta, 0.0)
	stagger_timer = max(stagger_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

	if target == null or not is_instance_valid(target):
		target = _acquire_nearest_target()

	if target != null and stagger_timer <= 0.0:
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= detection_range and distance > stop_range:
			var dir: Vector3 = offset.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			look_at(global_position + dir, Vector3.UP)
		elif distance <= stop_range:
			velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
			_try_attack()
		else:
			target = _acquire_nearest_target()
			velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	move_and_slide()
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	_animate_visual(delta, horizontal_speed > 0.20)

func _acquire_nearest_target() -> Node3D:
	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group("player"))
	candidates.append_array(get_tree().get_nodes_in_group("network_player_target"))
	var nearest: Node3D
	var nearest_distance: float = INF
	for candidate in candidates:
		if not candidate is Node3D or not is_instance_valid(candidate):
			continue
		var distance: float = global_position.distance_squared_to((candidate as Node3D).global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate as Node3D
	return nearest

func _animate_visual(delta: float, moving: bool) -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	var arm_l := get_node_or_null("Visual/ArmL") as Node3D
	var arm_r := get_node_or_null("Visual/ArmR") as Node3D
	var leg_l := get_node_or_null("Visual/LegL") as Node3D
	var leg_r := get_node_or_null("Visual/LegR") as Node3D
	var cape := get_node_or_null("Visual/TatteredCape") as Node3D
	if moving and is_on_floor():
		walk_phase += delta * 6.8
		var swing: float = sin(walk_phase) * 18.0
		if arm_l != null:
			arm_l.rotation_degrees.x = swing
		if arm_r != null:
			arm_r.rotation_degrees.x = -swing * 0.6
		if leg_l != null:
			leg_l.rotation_degrees.x = -swing * 0.75
		if leg_r != null:
			leg_r.rotation_degrees.x = swing * 0.75
		if cape != null:
			cape.rotation_degrees.x = 7.0 + abs(sin(walk_phase)) * 5.0
		visual.position.y = abs(sin(walk_phase * 2.0)) * 0.025
	else:
		visual.position.y = lerp(visual.position.y, 0.0, min(delta * 7.0, 1.0))
		if arm_l != null:
			arm_l.rotation_degrees.x = lerp(arm_l.rotation_degrees.x, 0.0, min(delta * 7.0, 1.0))
		if arm_r != null:
			arm_r.rotation_degrees.x = lerp(arm_r.rotation_degrees.x, 0.0, min(delta * 7.0, 1.0))
		if leg_l != null:
			leg_l.rotation_degrees.x = lerp(leg_l.rotation_degrees.x, 0.0, min(delta * 7.0, 1.0))
		if leg_r != null:
			leg_r.rotation_degrees.x = lerp(leg_r.rotation_degrees.x, 0.0, min(delta * 7.0, 1.0))

func _try_attack() -> void:
	if _is_network_client() or attack_timer > 0.0 or target == null:
		return
	attack_timer = attack_cooldown
	_play_attack_animation()
	if target.has_method("receive_damage"):
		target.call("receive_damage", attack_damage)

func _play_attack_animation() -> void:
	var pivot := get_node_or_null("Visual/WeaponPivot") as Node3D
	if pivot == null:
		return
	pivot.rotation_degrees = Vector3(0, 0, 30)
	var tween := create_tween()
	tween.tween_property(pivot, "rotation_degrees", Vector3(0, 0, -55), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "rotation_degrees", Vector3(0, 0, 30), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func receive_damage(amount: int, attacker: Node = null) -> void:
	if _is_network_client() or dead:
		return
	health -= amount
	stagger_timer = 0.22
	if attacker is Node3D:
		var attacker_3d := attacker as Node3D
		target = attacker_3d
		var push: Vector3 = global_position - attacker_3d.global_position
		push.y = 0.0
		if push.length() > 0.01:
			push = push.normalized()
			velocity.x = push.x * 3.5
			velocity.z = push.z * 3.5
	_flash_hit()
	if health <= 0:
		_die()

func _flash_hit() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3(1.10, 0.92, 1.10), 0.06)
	tween.tween_property(visual, "scale", Vector3.ONE, 0.12)

func _die() -> void:
	dead = true
	remove_from_group("enemy")
	_record_persistent_death()

	var main_world: Node = get_tree().current_scene
	if main_world != null and main_world.has_method("spawn_combat_loot"):
		main_world.call("spawn_combat_loot", global_position)

	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		var tween := create_tween()
		tween.tween_property(visual, "rotation_degrees", Vector3(0, 0, 88), 0.28)
		tween.tween_property(visual, "scale", Vector3(0.85, 0.25, 0.85), 0.22)
		tween.tween_callback(queue_free)
	else:
		queue_free()

func _record_persistent_death() -> void:
	if persistent_id.is_empty():
		return
	var world_state := get_node_or_null("/root/WorldState")
	if world_state != null and world_state.has_method("set_entity_state"):
		world_state.call("set_entity_state", persistent_id, {"dead": true})

func _is_network_client() -> bool:
	if not is_instance_valid(network_session):
		var sessions: Array[Node] = get_tree().get_nodes_in_group("network_session")
		if not sessions.is_empty():
			network_session = sessions[0]
	return network_session != null and str(network_session.get("session_mode")) == "client"
