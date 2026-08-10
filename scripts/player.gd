extends CharacterBody3D

const ITEM_DB := preload("res://scripts/item_db.gd")
const TEX_METAL := preload("res://assets/textures/metal.svg")
const TEX_CLOTH := preload("res://assets/textures/cloth.svg")
const HERO_MODEL_PATH := "res://assets/models/characters/retro_fantasy_hero.glb"

@export var move_speed := 6.0
@export var sprint_speed := 9.0
@export var acceleration := 18.0
@export var jump_velocity := 6.0
@export var mouse_sensitivity := 0.0022
@export var interaction_distance := 3.0
@export var attack_range := 2.8
@export var attack_cooldown := 0.52
@export var max_health := 100
@export var visual_ground_clearance := 0.08

var gravity := 18.0
var health := 100
var attack_timer := 0.0
var walk_phase := 0.0
var camera_pivot: Node3D
var camera: Camera3D
var visual: Node3D
var generated_hero: Node3D
var generated_arm_l: Node3D
var generated_arm_r: Node3D
var generated_elbow_l: Node3D
var generated_elbow_r: Node3D
var generated_leg_l: Node3D
var generated_leg_r: Node3D
var generated_knee_l: Node3D
var generated_knee_r: Node3D
var generated_body: Node3D
var generated_head: Node3D
var generated_cape: Node3D
var generated_attack_active: bool = false
var spawn_position := Vector3.ZERO

var inventory: Dictionary = {"Rusty Sword": 1}
var equipped_weapon := "Rusty Sword"
var equipped_armor := ""
var inventory_open := false

var interaction_label: Label
var health_label: Label
var equipment_label: Label
var inventory_panel: ColorRect
var inventory_label: Label
var status_label: Label

func _ready() -> void:
	add_to_group("player")
	camera_pivot = $CameraPivot
	camera = $CameraPivot/SpringArm3D/Camera3D
	visual = $Visual
	_install_generated_hero_model()
	# Keep the rendered boots slightly above the mathematical collision plane.
	# This prevents faceted terrain from visually cutting through the model.
	visual.position.y = visual_ground_clearance
	spawn_position = global_position
	health = max_health
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_player_hud()
	_refresh_hud()


func _install_generated_hero_model() -> void:
	# The project remains playable before the terminal asset build has run.
	# Once the GLB exists Godot imports it as a PackedScene and it replaces
	# the temporary primitive player mesh without changing movement/collision.
	if visual == null or not ResourceLoader.exists(HERO_MODEL_PATH):
		return
	var hero_scene := load(HERO_MODEL_PATH) as PackedScene
	if hero_scene == null:
		push_warning("Could not load generated hero model: %s" % HERO_MODEL_PATH)
		return
	for child in visual.get_children():
		if child is Node3D:
			(child as Node3D).visible = false
	var hero := hero_scene.instantiate() as Node3D
	if hero == null:
		push_warning("Generated hero scene had no 3D root")
		return
	hero.name = "GeneratedRetroFantasyHero"
	hero.scale = Vector3.ONE
	visual.add_child(hero)
	generated_hero = hero
	generated_arm_l = hero.find_child("HeroArmPivotL", true, false) as Node3D
	generated_arm_r = hero.find_child("HeroArmPivotR", true, false) as Node3D
	generated_elbow_l = hero.find_child("HeroElbowPivotL", true, false) as Node3D
	generated_elbow_r = hero.find_child("HeroElbowPivotR", true, false) as Node3D
	generated_leg_l = hero.find_child("HeroLegPivotL", true, false) as Node3D
	generated_leg_r = hero.find_child("HeroLegPivotR", true, false) as Node3D
	generated_knee_l = hero.find_child("HeroKneePivotL", true, false) as Node3D
	generated_knee_r = hero.find_child("HeroKneePivotR", true, false) as Node3D
	generated_body = hero.find_child("HeroBodyPivot", true, false) as Node3D
	generated_head = hero.find_child("HeroHeadPivot", true, false) as Node3D
	generated_cape = hero.find_child("HeroCapePivot", true, false) as Node3D

