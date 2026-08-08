extends Node

const BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const TEX_GRASS := preload("res://assets/textures/grass.svg")
const TEX_STONE := preload("res://assets/textures/stone.svg")
const TEX_BARK := preload("res://assets/textures/bark.svg")
const TEX_METAL := preload("res://assets/textures/metal.svg")
const TEX_CLOTH := preload("res://assets/textures/cloth.svg")

const UPDATE_INTERVAL: float = 0.25
const LOAD_RADIUS: float = 145.0
const UNLOAD_RADIUS: float = 185.0

const REGION_DEFINITIONS: Array[Dictionary] = [
	{
		"id": "starting_valley",
		"display_name": "Starting Valley",
		"biome": "green_highlands",
		"center": Vector3(0, 0, 0),
		"radius": 100.0,
		"external": true
	},
	{
		"id": "blackwood",
		"display_name": "Blackwood",
		"biome": "blackwood",
		"center": Vector3(-165, 0, -12),
		"radius": 62.0,
		"landmark": "The Fallen Chapel"
	},
	{
		"id": "windscar_highlands",
		"display_name": "Windscar Highlands",
		"biome": "windscar_highlands",
		"center": Vector3(165, 0, -20),
		"radius": 62.0,
		"landmark": "The Windscar Beacon"
	},
	{
		"id": "veilmoor",
		"display_name": "Veilmoor",
		"biome": "veilmoor",
		"center": Vector3(8, 0, -175),
		"radius": 62.0,
		"landmark": "The Pale Grave Ring"
	}
]

var world: Node3D
var world_state: Node
var regions_root: Node3D
var backbone_root: Node3D
var loaded_regions: Dictionary = {}
var update_timer: float = 0.0
var current_region_id: String = "starting_valley"
var region_card: ColorRect
var region_label: Label
var region_card_tween: Tween
var debug_label: Label

func _ready() -> void:
	set_process(false)
	call_deferred("_install")

func _install() -> void:
	await get_tree().process_frame
	world = get_parent() as Node3D
	if world == null:
		return
	world_state = get_node_or_null("/root/WorldState")

	regions_root = Node3D.new()
	regions_root.name = "RuntimeRegions"
	world.add_child(regions_root)

	backbone_root = Node3D.new()
	backbone_root.name = "WorldBackbone"
	world.add_child(backbone_root)

	_build_backbone_routes()
	_build_region_ui()
	_force_initial_stream_update()
	set_process(true)

func _process(delta: float) -> void:
	update_timer -= delta
	if update_timer > 0.0:
		return
	update_timer = UPDATE_INTERVAL
	_update_streaming()

func _force_initial_stream_update() -> void:
	update_timer = 0.0
	_update_streaming()

func _get_player() -> Node3D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty() or not players[0] is Node3D:
		return null
	return players[0] as Node3D

func _update_streaming() -> void:
	var player: Node3D = _get_player()
	if player == null:
		return

	var player_pos: Vector3 = player.global_position
	var nearest_id: String = "starting_valley"
	var nearest_distance: float = INF

	for definition in REGION_DEFINITIONS:
		var region_id: String = str(definition.get("id", ""))
		var center: Vector3 = definition.get("center", Vector3.ZERO)
		var distance: float = _flat_distance(player_pos, center)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = region_id

		if bool(definition.get("external", false)):
			continue

		if distance <= LOAD_RADIUS and not loaded_regions.has(region_id):
			_load_region(definition)
		elif distance >= UNLOAD_RADIUS and loaded_regions.has(region_id):
			_unload_region(region_id)

	var nearest_definition: Dictionary = _get_region_definition(nearest_id)
	var nearest_radius: float = float(nearest_definition.get("radius", 70.0))
	if nearest_distance <= nearest_radius and nearest_id != current_region_id:
		_enter_region(nearest_id)

	if debug_label != null:
		var seed_value: int = 8242601
		if world_state != null:
			seed_value = int(world_state.get("world_seed"))
		debug_label.text = "Region: %s   •   World seed: %d" % [_region_display_name(current_region_id), seed_value]

