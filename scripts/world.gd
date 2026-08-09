extends Node3D

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const LOOT_SCRIPT := preload("res://scripts/loot.gd")
const RETRO_SHADER := preload("res://shaders/retro_post.gdshader")
const TEX_GRASS := preload("res://assets/textures/grass.svg")
const TEX_STONE := preload("res://assets/textures/stone.svg")
const TEX_BARK := preload("res://assets/textures/bark.svg")
const TEX_METAL := preload("res://assets/textures/metal.svg")
const TEX_CLOTH := preload("res://assets/textures/cloth.svg")

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_old_road()
	_build_mountain_ring()
	_build_castle_ruin()
	_build_watchtower()
	_build_moon_shrine()
	_build_forest()
	_build_ground_details()
	_build_torches()
	_spawn_loot()
	_spawn_enemies()
	_spawn_player()
	_build_retro_postprocess()
	_build_hud()

func _build_environment() -> void:
	var theme_index: int = _seed_for("environment") % 4
	var background_colors: Array[Color] = [Color("29106f"), Color("102f54"), Color("4a172e"), Color("163d35")]
	var ambient_colors: Array[Color] = [Color("7667c7"), Color("5f8fbd"), Color("b06a83"), Color("62a28b")]
	var fog_colors: Array[Color] = [Color("625b9d"), Color("446f91"), Color("8a4c64"), Color("497f6d")]
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = background_colors[theme_index]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_colors[theme_index]
	env.ambient_light_energy = 0.72
	env.fog_enabled = true
	env.fog_light_color = fog_colors[theme_index]
	env.fog_density = 0.011
	env.fog_sky_affect = 0.88
	world_env.environment = env
	add_child(world_env)

	var moon_light := DirectionalLight3D.new()
	moon_light.rotation_degrees = Vector3(-40, -28, 0)
	moon_light.light_color = Color("c9d2ff")
	moon_light.light_energy = 1.30
	moon_light.shadow_enabled = true
	add_child(moon_light)

	var purple_fill := DirectionalLight3D.new()
	purple_fill.rotation_degrees = Vector3(-18, 145, 0)
	purple_fill.light_color = Color("6748b3")
	purple_fill.light_energy = 0.24
	purple_fill.shadow_enabled = false
	add_child(purple_fill)

	var moon := MeshInstance3D.new()
	moon.name = "Moon"
	var moon_mesh := SphereMesh.new()
	moon_mesh.radial_segments = 12
	moon_mesh.rings = 6
	moon_mesh.radius = 8.0
	moon_mesh.height = 16.0
	moon.mesh = moon_mesh
	moon.position = Vector3(58, 48, -92)
	moon.material_override = _mat(Color("dbe1ff"), 0.15)
	add_child(moon)

func _seed_for(scope_id: String) -> int:
	var world_state := get_node_or_null("/root/WorldState")
	if world_state != null and world_state.has_method("stable_seed"):
		return int(world_state.call("stable_seed", "legacy:%s" % scope_id))
	return int(("8242601:legacy:%s" % scope_id).hash() & 0x7fffffff)