func _build_player_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110

	health_label = Label.new()
	health_label.position = Vector2(10, 300)
	health_label.add_theme_font_size_override("font_size", 12)
	layer.add_child(health_label)

	equipment_label = Label.new()
	equipment_label.position = Vector2(10, 316)
	equipment_label.add_theme_font_size_override("font_size", 10)
	layer.add_child(equipment_label)

	interaction_label = Label.new()
	interaction_label.position = Vector2(235, 315)
	interaction_label.add_theme_font_size_override("font_size", 12)
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.size = Vector2(170, 24)
	layer.add_child(interaction_label)

	status_label = Label.new()
	status_label.position = Vector2(430, 316)
	status_label.size = Vector2(195, 36)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", 10)
	layer.add_child(status_label)

	inventory_panel = ColorRect.new()
	inventory_panel.position = Vector2(145, 62)
	inventory_panel.size = Vector2(350, 225)
	inventory_panel.color = Color(0.035, 0.025, 0.075, 0.90)
	inventory_panel.visible = false
	layer.add_child(inventory_panel)

	inventory_label = Label.new()
	inventory_label.position = Vector2(18, 14)
	inventory_label.size = Vector2(314, 197)
	inventory_label.add_theme_font_size_override("font_size", 12)
	inventory_panel.add_child(inventory_label)

	add_child(layer)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		_toggle_inventory()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not inventory_open:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-55.0), deg_to_rad(35.0))

	if event.is_action_pressed("ui_cancel"):
		if inventory_open:
			_toggle_inventory()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

	if inventory_open:
		return
	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("attack"):
		_try_attack()
	if event.is_action_pressed("equip_next"):
		_cycle_equipment()

func _physics_process(delta: float) -> void:
	attack_timer = max(attack_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0
		if Input.is_action_just_pressed("jump") and not inventory_open:
			velocity.y = jump_velocity

	var input_vec: Vector2 = Vector2.ZERO
	if not inventory_open:
		input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir: Vector3 = (transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)).normalized()
	var sprinting: bool = Input.is_action_pressed("sprint") and input_vec.length() > 0.05
	var target_speed: float = sprint_speed if sprinting else move_speed
	var target_velocity: Vector3 = wish_dir * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if wish_dir.length() > 0.05:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(wish_dir.x, wish_dir.z) - rotation.y, 10.0 * delta)

	move_and_slide()
	_animate_visual(delta, input_vec.length(), sprinting)
	_update_interaction_prompt()