func _enter_region(region_id: String) -> void:
	current_region_id = region_id
	if world_state != null:
		world_state.set("current_region_id", region_id)
		if world_state.has_method("mark_region_discovered"):
			var already_discovered: bool = false
			if world_state.has_method("is_region_discovered"):
				already_discovered = bool(world_state.call("is_region_discovered", region_id))
			world_state.call("mark_region_discovered", region_id)
			if not already_discovered:
				_show_region_card(region_id)
	else:
		_show_region_card(region_id)

func _load_region(definition: Dictionary) -> void:
	var region_id: String = str(definition.get("id", "unknown"))
	var biome_id: String = str(definition.get("biome", "green_highlands"))
	var center: Vector3 = definition.get("center", Vector3.ZERO)
	var biome: Dictionary = BIOME_CATALOG.get_biome(biome_id)

	var region_node := Node3D.new()
	region_node.name = "Region_%s" % region_id
	region_node.position = center
	regions_root.add_child(region_node)
	loaded_regions[region_id] = region_node

	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_seed("region:%s" % region_id)

	_build_region_ground(region_node, biome, rng)
	_build_region_road(region_node, biome, rng)
	_build_region_vegetation(region_node, biome, rng)
	_build_region_landmark(region_node, region_id, biome)
	_build_region_encounters(region_node, region_id, biome, rng)

func _unload_region(region_id: String) -> void:
	var value: Variant = loaded_regions.get(region_id)
	if value is Node:
		(value as Node).queue_free()
	loaded_regions.erase(region_id)

func _stable_seed(scope_id: String) -> int:
	if world_state != null and world_state.has_method("stable_seed"):
		return int(world_state.call("stable_seed", scope_id))
	return int(("8242601:%s" % scope_id).hash() & 0x7fffffff)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _get_region_definition(region_id: String) -> Dictionary:
	for definition in REGION_DEFINITIONS:
		if str(definition.get("id", "")) == region_id:
			return definition
	return REGION_DEFINITIONS[0]

func _region_display_name(region_id: String) -> String:
	return str(_get_region_definition(region_id).get("display_name", region_id))

func _build_region_ground(region_node: Node3D, biome: Dictionary, rng: RandomNumberGenerator) -> void:
	var ground_color: Color = biome.get("ground_color", Color("4f7545"))
	_add_static_box(region_node, Vector3(0, -0.7, 0), Vector3(112, 1.4, 112), ground_color, TEX_GRASS)

	var elevation: float = float(biome.get("elevation", 1.0))
	for i in range(9):
		var terrace_pos := Vector3(rng.randf_range(-43.0, 43.0), 0.0, rng.randf_range(-43.0, 43.0))
		if terrace_pos.length() < 13.0:
			continue
		var width: float = rng.randf_range(10.0, 22.0)
		var depth: float = rng.randf_range(9.0, 20.0)
		var height: float = rng.randf_range(0.35, 0.9 + elevation * 0.45)
		_add_static_box(region_node, terrace_pos + Vector3(0, height * 0.5 - 0.03, 0), Vector3(width, height, depth), ground_color.darkened(0.06), TEX_GRASS)

func _build_region_road(region_node: Node3D, biome: Dictionary, rng: RandomNumberGenerator) -> void:
	var road_color: Color = biome.get("road_color", Color("827760"))
	for i in range(17):
		var t: float = float(i) / 16.0
		var z: float = lerp(48.0, -48.0, t)
		var x: float = sin(t * TAU * 1.15) * 5.0 + rng.randf_range(-0.45, 0.45)
		var road_piece := _add_static_box(region_node, Vector3(x, 0.035, z), Vector3(5.8, 0.10, 6.4), road_color, TEX_STONE)
		road_piece.rotation_degrees.y = cos(t * TAU * 1.15) * 7.0