func _mat(color: Color, rough: float = 1.0, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	if texture != null:
		material.albedo_texture = texture
	return material

func _mesh_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color, rough: float = 1.0, texture: Texture2D = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.material_override = _mat(color, rough, texture)
	parent.add_child(mesh_instance)
	return mesh_instance

func _mesh_cylinder(parent: Node3D, node_name: String, height: float, top_radius: float, bottom_radius: float, pos: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO, texture: Texture2D = null, segments: int = 7) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.height = height
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = _mat(color, 1.0, texture)
	parent.add_child(mesh_instance)
	return mesh_instance

func _mesh_sphere(parent: Node3D, node_name: String, radius: float, pos: Vector3, color: Color, mesh_scale: Vector3 = Vector3.ONE, texture: Texture2D = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.scale = mesh_scale
	mesh_instance.material_override = _mat(color, 1.0, texture)
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_static_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(color, 1.0, texture)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body

func _add_static_cylinder(parent: Node3D, pos: Vector3, height: float, radius: float, color: Color, texture: Texture2D = null, segments: int = 10) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.height = height
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, 1.0, texture)
	body.add_child(mesh_instance)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.height = height
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body

func _build_ground() -> void:
	var theme_index: int = _seed_for("ground_palette") % 4
	var ground_colors: Array[Color] = [Color("4c7044"), Color("476b63"), Color("725146"), Color("53634a")]
	var terrace_colors: Array[Color] = [Color("40643b"), Color("3c5d58"), Color("65443d"), Color("47583e")]
	_add_static_box(self, Vector3(0, -1.2, 0), Vector3(230, 2.4, 230), ground_colors[theme_index], TEX_GRASS)

	var terrace_positions: Array[Vector3] = [
		Vector3(-48, 0.35, 32), Vector3(48, 0.55, 38), Vector3(-67, 0.70, -18),
		Vector3(67, 0.85, -30), Vector3(-34, 0.45, -82), Vector3(60, 0.55, -82)
	]
	var terrace_sizes: Array[Vector3] = [
		Vector3(26, 0.7, 22), Vector3(30, 1.1, 24), Vector3(28, 1.4, 20),
		Vector3(28, 1.7, 25), Vector3(25, 0.9, 18), Vector3(30, 1.1, 20)
	]
	for i in range(terrace_positions.size()):
		_add_static_box(self, terrace_positions[i], terrace_sizes[i], terrace_colors[theme_index], TEX_GRASS)

func _build_old_road() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for("old_road")
	var phase: float = rng.randf_range(0.0, TAU)
	var bend: float = rng.randf_range(3.0, 8.0)
	var drift: float = rng.randf_range(-0.18, 0.38)
	for i in range(22):
		var fi: float = float(i)
		var z: float = 24.0 - fi * 5.0
		var x: float = sin(fi * 0.42 + phase) * bend + fi * drift
		var road_piece := _add_static_box(self, Vector3(x, 0.035, z), Vector3(5.4, 0.08, 5.2), Color("8b8068"))
		road_piece.rotation_degrees.y = sin(fi * 0.35 + phase) * 11.0
		if i % 3 == 0:
			_create_rock(Vector3(x - 3.8, 0.18, z + 1.0), Vector3(0.65, 0.45, 0.70), Color("66616a"))
		if i % 4 == 0:
			_create_rock(Vector3(x + 3.7, 0.15, z - 0.8), Vector3(0.55, 0.38, 0.60), Color("5d5962"))

func _build_mountain_ring() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for("mountain_ring")
	var mountain_positions: Array[Vector3] = [
		Vector3(-112, 20, -88), Vector3(-84, 16, -118), Vector3(-42, 22, -126),
		Vector3(0, 18, -132), Vector3(44, 24, -128), Vector3(84, 18, -116),
		Vector3(116, 22, -86), Vector3(-120, 18, 12), Vector3(122, 16, 18)
	]
	for i in range(mountain_positions.size()):
		var base_pos: Vector3 = mountain_positions[i]
		var pos := base_pos + Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(-2.0, 5.0), rng.randf_range(-6.0, 6.0))
		var height: float = rng.randf_range(30.0, 58.0)
		var radius: float = rng.randf_range(15.0, 29.0)
		_mesh_cylinder(self, "Mountain%d" % i, height, 0.0, radius, pos, Color("302f55"), Vector3.ZERO, null, 6)
		_mesh_cylinder(self, "MountainCap%d" % i, height * 0.30, 0.0, radius * 0.34, pos + Vector3(0, height * 0.34, 0), Color("6d6c8d"), Vector3.ZERO, null, 6)

func _build_castle_ruin() -> void:
	var base := Vector3(28, 0, -58)
	var stone := Color("5c5c68")
	var dark_stone := Color("41424d")

	_add_static_box(self, base + Vector3(0, 0.6, 9), Vector3(8, 1.2, 22), Color("817966"))
	_add_static_box(self, base + Vector3(-8.5, 3.0, 0), Vector3(3.2, 6.0, 20), stone, TEX_STONE)
	_add_static_box(self, base + Vector3(8.5, 3.0, 0), Vector3(3.2, 6.0, 20), stone, TEX_STONE)
	_add_static_box(self, base + Vector3(-4.9, 4.0, -9), Vector3(4.0, 8.0, 2.4), stone, TEX_STONE)
	_add_static_box(self, base + Vector3(4.9, 4.0, -9), Vector3(4.0, 8.0, 2.4), stone, TEX_STONE)
	_add_static_box(self, base + Vector3(0, 8.4, -9), Vector3(6.0, 2.2, 2.4), dark_stone, TEX_STONE)

	_add_static_cylinder(self, base + Vector3(-11, 6.0, -8), 12.0, 4.6, dark_stone, TEX_STONE, 10)
	_add_static_cylinder(self, base + Vector3(11, 6.0, -8), 12.0, 4.6, dark_stone, TEX_STONE, 10)
	_add_static_cylinder(self, base + Vector3(-11, 4.0, 10), 8.0, 3.8, stone, TEX_STONE, 9)

	_add_tower_crenellations(base + Vector3(-11, 12.5, -8), 4.9, 8)
	_add_tower_crenellations(base + Vector3(11, 12.5, -8), 4.9, 8)
	_add_tower_crenellations(base + Vector3(-11, 8.5, 10), 4.1, 7)

	for i in range(7):
		var x: float = -7.2 + float(i) * 2.4
		_add_static_box(self, base + Vector3(x, 6.6, 0.5), Vector3(1.25, 1.8, 1.6), dark_stone, TEX_STONE)

	_create_torch(base + Vector3(-3.0, 2.4, -7.1))
	_create_torch(base + Vector3(3.0, 2.4, -7.1))