func _animate_generated_hero(delta: float, input_strength: float, sprinting: bool) -> void:
	var blend: float = min(delta * 12.0, 1.0)
	visual.position.y = lerp(visual.position.y, visual_ground_clearance, blend)

	if not is_on_floor():
		var fall_tilt: float = -10.0 if velocity.y > 0.0 else 12.0
		_set_pivot_x(generated_body, -3.0 if velocity.y > 0.0 else 5.0, blend)
		_set_pivot_x(generated_leg_l, -18.0, blend)
		_set_pivot_x(generated_leg_r, 18.0, blend)
		_set_pivot_x(generated_knee_l, 24.0, blend)
		_set_pivot_x(generated_knee_r, 24.0, blend)
		_set_pivot_x(generated_arm_l, fall_tilt, blend)
		_set_pivot_x(generated_elbow_l, -18.0, blend)
		if not generated_attack_active:
			_set_pivot_x(generated_arm_r, fall_tilt, blend)
			_set_pivot_x(generated_elbow_r, -18.0, blend)
		_set_pivot_x(generated_cape, 22.0, blend)
		_set_pivot_z(generated_head, 0.0, blend)
		return

	if input_strength > 0.05:
		walk_phase += delta * (12.8 if sprinting else 8.2)
		var wave: float = sin(walk_phase)
		if sprinting:
			# Running is a separate pose: forward lean, bent elbows, high knees
			# and a much wider stride instead of a sped-up walk cycle.
			_set_pivot_x(generated_body, -11.0, blend)
			_set_pivot_z(generated_body, wave * 2.2, blend)
			_set_pivot_x(generated_leg_l, -wave * 48.0, blend)
			_set_pivot_x(generated_leg_r, wave * 48.0, blend)
			_set_pivot_x(generated_knee_l, max(0.0, wave) * 42.0 + 8.0, blend)
			_set_pivot_x(generated_knee_r, max(0.0, -wave) * 42.0 + 8.0, blend)
			_set_pivot_x(generated_arm_l, wave * 43.0, blend)
			_set_pivot_x(generated_elbow_l, -62.0, blend)
			if not generated_attack_active:
				_set_pivot_x(generated_arm_r, -wave * 43.0, blend)
				_set_pivot_x(generated_elbow_r, -62.0, blend)
			_set_pivot_z(generated_head, -wave * 2.0, blend)
			_set_pivot_x(generated_cape, 22.0 + abs(wave) * 16.0, blend)
		else:
			_set_pivot_x(generated_body, 0.0, blend)
			_set_pivot_z(generated_body, wave * 1.1, blend)
			_set_pivot_x(generated_leg_l, -wave * 25.0, blend)
			_set_pivot_x(generated_leg_r, wave * 25.0, blend)
			_set_pivot_x(generated_knee_l, max(0.0, wave) * 12.0, blend)
			_set_pivot_x(generated_knee_r, max(0.0, -wave) * 12.0, blend)
			_set_pivot_x(generated_arm_l, wave * 20.0, blend)
			_set_pivot_x(generated_elbow_l, -8.0, blend)
			if not generated_attack_active:
				_set_pivot_x(generated_arm_r, -wave * 20.0, blend)
				_set_pivot_x(generated_elbow_r, -8.0, blend)
			_set_pivot_z(generated_head, -wave * 1.0, blend)
			_set_pivot_x(generated_cape, 8.0 + abs(wave) * 7.0, blend)
	else:
		walk_phase += delta * 2.1
		var breath: float = sin(walk_phase) * 1.8
		_set_pivot_x(generated_body, breath * 0.3, blend)
		_set_pivot_z(generated_body, 0.0, blend)
		_set_pivot_x(generated_leg_l, 0.0, blend)
		_set_pivot_x(generated_leg_r, 0.0, blend)
		_set_pivot_x(generated_knee_l, 0.0, blend)
		_set_pivot_x(generated_knee_r, 0.0, blend)
		_set_pivot_x(generated_arm_l, breath, blend)
		_set_pivot_x(generated_elbow_l, -5.0, blend)
		if not generated_attack_active:
			_set_pivot_x(generated_arm_r, -breath, blend)
			_set_pivot_x(generated_elbow_r, -5.0, blend)
		_set_pivot_z(generated_head, sin(walk_phase * 0.55) * 1.1, blend)
		_set_pivot_x(generated_cape, 5.0 + abs(breath), blend)


func _set_pivot_x(pivot: Node3D, degrees: float, blend: float) -> void:
	if pivot != null:
		pivot.rotation_degrees.x = lerp(pivot.rotation_degrees.x, degrees, blend)

func _set_pivot_z(pivot: Node3D, degrees: float, blend: float) -> void:
	if pivot != null:
		pivot.rotation_degrees.z = lerp(pivot.rotation_degrees.z, degrees, blend)

