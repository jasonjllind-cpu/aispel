extends Node
class_name DungeonSystem

const DUNGEON_CATALOG := preload("res://scripts/dungeon/dungeon_catalog.gd")
const DUNGEON_GENERATOR_SCRIPT := preload("res://scripts/dungeon/dungeon_generator.gd")
const PORTAL_SCRIPT := preload("res://scripts/dungeon/dungeon_portal.gd")
const BOSS_SCRIPT := preload("res://scripts/dungeon/boss_actor.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const LOOT_SCRIPT := preload("res://scripts/world/generated_loot.gd")
const TEX_STONE := preload("res://assets/textures/stone.svg")
const TEX_METAL := preload("res://assets/textures/metal.svg")
const TEX_CLOTH := preload("res://assets/textures/cloth.svg")

const WALL_HEIGHT: float = 4.2
const WALL_THICKNESS: float = 0.45
const DOOR_WIDTH: float = 4.0

var world: Node3D
var world_state: Node
var generator: RefCounted
var dungeon_instances: Dictionary = {}
var active_dungeon_id: String = ""
var title_label: Label

func _ready() -> void:
	add_to_group("dungeon_system")
	set_process(false)
	call_deferred("_install")

func _install() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	world = get_parent() as Node3D
	if world == null:
		return
	world_state = get_node_or_null("/root/WorldState")
	generator = DUNGEON_GENERATOR_SCRIPT.new()
	generator.call("configure", _world_seed())
	_spawn_world_portals()
	if DisplayServer.get_name() != "headless":
		_build_ui()

func enter_dungeon(dungeon_id: String, player: Node) -> void:
	if player == null:
		return
	var definition: Dictionary = DUNGEON_CATALOG.get_dungeon(dungeon_id)
	if definition.is_empty():
		return
	var root: Node3D = _ensure_dungeon_instance(dungeon_id)
	if root == null:
		return
	var layout: Dictionary = root.get_meta("layout", {})
	var rooms_value: Variant = layout.get("rooms", [])
	if not rooms_value is Array or (rooms_value as Array).is_empty():
		return
	var entrance_room: Dictionary = (rooms_value as Array)[0]
	var local_center: Vector3 = entrance_room.get("center", Vector3.ZERO)
	if player is Node3D:
		(player as Node3D).global_position = root.global_position + local_center + Vector3(0, 1.05, 0)
		player.set("velocity", Vector3.ZERO)
	active_dungeon_id = dungeon_id
	_show_title(str(definition.get("display_name", dungeon_id)))

func exit_dungeon(dungeon_id: String, player: Node) -> void:
	var definition: Dictionary = DUNGEON_CATALOG.get_dungeon(dungeon_id)
	if definition.is_empty() or not player is Node3D:
		return
	(player as Node3D).global_position = definition.get("world_return", Vector3.ZERO)
	player.set("velocity", Vector3.ZERO)
	active_dungeon_id = ""

func on_boss_defeated(dungeon_id: String, boss_id: String, boss_global_position: Vector3) -> void:
	if world_state != null:
		if world_state.has_method("set_entity_state"):
			world_state.call("set_entity_state", "boss:%s" % boss_id, {"dead": true, "dungeon_id": dungeon_id})
		if world_state.has_method("set_flag"):
			world_state.call("set_flag", "dungeon:%s:boss_defeated" % dungeon_id, true)
	var root: Node3D = _get_instance(dungeon_id)
	if root != null:
		_spawn_boss_reward(root, dungeon_id, root.to_local(boss_global_position) + Vector3(0, 0.7, 0))
	_show_title("BOSS DEFEATED — %s" % boss_id.replace("_", " ").capitalize())

func _spawn_world_portals() -> void:
	for dungeon_id in DUNGEON_CATALOG.get_dungeon_ids():
		var definition: Dictionary = DUNGEON_CATALOG.get_dungeon(dungeon_id)
		var node_name := "DungeonEntrance_%s" % dungeon_id
		if world.has_node(node_name):
			continue
		var portal: Area3D = _create_portal(dungeon_id, "enter", str(definition.get("display_name", dungeon_id)))
		portal.name = node_name
		portal.position = definition.get("world_entry", Vector3.ZERO)
		world.add_child(portal)

func _ensure_dungeon_instance(dungeon_id: String) -> Node3D:
	var existing: Node3D = _get_instance(dungeon_id)
	if existing != null:
		return existing
	var definition: Dictionary = DUNGEON_CATALOG.get_dungeon(dungeon_id)
	if definition.is_empty():
		return null
	var layout_value: Variant = generator.call("generate_layout", dungeon_id)
	if not layout_value is Dictionary:
		return null
	var layout: Dictionary = layout_value as Dictionary
	var root := Node3D.new()
	root.name = "Dungeon_%s" % dungeon_id
	root.position = definition.get("interior_origin", Vector3.ZERO)
	root.set_meta("dungeon_id", dungeon_id)
	root.set_meta("layout", layout.duplicate(true))
	root.add_to_group("dungeon_instance")
	world.add_child(root)
	dungeon_instances[dungeon_id] = root
	_build_dungeon_geometry(root, definition, layout)
	_build_dungeon_content(root, definition, layout)
	return root

func _get_instance(dungeon_id: String) -> Node3D:
	var value: Variant = dungeon_instances.get(dungeon_id)
	if value is Node3D and is_instance_valid(value):
		return value as Node3D
	return null

func _build_dungeon_geometry(root: Node3D, definition: Dictionary, layout: Dictionary) -> void:
	var rooms_value: Variant = layout.get("rooms", [])
	var connections_value: Variant = layout.get("connections", [])
	if not rooms_value is Array or not connections_value is Array:
		return
	var rooms: Array = rooms_value as Array
	var connections: Array = connections_value as Array
	for i in range(rooms.size()):
		if not rooms[i] is Dictionary:
			continue
		_build_room(root, rooms[i] as Dictionary, _room_openings(i, rooms, connections), definition)
	for connection_value in connections:
		if connection_value is Dictionary:
			_build_corridor(root, connection_value as Dictionary, rooms, definition)

func _build_room(root: Node3D, room: Dictionary, openings: Dictionary, definition: Dictionary) -> void:
	var center: Vector3 = room.get("center", Vector3.ZERO)
	var size: float = float(definition.get("room_size", 12.0))
	var stone: Color = definition.get("stone", Color("4e4d60"))
	_add_static_box(root, center + Vector3(0, -0.25, 0), Vector3(size, 0.5, size), stone.darkened(0.14))
	_add_static_box(root, center + Vector3(0, WALL_HEIGHT + 0.20, 0), Vector3(size, 0.4, size), stone.darkened(0.28))
	_build_room_wall(root, center, size, "north", bool(openings.get("north", false)), stone)
	_build_room_wall(root, center, size, "south", bool(openings.get("south", false)), stone)
	_build_room_wall(root, center, size, "east", bool(openings.get("east", false)), stone)
	_build_room_wall(root, center, size, "west", bool(openings.get("west", false)), stone)
	var room_type: String = str(room.get("type", "chamber"))
	if room_type == "crypt":
		for x in [-3.2, 3.2]:
			_add_static_box(root, center + Vector3(x, 0.65, 2.8), Vector3(1.1, 1.3, 2.0), stone.lightened(0.05))
	elif room_type == "treasure":
		_add_static_box(root, center + Vector3(0, 0.35, 0), Vector3(2.2, 0.7, 2.2), stone.lightened(0.08))
	elif room_type == "boss":
		for i in range(4):
			var angle: float = TAU * float(i) / 4.0
			_add_static_box(root, center + Vector3(cos(angle) * 4.0, 1.4, sin(angle) * 4.0), Vector3(0.9, 2.8, 0.9), stone.lightened(0.04))

func _build_room_wall(root: Node3D, center: Vector3, size: float, side: String, open: bool, color: Color) -> void:
	var half: float = size * 0.5
	if not open:
		if side == "north" or side == "south":
			_add_static_box(root, center + Vector3(0, WALL_HEIGHT * 0.5, -half if side == "north" else half), Vector3(size, WALL_HEIGHT, WALL_THICKNESS), color)
		else:
			_add_static_box(root, center + Vector3(half if side == "east" else -half, WALL_HEIGHT * 0.5, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, size), color)
		return
	var segment: float = (size - DOOR_WIDTH) * 0.5
	var offset: float = DOOR_WIDTH * 0.5 + segment * 0.5
	if side == "north" or side == "south":
		var z: float = -half if side == "north" else half
		_add_static_box(root, center + Vector3(-offset, WALL_HEIGHT * 0.5, z), Vector3(segment, WALL_HEIGHT, WALL_THICKNESS), color)
		_add_static_box(root, center + Vector3(offset, WALL_HEIGHT * 0.5, z), Vector3(segment, WALL_HEIGHT, WALL_THICKNESS), color)
	else:
		var x: float = half if side == "east" else -half
		_add_static_box(root, center + Vector3(x, WALL_HEIGHT * 0.5, -offset), Vector3(WALL_THICKNESS, WALL_HEIGHT, segment), color)
		_add_static_box(root, center + Vector3(x, WALL_HEIGHT * 0.5, offset), Vector3(WALL_THICKNESS, WALL_HEIGHT, segment), color)

func _room_openings(room_index: int, rooms: Array, connections: Array) -> Dictionary:
	var result := {"north": false, "south": false, "east": false, "west": false}
	if room_index < 0 or room_index >= rooms.size() or not rooms[room_index] is Dictionary:
		return result
	var room: Dictionary = rooms[room_index] as Dictionary
	var cell: Vector2i = room.get("cell", Vector2i.ZERO)
	for value in connections:
		if not value is Dictionary:
			continue
		var connection: Dictionary = value as Dictionary
		var from_index: int = int(connection.get("from", -1))
		var to_index: int = int(connection.get("to", -1))
		var other_index: int = -1
		if from_index == room_index:
			other_index = to_index
		elif to_index == room_index:
			other_index = from_index
		if other_index < 0 or other_index >= rooms.size() or not rooms[other_index] is Dictionary:
			continue
		var other: Dictionary = rooms[other_index] as Dictionary
		var delta: Vector2i = (other.get("cell", Vector2i.ZERO) as Vector2i) - cell
		if delta == Vector2i(0, -1):
			result["north"] = true
		elif delta == Vector2i(0, 1):
			result["south"] = true
		elif delta == Vector2i(1, 0):
			result["east"] = true
		elif delta == Vector2i(-1, 0):
			result["west"] = true
	return result

func _build_corridor(root: Node3D, connection: Dictionary, rooms: Array, definition: Dictionary) -> void:
	var from_index: int = int(connection.get("from", -1))
	var to_index: int = int(connection.get("to", -1))
	if from_index < 0 or to_index < 0 or from_index >= rooms.size() or to_index >= rooms.size():
		return
	var from_room: Dictionary = rooms[from_index] as Dictionary
	var to_room: Dictionary = rooms[to_index] as Dictionary
	var start: Vector3 = from_room.get("center", Vector3.ZERO)
	var finish: Vector3 = to_room.get("center", Vector3.ZERO)
	var direction: Vector3 = finish - start
	var distance: float = Vector2(direction.x, direction.z).length()
	var room_size: float = float(definition.get("room_size", 12.0))
	var length: float = max(2.0, distance - room_size + 0.8)
	var center: Vector3 = (start + finish) * 0.5
	var stone: Color = definition.get("stone", Color("4e4d60")).darkened(0.08)
	if abs(direction.x) > abs(direction.z):
		_add_static_box(root, center + Vector3(0, -0.25, 0), Vector3(length, 0.5, DOOR_WIDTH), stone)
		_add_static_box(root, center + Vector3(0, WALL_HEIGHT + 0.2, 0), Vector3(length, 0.4, DOOR_WIDTH), stone.darkened(0.2))
		_add_static_box(root, center + Vector3(0, WALL_HEIGHT * 0.5, -(DOOR_WIDTH * 0.5)), Vector3(length, WALL_HEIGHT, WALL_THICKNESS), stone)
		_add_static_box(root, center + Vector3(0, WALL_HEIGHT * 0.5, DOOR_WIDTH * 0.5), Vector3(length, WALL_HEIGHT, WALL_THICKNESS), stone)
	else:
		_add_static_box(root, center + Vector3(0, -0.25, 0), Vector3(DOOR_WIDTH, 0.5, length), stone)
		_add_static_box(root, center + Vector3(0, WALL_HEIGHT + 0.2, 0), Vector3(DOOR_WIDTH, 0.4, length), stone.darkened(0.2))
		_add_static_box(root, center + Vector3(-(DOOR_WIDTH * 0.5), WALL_HEIGHT * 0.5, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, length), stone)
		_add_static_box(root, center + Vector3(DOOR_WIDTH * 0.5, WALL_HEIGHT * 0.5, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, length), stone)

func _build_dungeon_content(root: Node3D, definition: Dictionary, layout: Dictionary) -> void:
	var rooms: Array = layout.get("rooms", [])
	if rooms.is_empty():
		return
	var entrance: Dictionary = rooms[0] as Dictionary
	var exit_portal: Area3D = _create_portal(str(definition.get("id", "")), "exit", str(definition.get("display_name", "Dungeon")))
	exit_portal.name = "DungeonExit"
	exit_portal.position = entrance.get("center", Vector3.ZERO) + Vector3(0, 0.7, 3.7)
	root.add_child(exit_portal)

	var encounters_value: Variant = layout.get("encounters", [])
	if encounters_value is Array:
		for value in encounters_value as Array:
			if value is Dictionary:
				_spawn_guardian(root, value as Dictionary)

	var loot_value: Variant = layout.get("loot", [])
	if loot_value is Array:
		for value in loot_value as Array:
			if value is Dictionary:
				_spawn_loot(root, value as Dictionary)

	var boss_id: String = str(layout.get("boss_id", definition.get("boss_id", "boss")))
	if _entity_dead("boss:%s" % boss_id):
		var boss_room_index: int = int(layout.get("boss_room_index", rooms.size() - 1))
		var boss_room: Dictionary = rooms[boss_room_index] as Dictionary
		_spawn_boss_reward(root, str(definition.get("id", "")), boss_room.get("center", Vector3.ZERO) + Vector3(0, 0.7, 0))
	else:
		_spawn_boss(root, definition, layout)

func _spawn_guardian(root: Node3D, encounter: Dictionary) -> void:
	var persistent_id: String = str(encounter.get("id", ""))
	if _entity_dead(persistent_id):
		return
	var enemy := CharacterBody3D.new()
	enemy.name = persistent_id.replace(":", "_")
	enemy.position = encounter.get("position", Vector3.ZERO)
	enemy.set_script(ENEMY_SCRIPT)
	enemy.set("persistent_id", persistent_id)
	enemy.set("enemy_name", "Catacomb Warden")
	enemy.set("max_health", 62)
	enemy.set("attack_damage", 16)
	enemy.set("detection_range", 14.0)
	_add_capsule_collision(enemy, 0.42, 1.85)
	if DisplayServer.get_name() != "headless":
		_build_enemy_visual(enemy, Color("58596a"), Color("8f9dff"), false)
	root.add_child(enemy)

func _spawn_boss(root: Node3D, definition: Dictionary, layout: Dictionary) -> void:
	var rooms: Array = layout.get("rooms", [])
	if rooms.is_empty():
		return
	var boss_room_index: int = int(layout.get("boss_room_index", rooms.size() - 1))
	var room: Dictionary = rooms[boss_room_index] as Dictionary
	var boss := CharacterBody3D.new()
	boss.set_script(BOSS_SCRIPT)
	boss.name = "Boss_%s" % str(definition.get("boss_id", "boss"))
	boss.position = room.get("center", Vector3.ZERO) + Vector3(0, 1.0, 0)
	boss.set("boss_id", str(definition.get("boss_id", "boss")))
	boss.set("dungeon_id", str(definition.get("id", "")))
	boss.set("boss_title", str(definition.get("boss_name", "Dungeon Boss")))
	boss.set("max_health", 220)
	boss.set("attack_damage", 24)
	_add_capsule_collision(boss, 0.60, 2.35)
	if DisplayServer.get_name() != "headless":
		_build_enemy_visual(boss, Color("3d3b50"), definition.get("accent", Color("8f9dff")), true)
	root.add_child(boss)

func _spawn_loot(root: Node3D, data: Dictionary) -> void:
	var persistent_id: String = str(data.get("id", ""))
	if _entity_collected(persistent_id):
		return
	var loot := Area3D.new()
	loot.set_script(LOOT_SCRIPT)
	loot.name = persistent_id.replace(":", "_")
	loot.position = data.get("position", Vector3.ZERO)
	loot.set("persistent_id", persistent_id)
	loot.set("item_name", str(data.get("item_name", "Moon Shard")))
	loot.set("amount", int(data.get("amount", 1)))
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.65
	collision.shape = shape
	loot.add_child(collision)
	if DisplayServer.get_name() != "headless":
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.42, 0.42, 0.42)
		visual.mesh = mesh
		visual.material_override = _material(Color("9ca8ff"), TEX_METAL)
		loot.add_child(visual)
	root.add_child(loot)

