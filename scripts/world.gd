extends Node3D

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const LOOT_SCRIPT := preload("res://scripts/loot.gd")
const RETRO_SHADER := preload("res://shaders/retro_post.gdshader")

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_paths_and_hills()
	_build_ruin()
	_build_watchtower()
	_build_forest()
	_spawn_loot()
	_spawn_enemies()
	_spawn_player()
	_build_retro_postprocess()
	_build_hud()

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("24106d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6859c9")
	env.ambient_light_energy = 0.82
	env.fog_enabled = true
	env.fog_light_color = Color("6158a8")
	env.fog_density = 0.016
	env.fog_sky_affect = 0.9
	world_env.environment = env
	add_child(world_env)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-38, -32, 0)
	moon.light_color = Color("c3ceff")
	moon.light_energy = 1.45
	moon.shadow_enabled = true
	add_child(moon)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 140, 0)
	fill.light_color = Color("6144b5")
	fill.light_energy = 0.28
	add_child(fill)

func _mat(color: Color, rough := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	return material

func _mesh_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color, rough := 1.0) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.material_override = _mat(color, rough)
	parent.add_child(mesh_instance)
	return mesh_instance

func _mesh_cylinder(parent: Node3D, node_name: String, height: float, top_radius: float, bottom_radius: float, pos: Vector3, color: Color, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.height = height
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = _mat(color)
	parent.add_child(mesh_instance)
	return mesh_instance

func _mesh_sphere(parent: Node3D, node_name: String, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.material_override = _mat(color)
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_static_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(color)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body

func _build_ground() -> void:
	_add_static_box(self, Vector3(0, -1, 0), Vector3(220, 2, 220), Color("315d2f"))

func _build_paths_and_hills() -> void:
	for i in range(18):
		var z := 20.0 - i * 6.0
		_add_static_box(self, Vector3(0, 0.02, z), Vector3(5.5, 0.08, 5.2), Color("716b57"))
	var hills := [
		[Vector3(-34, 1.0, -20), Vector3(22, 2.0, 18)],
		[Vector3(42, 1.5, 14), Vector3(28, 3.0, 24)],
		[Vector3(-50, 2.0, 48), Vector3(30, 4.0, 25)],
		[Vector3(55, 2.5, -55), Vector3(36, 5.0, 30)],
		[Vector3(-62, 1.5, -58), Vector3(30, 3.0, 26)]
	]
	for hill in hills:
		_add_static_box(self, hill[0], hill[1], Color("3c6c37"))

func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 82426
	for i in range(150):
		var p := Vector3(rng.randf_range(-95, 95), 0, rng.randf_range(-95, 95))
		if abs(p.x) < 6.0 and p.z > -90.0 and p.z < 35.0:
			continue
		if Vector2(p.x - 28.0, p.z + 45.0).length() < 20.0:
			continue
		var tree := Node3D.new()
		tree.position = p
		_mesh_cylinder(tree, "Trunk", rng.randf_range(3.5, 6.5), 0.22, 0.38, Vector3(0, 2.4, 0), Color("3b271d"))
		for j in range(3):
			_mesh_cylinder(tree, "Crown%d" % j, 2.6, 0.0, 1.5 - j * 0.2, Vector3(0, 3.2 + j * 1.05, 0), Color("153a22"))
		add_child(tree)

func _build_ruin() -> void:
	var base := Vector3(28, 0, -45)
	_add_static_box(self, base + Vector3(0, 2, 0), Vector3(18, 4, 12), Color("424452"))
	_add_static_box(self, base + Vector3(0, 6.0, -5.0), Vector3(14, 4, 1.8), Color("555667"))
	_add_static_box(self, base + Vector3(-7, 8.0, -4.5), Vector3(3, 9, 3), Color("383a47"))
	_add_static_box(self, base + Vector3(7, 8.0, -4.5), Vector3(3, 9, 3), Color("383a47"))
	_add_static_box(self, base + Vector3(0, 1.0, 10), Vector3(5, 2, 16), Color("807b75"))
	_add_static_box(self, base + Vector3(-10, 1.8, 1), Vector3(2, 3.6, 12), Color("4a4c55"))
	_add_static_box(self, base + Vector3(10, 1.8, 1), Vector3(2, 3.6, 12), Color("4a4c55"))

func _build_watchtower() -> void:
	var base := Vector3(-55, 0, -68)
	_add_static_box(self, base + Vector3(0, 6, 0), Vector3(7, 12, 7), Color("3e414b"))
	_add_static_box(self, base + Vector3(0, 12.8, 0), Vector3(10, 1.6, 10), Color("50535d"))
	for x in [-4.2, 4.2]:
		for z in [-4.2, 4.2]:
			_add_static_box(self, base + Vector3(x, 15.2, z), Vector3(1.5, 5, 1.5), Color("353741"))

func _spawn_loot() -> void:
	_create_loot(Vector3(5, 0.8, -18), "Ancient Coin", Color("d8b84b"))
	_create_loot(Vector3(30, 1.0, -41), "Moon Shard", Color("8bd2ff"))
	_create_loot(Vector3(-55, 1.0, -63), "Old Key", Color("c59a57"))
	_create_loot(Vector3(31, 1.0, -52), "Moon Blade", Color("80d4ff"))
	_create_loot(Vector3(-52, 1.0, -72), "Warden Mail", Color("707887"))

func _create_loot(pos: Vector3, item_name: String, color: Color) -> void:
	var area := Area3D.new()
	area.position = pos
	area.set_script(LOOT_SCRIPT)
	area.item_name = item_name
	var mesh := MeshInstance3D.new()
	var shape_mesh := BoxMesh.new()
	if item_name == "Moon Blade":
		shape_mesh.size = Vector3(0.14, 1.25, 0.10)
	elif item_name == "Warden Mail":
		shape_mesh.size = Vector3(0.75, 0.85, 0.30)
	else:
		shape_mesh.size = Vector3(0.45, 0.45, 0.45)
	mesh.mesh = shape_mesh
	mesh.material_override = _mat(color, 0.3)
	area.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	col.shape = shape
	area.add_child(col)
	add_child(area)

func spawn_combat_loot(pos: Vector3) -> void:
	var roll := randi() % 100
	if roll < 30:
		_create_loot(pos + Vector3(0, 0.7, 0), "Moon Shard", Color("8bd2ff"))
	else:
		_create_loot(pos + Vector3(0, 0.7, 0), "Ancient Coin", Color("d8b84b"))

func _spawn_enemies() -> void:
	_create_enemy(Vector3(10, 1.0, -30))
	_create_enemy(Vector3(33, 1.0, -48))
	_create_enemy(Vector3(-48, 1.0, -58))
	_create_enemy(Vector3(-58, 1.0, -75))

func _create_enemy(pos: Vector3) -> void:
	var enemy := CharacterBody3D.new()
	enemy.position = pos
	enemy.set_script(ENEMY_SCRIPT)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	enemy.add_child(col)
	_build_warden_visual(enemy)
	add_child(enemy)

func _build_warden_visual(enemy: CharacterBody3D) -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	enemy.add_child(visual)

	_mesh_box(visual, "Torso", Vector3(0.72, 0.9, 0.42), Vector3(0, 1.25, 0), Color("4b514e"))
	_mesh_box(visual, "Hips", Vector3(0.58, 0.30, 0.38), Vector3(0, 0.68, 0), Color("303531"))
	_mesh_sphere(visual, "Head", 0.28, Vector3(0, 1.92, 0), Color("9da28f"))
	_mesh_cylinder(visual, "Helmet", 0.34, 0.28, 0.36, Vector3(0, 2.10, 0), Color("343943"))
	_mesh_cylinder(visual, "ArmL", 0.78, 0.12, 0.14, Vector3(-0.48, 1.22, 0), Color("444a47"), Vector3(0, 0, -7))
	_mesh_cylinder(visual, "ArmR", 0.78, 0.12, 0.14, Vector3(0.48, 1.22, 0), Color("444a47"), Vector3(0, 0, 7))
	_mesh_cylinder(visual, "LegL", 0.88, 0.13, 0.15, Vector3(-0.20, 0.25, 0), Color("252a27"))
	_mesh_cylinder(visual, "LegR", 0.88, 0.13, 0.15, Vector3(0.20, 0.25, 0), Color("252a27"))
	_mesh_box(visual, "TatteredCape", Vector3(0.72, 1.05, 0.08), Vector3(0, 1.05, 0.25), Color("241b28"))
	_mesh_box(visual, "EyeGlow", Vector3(0.28, 0.06, 0.04), Vector3(0, 1.96, -0.27), Color("cc4a72"), 0.25)

	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.52, 1.18, -0.02)
	weapon_pivot.rotation_degrees = Vector3(0, 0, 30)
	visual.add_child(weapon_pivot)
	_mesh_box(weapon_pivot, "Blade", Vector3(0.11, 1.15, 0.09), Vector3(0, 0.58, 0), Color("858b91"), 0.35)
	_mesh_box(weapon_pivot, "Guard", Vector3(0.42, 0.08, 0.10), Vector3(0, -0.02, 0), Color("5d4a36"))
	_mesh_box(weapon_pivot, "Grip", Vector3(0.10, 0.35, 0.10), Vector3(0, -0.20, 0), Color("38271e"))

func _spawn_player() -> void:
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 1.2, 22)
	player.set_script(PLAYER_SCRIPT)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	player.add_child(collision)

	_build_player_visual(player)

	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	pivot.position.y = 1.65
	player.add_child(pivot)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	arm.spring_length = 5.5
	arm.margin = 0.2
	pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 66
	arm.add_child(cam)
	add_child(player)