func _animate_visual(delta: float, input_strength: float, sprinting: bool) -> void:
	if visual == null:
		return
	if generated_hero != null:
		_animate_generated_hero(delta, input_strength, sprinting)
		return
	var arm_l := get_node_or_null("Visual/ArmL") as Node3D
	var arm_r := get_node_or_null("Visual/ArmR") as Node3D
	var leg_l := get_node_or_null("Visual/LegL") as Node3D
	var leg_r := get_node_or_null("Visual/LegR") as Node3D
	var cape := get_node_or_null("Visual/Cape") as Node3D

	if input_strength > 0.05 and is_on_floor():
		walk_phase += delta * (12.0 if sprinting else 8.5)
		var swing: float = sin(walk_phase) * (34.0 if sprinting else 24.0)
		if arm_l != null:
			arm_l.rotation_degrees.x = swing
		if arm_r != null:
			arm_r.rotation_degrees.x = -swing
		if leg_l != null:
			leg_l.rotation_degrees.x = -swing * 0.75
		if leg_r != null:
			leg_r.rotation_degrees.x = swing * 0.75
		if cape != null:
			cape.rotation_degrees.x = 8.0 + abs(sin(walk_phase)) * (8.0 if sprinting else 4.0)
		# Limb swing communicates walking without moving the entire character
		# vertically relative to its collider and the terrain.
		visual.position.y = lerp(visual.position.y, visual_ground_clearance, min(delta * 12.0, 1.0))
	else:
		walk_phase += delta * 2.0
		visual.position.y = lerp(visual.position.y, visual_ground_clearance, min(delta * 8.0, 1.0))
		if arm_l != null:
			arm_l.rotation_degrees.x = lerp(arm_l.rotation_degrees.x, 0.0, min(delta * 8.0, 1.0))
		if arm_r != null:
			arm_r.rotation_degrees.x = lerp(arm_r.rotation_degrees.x, 0.0, min(delta * 8.0, 1.0))
		if leg_l != null:
			leg_l.rotation_degrees.x = lerp(leg_l.rotation_degrees.x, 0.0, min(delta * 8.0, 1.0))
		if leg_r != null:
			leg_r.rotation_degrees.x = lerp(leg_r.rotation_degrees.x, 0.0, min(delta * 8.0, 1.0))
		if cape != null:
			cape.rotation_degrees.x = lerp(cape.rotation_degrees.x, 4.0, min(delta * 5.0, 1.0))

