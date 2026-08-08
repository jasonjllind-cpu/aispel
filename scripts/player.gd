extends CharacterBody3D

@export var move_speed := 6.0
@export var sprint_speed := 9.0
@export var acceleration := 18.0
@export var jump_velocity := 6.0
@export var mouse_sensitivity := 0.0022
@export var interaction_distance := 3.0

var gravity := 18.0
var camera_pivot: Node3D
var camera: Camera3D
var visual: Node3D
var loot_counts: Dictionary = {}
var interaction_label: Label
var loot_label: Label

func _ready() -> void:
	add_to_group("player")
	camera_pivot = $CameraPivot
	camera = $CameraPivot/SpringArm3D/Camera3D
	visual = $Visual
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_player_hud()

func _build_player_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110
	interaction_label = Label.new()
	interaction_label.position = Vector2(265, 315)
	interaction_label.add_theme_font_size_override("font_size", 12)
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.size = Vector2(110, 24)
	layer.add_child(interaction_label)
	loot_label = Label.new()
	loot_label.position = Vector2(10, 330)
	loot_label.add_theme_font_size_override("font_size", 10)
	layer.add_child(loot_label)
	add_child(layer)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-55.0), deg_to_rad(35.0))
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("interact"):
		_try_interact()

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
	_update_interaction_prompt()

func _get_nearest_interactable() -> Node:
	var best: Node = null
	var best_distance := interaction_distance
	for node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var distance := global_position.distance_to(node.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best

func _try_interact() -> void:
	var target := _get_nearest_interactable()
	if target != null and target.has_method("interact"):
		target.interact(self)

func _update_interaction_prompt() -> void:
	if interaction_label == null:
		return
	var target := _get_nearest_interactable()
	if target != null and target.has_method("get_interaction_text"):
		interaction_label.text = target.get_interaction_text()
	else:
		interaction_label.text = ""

func receive_loot(item_name: String, amount: int) -> void:
	loot_counts[item_name] = int(loot_counts.get(item_name, 0)) + amount
	var pieces: Array[String] = []
	for key in loot_counts.keys():
		pieces.append("%s x%d" % [key, loot_counts[key]])
	loot_label.text = "Loot: " + "   ".join(pieces)