func _build_player_visual(player: CharacterBody3D) -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	player.add_child(visual)

	_mesh_box(visual, "Torso", Vector3(0.78, 0.95, 0.44), Vector3(0, 1.28, 0), Color("29273b"))
	_mesh_box(visual, "Hips", Vector3(0.62, 0.32, 0.40), Vector3(0, 0.70, 0), Color("1d1d27"))
	_mesh_sphere(visual, "Head", 0.29, Vector3(0, 1.98, 0), Color("b9ad92"))
	_mesh_cylinder(visual, "Helmet", 0.34, 0.27, 0.37, Vector3(0, 2.16, 0), Color("535766"))
	_mesh_cylinder(visual, "ArmL", 0.80, 0.13, 0.15, Vector3(-0.50, 1.25, 0), Color("343243"), Vector3(0, 0, -8))
	_mesh_cylinder(visual, "ArmR", 0.80, 0.13, 0.15, Vector3(0.50, 1.25, 0), Color("343243"), Vector3(0, 0, 8))
	_mesh_cylinder(visual, "LegL", 0.90, 0.14, 0.16, Vector3(-0.21, 0.26, 0), Color("242331"))
	_mesh_cylinder(visual, "LegR", 0.90, 0.14, 0.16, Vector3(0.21, 0.26, 0), Color("242331"))
	_mesh_box(visual, "Cape", Vector3(0.78, 1.20, 0.08), Vector3(0, 1.10, 0.26), Color("4d2239"))
	_mesh_box(visual, "ShoulderL", Vector3(0.30, 0.18, 0.48), Vector3(-0.47, 1.58, 0), Color("4c4e59"))
	_mesh_box(visual, "ShoulderR", Vector3(0.30, 0.18, 0.48), Vector3(0.47, 1.58, 0), Color("4c4e59"))

	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.55, 1.22, -0.05)
	weapon_pivot.rotation_degrees = Vector3(0, 0, -25)
	visual.add_child(weapon_pivot)
	_mesh_box(weapon_pivot, "Blade", Vector3(0.12, 1.25, 0.09), Vector3(0, 0.62, 0), Color("a5a8ad"), 0.35)
	_mesh_box(weapon_pivot, "Guard", Vector3(0.46, 0.08, 0.11), Vector3(0, -0.02, 0), Color("776344"))
	_mesh_box(weapon_pivot, "Grip", Vector3(0.11, 0.36, 0.11), Vector3(0, -0.22, 0), Color("3b251c"))

func _build_retro_postprocess() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = RETRO_SHADER
	rect.material = material
	layer.add_child(rect)
	add_child(layer)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	label.text = "BUILD 0.08  •  WASD move  •  Shift run  •  LMB attack  •  E interact  •  I inventory  •  R equip"
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 10)
	layer.add_child(label)
	var objective := Label.new()
	objective.text = "Defeat the Hollow Wardens. Search the ruin for the Moon Blade and the tower for Warden Mail."
	objective.position = Vector2(10, 24)
	objective.add_theme_font_size_override("font_size", 9)
	layer.add_child(objective)
	add_child(layer)