func _get_nearest_interactable() -> Node:
	var best: Node = null
	var best_distance: float = interaction_distance
	for node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var node_3d := node as Node3D
		var distance: float = global_position.distance_to(node_3d.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best

func _try_interact() -> void:
	var target: Node = _get_nearest_interactable()
	if target != null and target.has_method("interact"):
		target.interact(self)

func _update_interaction_prompt() -> void:
	if interaction_label == null:
		return
	var target: Node = _get_nearest_interactable()
	if target != null and target.has_method("get_interaction_text"):
		interaction_label.text = target.get_interaction_text()
	else:
		interaction_label.text = ""

func _try_attack() -> void:
	if attack_timer > 0.0:
		return
	attack_timer = attack_cooldown
	_play_attack_animation()

	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best_enemy: Node3D = null
	var best_distance: float = attack_range
	for node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var enemy := node as Node3D
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= 0.01 or distance > best_distance:
			continue
		var direction: Vector3 = offset.normalized()
		if forward.dot(direction) < 0.20:
			continue
		best_enemy = enemy
		best_distance = distance

	if best_enemy != null and best_enemy.has_method("receive_damage"):
		var attack_damage: int = _get_attack_damage()
		best_enemy.receive_damage(attack_damage, self)
		_set_status("Hit for %d" % attack_damage)

func _play_attack_animation() -> void:
	if generated_arm_r != null:
		generated_attack_active = true
		generated_arm_r.rotation_degrees = Vector3(-52.0, 0.0, -24.0)
		var generated_tween := create_tween()
		generated_tween.tween_property(generated_arm_r, "rotation_degrees", Vector3(42.0, 0.0, 34.0), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		generated_tween.tween_property(generated_arm_r, "rotation_degrees", Vector3.ZERO, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		generated_tween.finished.connect(_finish_generated_attack)
		return
	var pivot := get_node_or_null("Visual/WeaponPivot") as Node3D
	if pivot == null:
		return
	pivot.rotation_degrees = Vector3(0, 0, -25)
	var tween := create_tween()
	tween.tween_property(pivot, "rotation_degrees", Vector3(0, 0, -115), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "rotation_degrees", Vector3(0, 0, -25), 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func _finish_generated_attack() -> void:
	generated_attack_active = false

func _get_attack_damage() -> int:
	return max(8, ITEM_DB.get_damage(equipped_weapon))

func receive_damage(amount: int) -> void:
	var armor: int = ITEM_DB.get_armor(equipped_armor)
	var final_damage: int = max(1, amount - armor)
	health = max(0, health - final_damage)
	_set_status("-%d HP" % final_damage)
	_refresh_hud()
	if health <= 0:
		_respawn()

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	health = max_health
	_set_status("You awaken by the old road")
	_refresh_hud()

func receive_loot(item_name: String, amount: int) -> void:
	inventory[item_name] = int(inventory.get(item_name, 0)) + amount
	_set_status("Found %s" % item_name)
	_auto_equip_upgrade(item_name)
	_refresh_hud()

func _auto_equip_upgrade(item_name: String) -> void:
	var item_type: String = ITEM_DB.get_type(item_name)
	if item_type == "weapon":
		if ITEM_DB.get_damage(item_name) > ITEM_DB.get_damage(equipped_weapon):
			equip_item(item_name)
	elif item_type == "armor":
		if equipped_armor.is_empty() or ITEM_DB.get_armor(item_name) > ITEM_DB.get_armor(equipped_armor):
			equip_item(item_name)

func equip_item(item_name: String) -> void:
	if int(inventory.get(item_name, 0)) <= 0:
		return
	var item_type: String = ITEM_DB.get_type(item_name)
	if item_type == "weapon":
		equipped_weapon = item_name
	elif item_type == "armor":
		equipped_armor = item_name
	else:
		return
	_update_equipment_visuals()
	_set_status("Equipped %s" % item_name)
	_refresh_hud()

func _cycle_equipment() -> void:
	var equippable: Array[String] = []
	for key in inventory.keys():
		var item_name: String = str(key)
		if int(inventory[key]) > 0 and ITEM_DB.is_equippable(item_name):
			equippable.append(item_name)
	if equippable.is_empty():
		return
	equippable.sort()
	var current_index: int = -1
	for i in range(equippable.size()):
		if equippable[i] == equipped_weapon or equippable[i] == equipped_armor:
			current_index = i
			break
	equip_item(equippable[(current_index + 1) % equippable.size()])

func _toggle_inventory() -> void:
	inventory_open = not inventory_open
	inventory_panel.visible = inventory_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if inventory_open else Input.MOUSE_MODE_CAPTURED
	_refresh_hud()

func _refresh_hud() -> void:
	if health_label == null:
		return
	health_label.text = "HP  %d / %d" % [health, max_health]
	var armor_text: String = equipped_armor if not equipped_armor.is_empty() else "None"
	equipment_label.text = "Weapon: %s   Armor: %s" % [equipped_weapon, armor_text]

	var lines: Array[String] = []
	lines.append("INVENTORY")
	lines.append("------------------------------")
	var keys: Array = inventory.keys()
	keys.sort()
	for key in keys:
		var item_name: String = str(key)
		var marker: String = ""
		if item_name == equipped_weapon or item_name == equipped_armor:
			marker = "  [EQUIPPED]"
		lines.append("%s  x%d%s" % [item_name, int(inventory[key]), marker])
	lines.append("")
	lines.append("I close   •   R equip next")
	inventory_label.text = "\n".join(lines)

func _update_equipment_visuals() -> void:
	var blade := get_node_or_null("Visual/WeaponPivot/Blade") as MeshInstance3D
	if blade != null:
		var blade_material := StandardMaterial3D.new()
		blade_material.roughness = 0.35
		blade_material.albedo_color = Color("94d7ff") if equipped_weapon == "Moon Blade" else Color("a5a8ad")
		blade_material.albedo_texture = TEX_METAL
		blade.material_override = blade_material
	var torso := get_node_or_null("Visual/Torso") as MeshInstance3D
	if torso != null:
		var torso_material := StandardMaterial3D.new()
		torso_material.roughness = 0.9
		torso_material.albedo_color = Color("434754") if equipped_armor == "Warden Mail" else Color("302b43")
		torso_material.albedo_texture = TEX_METAL if equipped_armor == "Warden Mail" else TEX_CLOTH
		torso.material_override = torso_material

func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