func _add_tower_crenellations(center: Vector3, radius: float, count: int) -> void:
	for i in range(count):
		var angle: float = TAU * float(i) / float(count)
		var pos := center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var block := _add_static_box(self, pos, Vector3(1.5, 1.8, 1.5), Color("4a4b57"), TEX_STONE)
		block.rotation_degrees.y = rad_to_deg(angle)

func _build_watchtower() -> void:
	var base := Vector3(-58, 0, -72)
	_add_static_cylinder(self, base + Vector3(0, 7.0, 0), 14.0, 4.2, Color("4b4d58"), TEX_STONE, 9)
	_add_static_cylinder(self, base + Vector3(0, 14.4, 0), 1.3, 5.3, Color("62636d"), TEX_STONE, 9)
	_mesh_cylinder(self, "TowerRoof", 5.0, 0.0, 6.0, base + Vector3(0, 17.4, 0), Color("302a3c"), Vector3.ZERO, TEX_CLOTH, 9)
	_add_tower_crenellations(base + Vector3(0, 15.5, 0), 5.0, 8)
	_create_torch(base + Vector3(0, 2.4, 4.3))

func _build_moon_shrine() -> void:
	var base := Vector3(-34, 0, -28)
	for i in range(6):
		var angle: float = TAU * float(i) / 6.0
		var p := base + Vector3(cos(angle) * 5.0, 1.6, sin(angle) * 5.0)
		_add_static_cylinder(self, p, 3.2, 0.55, Color("666678"), TEX_STONE, 7)
	_mesh_sphere(self, "ShrineOrb", 1.05, base + Vector3(0, 2.4, 0), Color("8f9fff"), Vector3.ONE)
	var shrine_light := OmniLight3D.new()
	shrine_light.position = base + Vector3(0, 2.6, 0)
	shrine_light.light_color = Color("8d8fff")
	shrine_light.light_energy = 1.8
	shrine_light.omni_range = 9.0
	shrine_light.shadow_enabled = false
	add_child(shrine_light)

func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for("forest")
	var tree_count: int = rng.randi_range(85, 175)
	for i in range(tree_count):
		var p := Vector3(rng.randf_range(-100, 100), 0, rng.randf_range(-100, 100))
		if abs(p.x) < 7.0 and p.z > -95.0 and p.z < 30.0:
			continue
		if Vector2(p.x - 28.0, p.z + 58.0).length() < 23.0:
			continue
		if Vector2(p.x + 58.0, p.z + 72.0).length() < 12.0:
			continue
		if Vector2(p.x + 34.0, p.z + 28.0).length() < 11.0:
			continue
		var tree_scale: float = rng.randf_range(0.82, 1.35)
		if i % 5 == 0:
			_create_gnarled_tree(p, tree_scale, rng.randf_range(-28.0, 28.0))
		else:
			_create_pine(p, tree_scale, rng.randf_range(0.0, 360.0))

func _create_pine(pos: Vector3, tree_scale: float, yaw: float) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.rotation_degrees.y = yaw
	_mesh_cylinder(tree, "Trunk", 5.2 * tree_scale, 0.22 * tree_scale, 0.40 * tree_scale, Vector3(0, 2.6 * tree_scale, 0), Color("5a3928"), Vector3.ZERO, TEX_BARK, 6)
	_mesh_cylinder(tree, "CrownLow", 3.0 * tree_scale, 0.0, 2.0 * tree_scale, Vector3(0, 4.7 * tree_scale, 0), Color("183b28"), Vector3.ZERO, TEX_GRASS, 7)
	_mesh_cylinder(tree, "CrownMid", 2.7 * tree_scale, 0.0, 1.65 * tree_scale, Vector3(0, 6.0 * tree_scale, 0), Color("204a30"), Vector3.ZERO, TEX_GRASS, 7)
	_mesh_cylinder(tree, "CrownTop", 2.3 * tree_scale, 0.0, 1.25 * tree_scale, Vector3(0, 7.0 * tree_scale, 0), Color("285537"), Vector3.ZERO, TEX_GRASS, 7)
	add_child(tree)

