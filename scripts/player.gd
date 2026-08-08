extends CharacterBody3D

@export var move_speed := 6.0
@export var sprint_speed := 9.0
@export var acceleration := 18.0
@export var jump_velocity := 6.0
@export var mouse_sensitivity := 0.0022

var gravity := 18.0
var camera_pivot: Node3D
var camera: Camera3D
var visual: Node3D

func _ready() -> void:
	camera_pivot = $CameraPivot
	camera = $CameraPivot/SpringArm3D/Camera3D
	visual = $Visual
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-55.0), deg_to_rad(35.0))
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)).normalized()
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else move_speed
	var target_velocity := wish_dir * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if wish_dir.length() > 0.05:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(wish_dir.x, wish_dir.z) - rotation.y, 10.0 * delta)

	move_and_slide()