func _build_region_vegetation(region_node: Node3D, biome: Dictionary, rng: RandomNumberGenerator) -> void:
	var tree_density: float = float(biome.get("tree_density", 0.4))
	var rock_density: float = float(biome.get("rock_density", 0.2))
	var tree_count: int = int(22 + tree_density * 55.0)
	var rock_count: int = int(10 + rock_density * 42.0)
	var trunk_color: Color = biome.get("tree_trunk", Color("5b3826"))
	var leaf_color: Color = biome.get("tree_leaf", Color("285238"))
	var rock_color: Color = biome.get("rock_color", Color("706d72"))

	for i in range(tree_count):
		var pos := Vector3(rng.randf_range(-50.0, 50.0), 0, rng.randf_range(-50.0, 50.0))
		if abs(pos.x) < 9.0:
			continue
		var scale_value: float = rng.randf_range(0.72, 1.35)
		if i % 5 == 0:
			_create_dead_tree(region_node, pos, scale_value, trunk_color, leaf_color.darkened(0.25))
		else:
			_create_pine(region_node, pos, scale_value, trunk_color, leaf_color)

	for i in range(rock_count):
		var pos := Vector3(rng.randf_range(-51.0, 51.0), 0.20, rng.randf_range(-51.0, 51.0))
		if abs(pos.x) < 7.0:
			continue
		_create_rock(region_node, pos, Vector3(rng.randf_range(0.45, 1.4), rng.randf_range(0.35, 1.0), rng.randf_range(0.5, 1.5)), rock_color)

func _build_region_landmark(region_node: Node3D, region_id: String, biome: Dictionary) -> void:
	match region_id:
		"blackwood":
			_build_fallen_chapel(region_node, biome)
		"windscar_highlands":
			_build_windscar_beacon(region_node, biome)
		"veilmoor":
			_build_pale_grave_ring(region_node, biome)

func _build_fallen_chapel(region_node: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("494950"))
	var accent: Color = biome.get("accent", Color("7e9a75"))
	var base := Vector3(-12, 0, -17)
	_add_static_box(region_node, base + Vector3(0, 0.25, 0), Vector3(17, 0.5, 24), stone.darkened(0.10), TEX_STONE)
	_add_static_box(region_node, base + Vector3(-7.5, 3.2, 0), Vector3(1.2, 6.4, 24), stone, TEX_STONE)
	_add_static_box(region_node, base + Vector3(7.5, 2.0, -5), Vector3(1.2, 4.0, 14), stone, TEX_STONE)
	_add_static_box(region_node, base + Vector3(0, 3.0, -11.5), Vector3(16, 6.0, 1.2), stone.darkened(0.08), TEX_STONE)
	_add_static_box(region_node, base + Vector3(0, 1.7, 7.0), Vector3(8, 3.4, 1.0), stone, TEX_STONE)
	_create_glow_orb(region_node, base + Vector3(0, 2.0, -7), accent, 7.0)

func _build_windscar_beacon(region_node: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("77767d"))
	var accent: Color = biome.get("accent", Color("c4b98c"))
	var base := Vector3(14, 0, -15)
	_add_static_box(region_node, base + Vector3(0, 1.0, 0), Vector3(12, 2.0, 12), stone.darkened(0.12), TEX_STONE)
	for i in range(6):
		var angle: float = TAU * float(i) / 6.0
		var p := base + Vector3(cos(angle) * 7.0, 3.3, sin(angle) * 7.0)
		_add_static_box(region_node, p, Vector3(1.3, 6.6, 1.3), stone, TEX_STONE)
	_add_static_box(region_node, base + Vector3(0, 5.5, 0), Vector3(2.0, 11.0, 2.0), stone.lightened(0.05), TEX_STONE)
	_create_glow_orb(region_node, base + Vector3(0, 11.5, 0), accent, 10.0)

func _build_pale_grave_ring(region_node: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("5e5b6d"))
	var accent: Color = biome.get("accent", Color("8c8be2"))
	var base := Vector3(0, 0, -11)
	for i in range(12):
		var angle: float = TAU * float(i) / 12.0
		var radius: float = 10.0 + (2.0 if i % 3 == 0 else 0.0)
		var p := base + Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
		var grave := _add_static_box(region_node, p, Vector3(1.0, 2.0 + float(i % 2) * 0.6, 0.45), stone, TEX_STONE)
		grave.rotation_degrees.y = rad_to_deg(-angle) + 90.0
	_add_static_box(region_node, base + Vector3(0, 0.35, 0), Vector3(8, 0.7, 8), stone.darkened(0.15), TEX_STONE)
	_create_glow_orb(region_node, base + Vector3(0, 1.4, 0), accent, 11.0)