func _create_gnarled_tree(pos: Vector3, tree_scale: float, lean: float) -> void:
	var tree := Node3D.new()
	tree.position = pos
	_mesh_cylinder(tree, "Trunk", 5.1 * tree_scale, 0.25 * tree_scale, 0.48 * tree_scale, Vector3(0, 2.5 * tree_scale, 0), Color("503126"), Vector3(0, 0, lean), TEX_BARK, 6)
	_mesh_cylinder(tree, "BranchL", 3.1 * tree_scale, 0.12 * tree_scale, 0.24 * tree_scale, Vector3(-0.9 * tree_scale, 4.2 * tree_scale, 0), Color("503126"), Vector3(0, 0, 58), TEX_BARK, 6)
	_mesh_cylinder(tree, "BranchR", 2.7 * tree_scale, 0.10 * tree_scale, 0.22 * tree_scale, Vector3(0.9 * tree_scale, 4.6 * tree_scale, 0), Color("503126"), Vector3(0, 0, -52), TEX_BARK, 6)
	_mesh_sphere(tree, "LeavesA", 1.3 * tree_scale, Vector3(-1.8 * tree_scale, 5.0 * tree_scale, 0), Color("263f2a"), Vector3(1.3, 0.8, 1.0), TEX_GRASS)
	_mesh_sphere(tree, "LeavesB", 1.45 * tree_scale, Vector3(0.3 * tree_scale, 5.9 * tree_scale, 0), Color("315235"), Vector3(1.1, 0.8, 1.2), TEX_GRASS)
	_mesh_sphere(tree, "LeavesC", 1.15 * tree_scale, Vector3(1.8 * tree_scale, 5.2 * tree_scale, 0), Color("1e3925"), Vector3(1.2, 0.75, 1.0), TEX_GRASS)
	add_child(tree)

func _build_ground_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for("ground_details")
	for i in range(70):
		var pos := Vector3(rng.randf_range(-92, 92), 0.11, rng.randf_range(-92, 92))
		if abs(pos.x) < 4.0 and pos.z > -92.0 and pos.z < 25.0:
			continue
		_create_grass_clump(pos, rng.randf_range(0.7, 1.5), rng.randf_range(0.0, 360.0))
	for i in range(34):
		var rock_pos := Vector3(rng.randf_range(-92, 92), 0.18, rng.randf_range(-92, 92))
		_create_rock(rock_pos, Vector3(rng.randf_range(0.45, 1.15), rng.randf_range(0.35, 0.85), rng.randf_range(0.45, 1.20)), Color("5a5760"))

func _create_grass_clump(pos: Vector3, grass_scale: float, yaw: float) -> void:
	var clump := Node3D.new()
	clump.position = pos
	clump.rotation_degrees.y = yaw
	var blade_a := _mesh_box(clump, "GrassA", Vector3(0.08, 0.75, 0.45) * grass_scale, Vector3(0, 0.36 * grass_scale, 0), Color("4f7a43"), 1.0, TEX_GRASS)
	blade_a.rotation_degrees.z = 8.0
	var blade_b := _mesh_box(clump, "GrassB", Vector3(0.45, 0.62, 0.08) * grass_scale, Vector3(0, 0.30 * grass_scale, 0), Color("3d6738"), 1.0, TEX_GRASS)
	blade_b.rotation_degrees.z = -7.0
	add_child(clump)

func _create_rock(pos: Vector3, rock_scale: Vector3, color: Color) -> void:
	var rock := _mesh_sphere(self, "Rock", 0.75, pos, color, rock_scale, TEX_STONE)
	rock.rotation_degrees = Vector3(12.0, fmod(abs(pos.x * 7.0 + pos.z * 3.0), 180.0), -8.0)

func _build_torches() -> void:
	var torch_positions: Array[Vector3] = [
		Vector3(-1.8, 0, -8), Vector3(4.2, 0, -24), Vector3(8.5, 0, -41),
		Vector3(24.0, 0, -45), Vector3(36.0, 0, -48), Vector3(-31.0, 0, -32)
	]
	for pos in torch_positions:
		_create_torch(pos)

