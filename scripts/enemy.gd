extends CharacterBody3D

@export var enemy_name := "Hollow Warden"
@export var move_speed := 2.4
@export var detection_range := 13.0
@export var stop_range := 1.55
@export var max_health := 46
@export var attack_damage := 13
@export var attack_cooldown := 1.15

var gravity := 18.0
var target: Node3D
var health := 46
var attack_timer := 0.0
var stagger_timer := 0.0
var dead := false

func _ready() -> void:
	add_to_group("enemy")
	health = max_health

func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_timer = max(attack_timer - delta, 0.0)
	stagger_timer = max(stagger_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

	if target == null or not is_instance_valid(target):
		var players: Array[Node] = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0] is Node3D:
			target = players[0] as Node3D

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
			velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	move_and_slide()

func _try_attack() -> void:
	if attack_timer > 0.0 or target == null:
		return
	attack_timer = attack_cooldown
	_play_attack_animation()
	if target.has_method("receive_damage"):
		target.receive_damage(attack_damage)

func _play_attack_animation() -> void:
	var pivot := get_node_or_null("Visual/WeaponPivot") as Node3D
	if pivot == null:
		return
	pivot.rotation_degrees = Vector3(0, 0, 30)
	var tween := create_tween()
	tween.tween_property(pivot, "rotation_degrees", Vector3(0, 0, -55), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "rotation_degrees", Vector3(0, 0, 30), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func receive_damage(amount: int, attacker: Node = null) -> void:
	if dead:
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
	var world: Node = get_parent()
	if world != null and world.has_method("spawn_combat_loot"):
		world.spawn_combat_loot(global_position)
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		var tween := create_tween()
		tween.tween_property(visual, "rotation_degrees", Vector3(0, 0, 88), 0.28)
		tween.tween_property(visual, "scale", Vector3(0.85, 0.25, 0.85), 0.22)
		tween.tween_callback(queue_free)
	else:
		queue_free()