func _build_region_encounters(region_node: Node3D, region_id: String, biome: Dictionary, rng: RandomNumberGenerator) -> void:
	var profile: String = str(biome.get("encounter_profile", "warden_patrol"))
	var positions: Array[Vector3] = [Vector3(-20, 1.0, 12), Vector3(18, 1.0, -2), Vector3(-8, 1.0, -32)]
	for i in range(positions.size()):
		var entity_id: String = "enemy:%s:%d" % [region_id, i]
		if _entity_is_dead(entity_id):
			continue
		var jitter := Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))
		_spawn_enemy_variant(region_node, positions[i] + jitter, profile, entity_id, i)

func _entity_is_dead(entity_id: String) -> bool:
	if world_state == null or not world_state.has_method("get_entity_state"):
		return false
	var state: Variant = world_state.call("get_entity_state", entity_id)
	if state is Dictionary:
		return bool((state as Dictionary).get("dead", false))
	return false

func _spawn_enemy_variant(region_node: Node3D, pos: Vector3, profile: String, entity_id: String, index: int) -> void:
	var enemy := CharacterBody3D.new()
	enemy.name = "RegionEnemy_%d" % index
	enemy.position = pos
	enemy.set_script(ENEMY_SCRIPT)
	enemy.set("persistent_id", entity_id)

	match profile:
		"blackwood_ambush":
			enemy.set("enemy_name", "Blackwood Stalker")
			enemy.set("move_speed", 3.0)
			enemy.set("max_health", 38)
			enemy.set("attack_damage", 11)
		"restless_dead":
			enemy.set("enemy_name", "Pale Warden")
			enemy.set("move_speed", 2.1)
			enemy.set("max_health", 58)
			enemy.set("attack_damage", 15)
		"highland_guardians":
			enemy.set("enemy_name", "Highland Sentinel")
			enemy.set("move_speed", 2.5)
			enemy.set("max_health", 70)
			enemy.set("attack_damage", 17)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.85
	collision.shape = capsule
	collision.position.y = 0.92
	enemy.add_child(collision)
	_build_region_enemy_visual(enemy, profile)
	region_node.add_child(enemy)

func _build_region_enemy_visual(enemy: CharacterBody3D, profile: String) -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	enemy.add_child(visual)

	var body_color := Color("454a50")
	var cape_color := Color("24192a")
	var eye_color := Color("e04f78")
	if profile == "blackwood_ambush":
		body_color = Color("28382e")
		cape_color = Color("172019")
		eye_color = Color("8fd06f")
	elif profile == "restless_dead":
		body_color = Color("55576a")
		cape_color = Color("29283d")
		eye_color = Color("9ca8ff")
	elif profile == "highland_guardians":
		body_color = Color("66655f")
		cape_color = Color("44382e")
		eye_color = Color("e6c27a")

	_mesh_box(visual, "Torso", Vector3(0, 1.28, 0), Vector3(0.78, 0.92, 0.46), body_color, TEX_METAL)
	_mesh_box(visual, "Hips", Vector3(0, 0.70, 0), Vector3(0.62, 0.30, 0.40), body_color.darkened(0.2), TEX_CLOTH)
	_mesh_sphere(visual, "Head", Vector3(0, 1.94, 0), 0.27, body_color.lightened(0.15), Vector3.ONE, TEX_METAL)
	_mesh_cylinder(visual, "ArmL", Vector3(-0.48, 1.18, 0), 0.78, 0.14, body_color, Vector3(0, 0, -7), TEX_METAL)
	_mesh_cylinder(visual, "ArmR", Vector3(0.48, 1.18, 0), 0.78, 0.14, body_color, Vector3(0, 0, 7), TEX_METAL)
	_mesh_cylinder(visual, "LegL", Vector3(-0.21, 0.25, 0), 0.90, 0.15, body_color.darkened(0.28), Vector3.ZERO, TEX_CLOTH)
	_mesh_cylinder(visual, "LegR", Vector3(0.21, 0.25, 0), 0.90, 0.15, body_color.darkened(0.28), Vector3.ZERO, TEX_CLOTH)
	_mesh_box(visual, "TatteredCape", Vector3(0, 1.05, 0.27), Vector3(0.78, 1.18, 0.08), cape_color, TEX_CLOTH)
	_mesh_box(visual, "EyeGlow", Vector3(0, 1.98, -0.27), Vector3(0.30, 0.055, 0.04), eye_color)

	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.54, 1.18, -0.03)
	weapon_pivot.rotation_degrees = Vector3(0, 0, 30)
	visual.add_child(weapon_pivot)
	_mesh_box(weapon_pivot, "Blade", Vector3(0, 0.60, 0), Vector3(0.11, 1.20, 0.08), body_color.lightened(0.3), TEX_METAL)