func _create_torch(pos: Vector3) -> void:
	var torch := Node3D.new()
	torch.position = pos
	_mesh_cylinder(torch, "Pole", 2.2, 0.07, 0.10, Vector3(0, 1.1, 0), Color("5c3826"), Vector3.ZERO, TEX_BARK, 6)
	_mesh_sphere(torch, "Flame", 0.20, Vector3(0, 2.30, 0), Color("ffb24a"), Vector3(0.75, 1.35, 0.75))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.25, 0)
	light.light_color = Color("ff9d55")
	light.light_energy = 2.2
	light.omni_range = 8.0
	light.shadow_enabled = false
	torch.add_child(light)
	add_child(torch)

func _spawn_loot() -> void:
	_create_loot(Vector3(5.0, 0.8, -18.0), "Ancient Coin", Color("d8b84b"))
	_create_loot(Vector3(-34.0, 1.0, -28.0), "Moon Shard", Color("8bd2ff"))
	_create_loot(Vector3(-58.0, 1.0, -68.0), "Old Key", Color("c59a57"))
	_create_loot(Vector3(28.0, 1.0, -64.0), "Moon Blade", Color("80d4ff"))
	_create_loot(Vector3(-54.0, 1.0, -76.0), "Warden Mail", Color("707887"))

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
	mesh.material_override = _mat(color, 0.30, TEX_METAL if item_name == "Moon Blade" or item_name == "Warden Mail" else null)
	area.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	col.shape = shape
	area.add_child(col)
	add_child(area)

func spawn_combat_loot(pos: Vector3) -> void:
	var roll: int = randi() % 100
	if roll < 30:
		_create_loot(pos + Vector3(0, 0.7, 0), "Moon Shard", Color("8bd2ff"))
	else:
		_create_loot(pos + Vector3(0, 0.7, 0), "Ancient Coin", Color("d8b84b"))

func _spawn_enemies() -> void:
	_create_enemy(Vector3(10, 1.0, -30))
	_create_enemy(Vector3(31, 1.0, -52))
	_create_enemy(Vector3(-46, 1.0, -58))
	_create_enemy(Vector3(-61, 1.0, -75))

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

	_mesh_box(visual, "Torso", Vector3(0.78, 0.92, 0.46), Vector3(0, 1.28, 0), Color("454a50"), 0.90, TEX_METAL)
	_mesh_box(visual, "Hips", Vector3(0.62, 0.30, 0.40), Vector3(0, 0.70, 0), Color("292d32"), 0.95, TEX_CLOTH)
	_mesh_sphere(visual, "Head", 0.27, Vector3(0, 1.94, 0), Color("8e9589"))
	_mesh_cylinder(visual, "Helmet", 0.38, 0.20, 0.37, Vector3(0, 2.12, 0), Color("323641"), Vector3.ZERO, TEX_METAL, 7)
	_mesh_box(visual, "ShoulderL", Vector3(0.34, 0.18, 0.52), Vector3(-0.49, 1.56, 0), Color("555b62"), 0.75, TEX_METAL)
	_mesh_box(visual, "ShoulderR", Vector3(0.34, 0.18, 0.52), Vector3(0.49, 1.56, 0), Color("555b62"), 0.75, TEX_METAL)
	_mesh_cylinder(visual, "ArmL", 0.78, 0.12, 0.15, Vector3(-0.48, 1.18, 0), Color("3e4348"), Vector3(0, 0, -7), TEX_METAL, 6)
	_mesh_cylinder(visual, "ArmR", 0.78, 0.12, 0.15, Vector3(0.48, 1.18, 0), Color("3e4348"), Vector3(0, 0, 7), TEX_METAL, 6)
	_mesh_cylinder(visual, "LegL", 0.90, 0.13, 0.16, Vector3(-0.21, 0.25, 0), Color("23262b"), Vector3.ZERO, TEX_CLOTH, 6)
	_mesh_cylinder(visual, "LegR", 0.90, 0.13, 0.16, Vector3(0.21, 0.25, 0), Color("23262b"), Vector3.ZERO, TEX_CLOTH, 6)
	_mesh_box(visual, "TatteredCape", Vector3(0.78, 1.18, 0.08), Vector3(0, 1.05, 0.27), Color("24192a"), 1.0, TEX_CLOTH)
	_mesh_box(visual, "EyeGlow", Vector3(0.30, 0.055, 0.04), Vector3(0, 1.98, -0.27), Color("e04f78"), 0.20)

	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.54, 1.18, -0.03)
	weapon_pivot.rotation_degrees = Vector3(0, 0, 30)
	visual.add_child(weapon_pivot)
	_mesh_box(weapon_pivot, "Blade", Vector3(0.11, 1.20, 0.08), Vector3(0, 0.60, 0), Color("8a929b"), 0.28, TEX_METAL)
	_mesh_box(weapon_pivot, "Guard", Vector3(0.44, 0.08, 0.10), Vector3(0, -0.02, 0), Color("604b38"))
	_mesh_box(weapon_pivot, "Grip", Vector3(0.10, 0.36, 0.10), Vector3(0, -0.21, 0), Color("3b261d"), 1.0, TEX_BARK)

