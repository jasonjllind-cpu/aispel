extends Node3D

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const RETRO_SHADER := preload("res://shaders/retro_post.gdshader")

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_ruin()
	_build_forest()
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
	env.fog_density = 0.018
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
	fill.shadow_enabled = false
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
	_add_static_box(self, Vector3(0, -1, 0), Vector3(140, 2, 140), Color("315d2f"))
	for i in range(22):
		var x := -55.0 + float(i % 11) * 11.0
		var z := -48.0 + float(i / 11) * 95.0
		var h := 1.0 + float((i * 7) % 5) * 0.6
		_add_static_box(self, Vector3(x, h * 0.25 - 0.2, z), Vector3(8, h, 8), Color("44733a"))

func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 82426
	for i in range(75):
		var p := Vector3(rng.randf_range(-58, 58), 0, rng.randf_range(-58, 58))
		if p.length() < 12.0 or Vector2(p.x - 28.0, p.z + 25.0).length() < 15.0:
			continue
		var tree := Node3D.new()
		tree.position = p
		var trunk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 6
		cyl.rings = 1
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.34
		cyl.height = rng.randf_range(3.2, 5.8)
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
			cone.bottom_radius = 1.3 - j * 0.18
			cone.height = 2.4
			crown.mesh = cone
			crown.position.y = 3.0 + j * 1.0
			crown.material_override = _mat(Color("153a22"))
			tree.add_child(crown)
		add_child(tree)

func _build_ruin() -> void:
	var base := Vector3(28, 0, -25)
	_add_static_box(self, base + Vector3(0, 2, 0), Vector3(14, 4, 10), Color("424452"))
	_add_static_box(self, base + Vector3(0, 5.2, -4.2), Vector3(10, 3, 1.6), Color("555667"))
	_add_static_box(self, base + Vector3(-5.2, 7.2, -3.7), Vector3(2.3, 7, 2.3), Color("383a47"))
	_add_static_box(self, base + Vector3(5.2, 7.2, -3.7), Vector3(2.3, 7, 2.3), Color("383a47"))
	_add_static_box(self, base + Vector3(0, 1.2, 7), Vector3(4, 2.4, 12), Color("807b75"))

func _spawn_player() -> void:
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 1.2, 12)
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
	label.text = "RETRO FANTASY  •  WASD move  •  Shift run  •  Space jump  •  Mouse look"
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 11)
	layer.add_child(label)
	var objective := Label.new()
	objective.text = "Explore the moonlit ruins"
	objective.position = Vector2(10, 26)
	objective.add_theme_font_size_override("font_size", 10)
	layer.add_child(objective)
	add_child(layer)