func _build_backbone_routes() -> void:
	_build_route(Vector3(-88, 0, -10), Vector3(-145, 0, -12), Color("5d584e"), Color("30452f"))
	_build_route(Vector3(88, 0, -15), Vector3(145, 0, -19), Color("8a7b62"), Color("53623f"))
	_build_route(Vector3(8, 0, -92), Vector3(8, 0, -155), Color("625c68"), Color("3f3e4d"))
	_build_route(Vector3(-160, 0, -55), Vector3(-32, 0, -163), Color("55505a"), Color("343a35"), 9.0)

func _build_route(start: Vector3, finish: Vector3, road_color: Color, ground_color: Color, width: float = 12.0) -> void:
	var distance: float = start.distance_to(finish)
	var segments: int = max(2, int(ceil(distance / 6.0)))
	var direction: Vector3 = finish - start
	var yaw: float = rad_to_deg(atan2(direction.x, direction.z))
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var pos: Vector3 = start.lerp(finish, t)
		var ground := _add_static_box(backbone_root, pos + Vector3(0, -0.38, 0), Vector3(width, 0.75, 6.3), ground_color, TEX_GRASS)
		ground.rotation_degrees.y = yaw
		var road := _add_static_box(backbone_root, pos + Vector3(0, 0.025, 0), Vector3(5.2, 0.08, 6.0), road_color, TEX_STONE)
		road.rotation_degrees.y = yaw

func _build_region_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 126

	region_card = ColorRect.new()
	region_card.position = Vector2(170, 112)
	region_card.size = Vector2(300, 52)
	region_card.color = Color(0.022, 0.018, 0.050, 0.92)
	region_card.visible = false
	region_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(region_card)

	region_label = Label.new()
	region_label.position = Vector2(10, 7)
	region_label.size = Vector2(280, 40)
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	region_label.add_theme_font_size_override("font_size", 12)
	region_card.add_child(region_label)

	debug_label = Label.new()
	debug_label.position = Vector2(382, 8)
	debug_label.size = Vector2(248, 18)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.add_theme_font_size_override("font_size", 9)
	layer.add_child(debug_label)

	world.add_child(layer)

func _show_region_card(region_id: String) -> void:
	if region_card == null or region_label == null:
		return
	if region_card_tween != null and region_card_tween.is_valid():
		region_card_tween.kill()
	var definition: Dictionary = _get_region_definition(region_id)
	var display_name: String = str(definition.get("display_name", region_id))
	var landmark: String = str(definition.get("landmark", ""))
	region_label.text = "ENTERING — %s\n%s" % [display_name, landmark]
	region_card.modulate = Color.WHITE
	region_card.visible = true
	region_card_tween = create_tween()
	region_card_tween.tween_interval(2.4)
	region_card_tween.tween_property(region_card, "modulate", Color(1, 1, 1, 0), 0.8)
	region_card_tween.tween_callback(_hide_region_card)

func _hide_region_card() -> void:
	if region_card != null:
		region_card.visible = false