func _spawn_player() -> void:
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 1.2, 24)
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
	arm.spring_length = 5.8
	arm.margin = 0.2
	pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 65
	arm.add_child(cam)
	add_child(player)

func _build_player_visual(player: CharacterBody3D) -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	player.add_child(visual)

	_mesh_box(visual, "Torso", Vector3(0.78, 0.92, 0.44), Vector3(0, 1.27, 0), Color("302b43"), 0.95, TEX_CLOTH)
	_mesh_box(visual, "Hips", Vector3(0.60, 0.30, 0.38), Vector3(0, 0.70, 0), Color("242132"), 0.95, TEX_CLOTH)
	_mesh_sphere(visual, "Head", 0.28, Vector3(0, 1.95, 0), Color("b7a78c"))
	_mesh_cylinder(visual, "Helmet", 0.34, 0.16, 0.35, Vector3(0, 2.14, 0), Color("414657"), Vector3.ZERO, TEX_METAL, 7)
	_mesh_box(visual, "ShoulderL", Vector3(0.34, 0.17, 0.50), Vector3(-0.48, 1.55, 0), Color("4c5060"), 0.78, TEX_METAL)
	_mesh_box(visual, "ShoulderR", Vector3(0.34, 0.17, 0.50), Vector3(0.48, 1.55, 0), Color("4c5060"), 0.78, TEX_METAL)
	_mesh_cylinder(visual, "ArmL", 0.78, 0.12, 0.14, Vector3(-0.48, 1.17, 0), Color("373247"), Vector3(0, 0, -6), TEX_CLOTH, 6)
	_mesh_cylinder(visual, "ArmR", 0.78, 0.12, 0.14, Vector3(0.48, 1.17, 0), Color("373247"), Vector3(0, 0, 6), TEX_CLOTH, 6)
	_mesh_cylinder(visual, "LegL", 0.90, 0.13, 0.15, Vector3(-0.20, 0.25, 0), Color("211f2d"), Vector3.ZERO, TEX_CLOTH, 6)
	_mesh_cylinder(visual, "LegR", 0.90, 0.13, 0.15, Vector3(0.20, 0.25, 0), Color("211f2d"), Vector3.ZERO, TEX_CLOTH, 6)
	_mesh_box(visual, "Cape", Vector3(0.78, 1.20, 0.07), Vector3(0, 1.08, 0.27), Color("38244d"), 1.0, TEX_CLOTH)
	_mesh_box(visual, "Belt", Vector3(0.70, 0.12, 0.46), Vector3(0, 0.83, 0), Color("5b3b29"), 1.0, TEX_BARK)

	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.55, 1.18, 0)
	weapon_pivot.rotation_degrees = Vector3(0, 0, -25)
	visual.add_child(weapon_pivot)
	_mesh_box(weapon_pivot, "Blade", Vector3(0.11, 1.28, 0.08), Vector3(0, 0.64, 0), Color("a6aeb8"), 0.25, TEX_METAL)
	_mesh_box(weapon_pivot, "Guard", Vector3(0.46, 0.08, 0.10), Vector3(0, -0.02, 0), Color("866846"))
	_mesh_box(weapon_pivot, "Grip", Vector3(0.10, 0.38, 0.10), Vector3(0, -0.22, 0), Color("4a2d22"), 1.0, TEX_BARK)

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
	label.text = "0.12  •  WASD move  •  Shift run  •  Space jump  •  E interact  •  LMB attack  •  I inventory"
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 10)
	layer.add_child(label)
	var objective := Label.new()
	objective.text = "Follow the old road. Find the moon shrine, ruined keep and lonely watchtower."
	objective.position = Vector2(10, 25)
	objective.add_theme_font_size_override("font_size", 10)
	layer.add_child(objective)
	add_child(layer)
