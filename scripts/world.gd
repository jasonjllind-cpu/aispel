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
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m

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
		var trunk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 6
		cyl.rings = 1
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.38
		cyl.height = rng.randf_range(3.5, 6.5)
		trunk.mesh = cyl
		trunk.position.y = cyl.height * 0.5
		trunk.material_override = _mat(Color("3b271d"))
		tree.add_child(trunk)
		for j in range(3):
			var crown := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.radial_segments = 7
			cone.rings = 1
			cone.top_radius = 0.0
			cone.bottom_radius = 1.5 - j * 0.2
			cone.height = 2.6
			crown.mesh = cone
			crown.position.y = 3.2 + j * 1.05
			crown.material_override = _mat(Color("153a22"))
			tree.add_child(crown)
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

func _create_loot(pos: Vector3, name: String, color: Color) -> void:
	var area := Area3D.new()
	area.position = pos
	area.set_script(LOOT_SCRIPT)
	area.item_name = name
	var mesh := MeshInstance3D.new()
	var shape_mesh := BoxMesh.new()
	shape_mesh.size = Vector3(0.45, 0.45, 0.45)
	mesh.mesh = shape_mesh
	mesh.material_override = _mat(color, 0.3)
	area.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	col.shape = shape
	area.add_child(col)
	add_child(area)

func _spawn_enemies() -> void:
	_create_enemy(Vector3(10, 1.0, -30))
	_create_enemy(Vector3(33, 1.0, -48))
	_create_enemy(Vector3(-48, 1.0, -58))

func _create_enemy(pos: Vector3) -> void:
	var enemy := CharacterBody3D.new()
	enemy.position = pos
	enemy.set_script(ENEMY_SCRIPT)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	enemy.add_child(col)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radial_segments = 7
	body_mesh.rings = 3
	body_mesh.radius = 0.38
	body_mesh.height = 1.65
	body.mesh = body_mesh
	body.position.y = 0.85
	body.material_override = _mat(Color("5f665a"))
	enemy.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 3
	sphere.radius = 0.28
	sphere.height = 0.56
	head.mesh = sphere
	head.position.y = 1.82
	head.material_override = _mat(Color("9ba08f"))
	enemy.add_child(head)
	add_child(enemy)

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
	var visual := Node3D.new()
	visual.name = "Visual"
	player.add_child(visual)
	var body_mesh := MeshInstance3D.new()
	var body_shape := CapsuleMesh.new()
	body_shape.radial_segments = 8
	body_shape.rings = 4
	body_shape.radius = 0.42
	body_shape.height = 1.7
	body_mesh.mesh = body_shape
	body_mesh.position.y = 0.9
	body_mesh.material_override = _mat(Color("272538"))
	visual.add_child(body_mesh)
	var head := MeshInstance3D.new()
	var head_shape := SphereMesh.new()
	head_shape.radial_segments = 8
	head_shape.rings = 4
	head_shape.radius = 0.32
	head_shape.height = 0.64
	head.mesh = head_shape
	head.position.y = 1.9
	head.material_override = _mat(Color("b9ad92"))
	visual.add_child(head)
	var sword := MeshInstance3D.new()
	var sword_shape := BoxMesh.new()
	sword_shape.size = Vector3(0.12, 1.8, 0.18)
	sword.mesh = sword_shape
	sword.position = Vector3(0.55, 1.2, 0)
	sword.rotation_degrees.z = -18
	sword.material_override = _mat(Color("a8b7c7"), 0.35)
	visual.add_child(sword)
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
	label.text = "RETRO FANTASY  •  WASD move  •  Shift run  •  Space jump  •  E interact"
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 11)
	layer.add_child(label)
	var objective := Label.new()
	objective.text = "Follow the old road. Search the ruins and tower."
	objective.position = Vector2(10, 26)
	objective.add_theme_font_size_override("font_size", 10)
	layer.add_child(objective)
	add_child(layer)