func _spawn_boss_reward(root: Node3D, dungeon_id: String, local_position: Vector3) -> void:
	var definition: Dictionary = DUNGEON_CATALOG.get_dungeon(dungeon_id)
	var reward_id := "loot:dungeon:%s:boss_reward" % dungeon_id
	if root.has_node(reward_id.replace(":", "_")) or _entity_collected(reward_id):
		return
	_spawn_loot(root, {
		"id": reward_id,
		"position": local_position,
		"item_name": str(definition.get("reward_item", "Moon Shard")),
		"amount": int(definition.get("reward_amount", 5))
	})

func _create_portal(dungeon_id: String, mode: String, display_name: String) -> Area3D:
	var portal := Area3D.new()
	portal.set_script(PORTAL_SCRIPT)
	portal.set("dungeon_id", dungeon_id)
	portal.set("portal_mode", mode)
	portal.set("display_name", display_name)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.25
	collision.shape = shape
	portal.add_child(collision)
	if DisplayServer.get_name() != "headless":
		var accent: Color = DUNGEON_CATALOG.get_dungeon(dungeon_id).get("accent", Color("8f9dff"))
		var stone: Color = DUNGEON_CATALOG.get_dungeon(dungeon_id).get("stone", Color("4e4d60"))
		_mesh_box(portal, Vector3(-1.15, 1.5, 0), Vector3(0.55, 3.0, 0.65), stone)
		_mesh_box(portal, Vector3(1.15, 1.5, 0), Vector3(0.55, 3.0, 0.65), stone)
		_mesh_box(portal, Vector3(0, 2.85, 0), Vector3(2.85, 0.55, 0.65), stone)
		var glow := _mesh_sphere(portal, Vector3(0, 1.35, 0.05), 0.52, accent)
		glow.scale = Vector3(1.25, 1.8, 0.35)
	return portal