func _mat(color: Color, texture: Texture2D = null, roughness: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if texture != null:
		material.albedo_texture = texture
	return material

func _add_static_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, texture)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func _mesh_box(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = pos
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, texture)
	parent.add_child(mesh_instance)
	return mesh_instance

func _mesh_cylinder(parent: Node3D, node_name: String, pos: Vector3, height: float, radius: float, color: Color, rotation: Vector3 = Vector3.ZERO, texture: Texture2D = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rotation
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.height = height
	mesh.top_radius = radius * 0.75
	mesh.bottom_radius = radius
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, texture)
	parent.add_child(mesh_instance)
	return mesh_instance

func _mesh_sphere(parent: Node3D, node_name: String, pos: Vector3, radius: float, color: Color, mesh_scale: Vector3 = Vector3.ONE, texture: Texture2D = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = pos
	mesh_instance.scale = mesh_scale
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, texture)
	parent.add_child(mesh_instance)
	return mesh_instance

func _create_pine(parent: Node3D, pos: Vector3, tree_scale: float, trunk_color: Color, leaf_color: Color) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.rotation_degrees.y = fmod(abs(pos.x * 9.0 + pos.z * 5.0), 360.0)
	_mesh_cylinder(tree, "Trunk", Vector3(0, 2.4 * tree_scale, 0), 4.8 * tree_scale, 0.36 * tree_scale, trunk_color, Vector3.ZERO, TEX_BARK)
	_mesh_cylinder(tree, "CrownLow", Vector3(0, 4.5 * tree_scale, 0), 2.7 * tree_scale, 1.8 * tree_scale, leaf_color, Vector3.ZERO, TEX_GRASS)
	_mesh_cylinder(tree, "CrownTop", Vector3(0, 6.0 * tree_scale, 0), 2.5 * tree_scale, 1.25 * tree_scale, leaf_color.lightened(0.06), Vector3.ZERO, TEX_GRASS)
	parent.add_child(tree)

func _create_dead_tree(parent: Node3D, pos: Vector3, tree_scale: float, trunk_color: Color, leaf_color: Color) -> void:
	var tree := Node3D.new()
	tree.position = pos
	var lean: float = fmod(abs(pos.x * 7.0 + pos.z * 11.0), 26.0) - 13.0
	_mesh_cylinder(tree, "Trunk", Vector3(0, 2.4 * tree_scale, 0), 4.8 * tree_scale, 0.42 * tree_scale, trunk_color.darkened(0.08), Vector3(0, 0, lean), TEX_BARK)
	_mesh_cylinder(tree, "BranchL", Vector3(-0.8 * tree_scale, 4.0 * tree_scale, 0), 2.8 * tree_scale, 0.20 * tree_scale, trunk_color, Vector3(0, 0, 58), TEX_BARK)
	_mesh_cylinder(tree, "BranchR", Vector3(0.8 * tree_scale, 4.2 * tree_scale, 0), 2.5 * tree_scale, 0.18 * tree_scale, trunk_color, Vector3(0, 0, -54), TEX_BARK)
	if leaf_color.get_luminance() > 0.12:
		_mesh_sphere(tree, "SparseLeaves", Vector3(0, 5.2 * tree_scale, 0), 1.0 * tree_scale, leaf_color, Vector3(1.3, 0.6, 1.1), TEX_GRASS)
	parent.add_child(tree)

func _create_rock(parent: Node3D, pos: Vector3, rock_scale: Vector3, color: Color) -> void:
	var rock := _mesh_sphere(parent, "Rock", pos, 0.72, color, rock_scale, TEX_STONE)
	rock.rotation_degrees = Vector3(10.0, fmod(abs(pos.x * 13.0 + pos.z * 3.0), 180.0), -7.0)

func _create_glow_orb(parent: Node3D, pos: Vector3, color: Color, light_range: float) -> void:
	_mesh_sphere(parent, "LandmarkGlow", pos, 0.62, color, Vector3.ONE)
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = 1.7
	light.omni_range = light_range
	light.shadow_enabled = false
	parent.add_child(light)
