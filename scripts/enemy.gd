extends CharacterBody3D

@export var move_speed := 2.4
@export var detection_range := 12.0
@export var stop_range := 1.8

var gravity := 18.0
var target: Node3D

func _ready() -> void:
	add_to_group("enemy")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if target == null or not is_instance_valid(target):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]
	if target != null:
		var offset := target.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= detection_range and distance > stop_range:
			var dir := offset.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			look_at(global_position + dir, Vector3.UP)
		else:
			velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	move_and_slide()