func _entity_dead(entity_id: String) -> bool:
	if world_state == null or not world_state.has_method("get_entity_state"):
		return false
	var state: Dictionary = world_state.call("get_entity_state", entity_id)
	return bool(state.get("dead", false))

func _entity_collected(entity_id: String) -> bool:
	if world_state == null or not world_state.has_method("get_entity_state"):
		return false
	var state: Dictionary = world_state.call("get_entity_state", entity_id)
	return bool(state.get("collected", false))

func _world_seed() -> int:
	if world_state != null:
		return int(world_state.get("world_seed"))
	return 8242601

func _add_capsule_collision(body: CollisionObject3D, radius: float, height: float) -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position.y = height * 0.5
	body.add_child(collision)

func _build_enemy_visual(enemy: Node3D, body_color: Color, accent: Color, boss_scale: bool) -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	if boss_scale:
		visual.scale = Vector3(1.32, 1.32, 1.32)
	enemy.add_child(visual)
	_mesh_box(visual, Vector3(0, 1.28, 0), Vector3(0.82, 0.95, 0.48), body_color)
	_mesh_sphere(visual, Vector3(0, 1.98, 0), 0.29, body_color.lightened(0.12))
	_mesh_box(visual, Vector3(0, 1.02, 0.28), Vector3(0.86, 1.28, 0.08), body_color.darkened(0.28))
	_mesh_box(visual, Vector3(0, 2.0, -0.29), Vector3(0.32, 0.06, 0.04), accent)
	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.58, 1.18, 0)
	weapon_pivot.rotation_degrees.z = 30.0
	visual.add_child(weapon_pivot)
	_mesh_box(weapon_pivot, Vector3(0, 0.62, 0), Vector3(0.12, 1.25, 0.09), body_color.lightened(0.32))

func _add_static_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	if DisplayServer.get_name() != "headless":
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		visual.mesh = mesh
		visual.material_override = _material(color, TEX_STONE)
		body.add_child(visual)
	parent.add_child(body)
	return body

func _mesh_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.position = pos
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(color, TEX_STONE)
	parent.add_child(visual)
	return visual

func _mesh_sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.position = pos
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	visual.mesh = mesh
	var material := _material(color, TEX_METAL)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	visual.material_override = material
	parent.add_child(visual)
	return visual

func _material(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if texture != null:
		material.albedo_texture = texture
	return material

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 136
	title_label = Label.new()
	title_label.position = Vector2(150, 92)
	title_label.size = Vector2(340, 32)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 14)
	layer.add_child(title_label)
	world.add_child(layer)

func _show_title(text: String) -> void:
	if title_label == null:
		return
	title_label.text = text
	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(title_label, "modulate", Color(1, 1, 1, 0), 0.6)
	tween.tween_callback(_clear_title)

func _clear_title() -> void:
	if title_label != null:
		title_label.text = ""
		title_label.modulate = Color.WHITE
