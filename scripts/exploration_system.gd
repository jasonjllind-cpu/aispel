extends Node

const LOCKED_DOOR_SCRIPT := preload("res://scripts/locked_door.gd")
const CHEST_SCRIPT := preload("res://scripts/treasure_chest.gd")
const SHRINE_SCRIPT := preload("res://scripts/checkpoint_shrine.gd")
const TEX_STONE := preload("res://assets/textures/stone.svg")
const TEX_BARK := preload("res://assets/textures/bark.svg")
const TEX_METAL := preload("res://assets/textures/metal.svg")
const TEX_CLOTH := preload("res://assets/textures/cloth.svg")

var world: Node3D
var location_card: ColorRect
var location_label: Label
var location_tween: Tween

var discovery_names: Array[String] = [
	"The Ashen Road",
	"Moon Shrine",
	"The Ruined Keep",
	"The Lonely Watchtower",
	"Whispering Crypt",
	"Starfall Grove",
	"The Abandoned Camp"
]
var discovery_centers: Array[Vector3] = [
	Vector3(0, 0, 12),
	Vector3(-34, 0, -28),
	Vector3(28, 0, -58),
	Vector3(-58, 0, -72),
	Vector3(72, 0, -34),
	Vector3(66, 0, 46),
	Vector3(-16, 0, 4)
]
var discovery_radii: Array[float] = [14.0, 11.0, 18.0, 13.0, 15.0, 12.0, 10.0]
var discovery_lore: Array[String] = [
	"A broken road still points toward the dead kingdom.",
	"Cold moonlight gathers here as if the stones remember it.",
	"The old gate still watches a kingdom that no longer exists.",
	"Someone kept watch here long after there was anything left to guard.",
	"The iron gate bears the same crest as the key from the tower.",
	"Blue light leaks through the roots and stones of this hidden grove.",
	"The fire is cold, but the camp was abandoned recently."
]
var discovered_flags: Array[bool] = [false, false, false, false, false, false, false]

func _ready() -> void:
	set_process(false)
	call_deferred("_install")

func _install() -> void:
	await get_tree().process_frame
	world = get_parent() as Node3D
	if world == null:
		return

	_build_location_ui()
	_build_checkpoint_interaction()
	_build_crypt()
	_build_abandoned_camp()
	_build_secret_grove()
	_spawn_extra_encounters()
	_update_existing_hud()
	set_process(true)

func _process(_delta: float) -> void:
	var player: Node3D = _get_player()
	if player == null:
		return

	var player_flat := Vector2(player.global_position.x, player.global_position.z)
	for i in range(discovery_names.size()):
		if discovered_flags[i]:
			continue
		var center: Vector3 = discovery_centers[i]
		var center_flat := Vector2(center.x, center.z)
		if player_flat.distance_to(center_flat) <= discovery_radii[i]:
			discovered_flags[i] = true
			_show_location(discovery_names[i], discovery_lore[i])

func _get_player() -> Node3D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty() or not players[0] is Node3D:
		return null
	return players[0] as Node3D

func _build_location_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 125

	location_card = ColorRect.new()
	location_card.position = Vector2(130, 48)
	location_card.size = Vector2(380, 58)
	location_card.color = Color(0.025, 0.018, 0.055, 0.88)
	location_card.visible = false
	location_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(location_card)

	location_label = Label.new()
	location_label.position = Vector2(10, 7)
	location_label.size = Vector2(360, 46)
	location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	location_label.add_theme_font_size_override("font_size", 11)
	location_card.add_child(location_label)

	world.add_child(layer)

func _show_location(location_name: String, lore: String) -> void:
	if location_card == null or location_label == null:
		return
	if location_tween != null and location_tween.is_valid():
		location_tween.kill()

	location_label.text = "DISCOVERED — %s\n%s" % [location_name, lore]
	location_card.visible = true
	location_card.modulate = Color.WHITE
	location_tween = create_tween()
	location_tween.tween_interval(2.8)
	location_tween.tween_property(location_card, "modulate", Color(1, 1, 1, 0), 1.0)
	location_tween.tween_callback(_hide_location_card)

func _hide_location_card() -> void:
	if location_card != null:
		location_card.visible = false

func _mat(color: Color, texture: Texture2D = null, roughness: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if texture != null:
		material.albedo_texture = texture
	return material

func _add_static_box(pos: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> StaticBody3D:
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

	world.add_child(body)
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

func _mesh_sphere(parent: Node3D, node_name: String, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = pos
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, null, 0.25)
	parent.add_child(mesh_instance)
	return mesh_instance

func _create_torch(pos: Vector3, light_color: Color = Color("ff9a55")) -> void:
	var torch := Node3D.new()
	torch.position = pos
	_mesh_box(torch, "Pole", Vector3(0, 1.0, 0), Vector3(0.12, 2.0, 0.12), Color("54301f"), TEX_BARK)
	_mesh_sphere(torch, "Flame", Vector3(0, 2.15, 0), 0.20, light_color)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.15, 0)
	light.light_color = light_color
	light.light_energy = 2.0
	light.omni_range = 7.0
	light.shadow_enabled = false
	torch.add_child(light)
	world.add_child(torch)

func _build_checkpoint_interaction() -> void:
	var shrine := Node3D.new()
	shrine.name = "MoonShrineCheckpoint"
	shrine.position = Vector3(-34, 0, -28)
	shrine.set_script(SHRINE_SCRIPT)
	shrine.set("checkpoint_name", "Moon Shrine")
	shrine.set("respawn_offset", Vector3(0, 1.2, 6.0))
	var orb := _mesh_sphere(shrine, "CheckpointOrb", Vector3(0, 2.45, 0), 0.72, Color("aeb8ff"))
	orb.scale = Vector3(1.0, 1.15, 1.0)
	world.add_child(shrine)

func _build_crypt() -> void:
	var base := Vector3(72, 0, -34)
	var stone := Color("4c4a56")
	var dark_stone := Color("32313d")
	var floor_stone := Color("5f5960")

	_add_static_box(base + Vector3(0, 0.12, 0), Vector3(19, 0.24, 17), floor_stone, TEX_STONE)
	_add_static_box(base + Vector3(-9.2, 2.6, 0), Vector3(1.0, 5.2, 17), stone, TEX_STONE)
	_add_static_box(base + Vector3(9.2, 2.6, 4.8), Vector3(1.0, 5.2, 7.4), stone, TEX_STONE)
	_add_static_box(base + Vector3(9.2, 2.6, -6.2), Vector3(1.0, 5.2, 4.8), stone, TEX_STONE)
	_add_static_box(base + Vector3(0, 2.6, -8.2), Vector3(19, 5.2, 1.0), dark_stone, TEX_STONE)
	_add_static_box(base + Vector3(-5.8, 2.6, 8.2), Vector3(7.4, 5.2, 1.0), stone, TEX_STONE)
	_add_static_box(base + Vector3(5.8, 2.6, 8.2), Vector3(7.4, 5.2, 1.0), stone, TEX_STONE)
	_add_static_box(base + Vector3(0, 5.25, 0), Vector3(19, 0.55, 17), dark_stone, TEX_STONE)

	for x in [-5.5, 5.5]:
		for z in [-4.8, 1.8]:
			_add_static_box(base + Vector3(x, 2.25, z), Vector3(1.0, 4.5, 1.0), Color("55535e"), TEX_STONE)

	_add_static_box(base + Vector3(0, 0.55, -6.9), Vector3(4.8, 1.1, 2.2), Color("625d68"), TEX_STONE)
	_add_static_box(base + Vector3(0, 1.65, -7.5), Vector3(2.8, 2.2, 0.9), Color("3b3944"), TEX_STONE)

	_build_crypt_side_room(base)
	_create_locked_gate(base + Vector3(0, 1.65, 8.0))
	_create_chest(base + Vector3(0, 0.0, -5.6), "Crypt Fang", 1, "Gravekeeper's Chest", true)
	_create_chest(base + Vector3(13.8, 0.0, -2.0), "Moon Shard", 4, "Hidden Reliquary", true)

	_create_torch(base + Vector3(-6.6, 0, 4.5), Color("ff7e54"))
	_create_torch(base + Vector3(6.6, 0, 4.5), Color("ff7e54"))
	_create_torch(base + Vector3(-6.6, 0, -5.0), Color("7e8dff"))
	_create_torch(base + Vector3(6.6, 0, -5.0), Color("7e8dff"))

func _build_crypt_side_room(base: Vector3) -> void:
	var side := base + Vector3(14.0, 0, -2.0)
	_add_static_box(side + Vector3(0, 0.12, 0), Vector3(9, 0.24, 8), Color("57515a"), TEX_STONE)
	_add_static_box(side + Vector3(4.2, 2.4, 0), Vector3(0.8, 4.8, 8), Color("3d3b46"), TEX_STONE)
	_add_static_box(side + Vector3(0, 2.4, -3.6), Vector3(9, 4.8, 0.8), Color("3d3b46"), TEX_STONE)
	_add_static_box(side + Vector3(0, 2.4, 3.6), Vector3(9, 4.8, 0.8), Color("494752"), TEX_STONE)
	_add_static_box(side + Vector3(0, 4.9, 0), Vector3(9, 0.45, 8), Color("30303a"), TEX_STONE)
	_create_torch(side + Vector3(2.6, 0, -2.3), Color("7d89ff"))

func _create_locked_gate(pos: Vector3) -> void:
	var door := StaticBody3D.new()
	door.name = "CryptGate"
	door.position = pos
	door.set_script(LOCKED_DOOR_SCRIPT)
	door.set("required_item", "Old Key")
	door.set("door_name", "Whispering Crypt Gate")

	_mesh_box(door, "Door", Vector3.ZERO, Vector3(3.8, 3.3, 0.35), Color("59525a"), TEX_METAL)
	for x in [-1.45, -0.72, 0.0, 0.72, 1.45]:
		_mesh_box(door, "Bar", Vector3(x, 0, -0.20), Vector3(0.12, 3.4, 0.12), Color("272832"), TEX_METAL)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.8, 3.3, 0.45)
	collision.shape = shape
	door.add_child(collision)
	world.add_child(door)

func _create_chest(pos: Vector3, item_name: String, amount: int, chest_name: String, rare: bool) -> void:
	var chest := StaticBody3D.new()
	chest.name = chest_name.replace(" ", "")
	chest.position = pos
	chest.set_script(CHEST_SCRIPT)
	chest.set("item_name", item_name)
	chest.set("amount", amount)
	chest.set("chest_name", chest_name)

	_mesh_box(chest, "Base", Vector3(0, 0.42, 0), Vector3(1.65, 0.80, 1.0), Color("5a3525"), TEX_BARK)
	var lid := _mesh_box(chest, "Lid", Vector3(0, 0.97, 0), Vector3(1.72, 0.34, 1.06), Color("70452c"), TEX_BARK)
	lid.rotation_degrees.x = 0.0
	_mesh_box(chest, "Band", Vector3(0, 0.62, -0.52), Vector3(0.30, 0.95, 0.08), Color("8a7750"), TEX_METAL)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.75, 1.20, 1.08)
	collision.shape = shape
	collision.position.y = 0.58
	chest.add_child(collision)

	if rare:
		var light := OmniLight3D.new()
		light.position = Vector3(0, 1.15, 0)
		light.light_color = Color("8599ff")
		light.light_energy = 1.0
		light.omni_range = 4.5
		light.shadow_enabled = false
		chest.add_child(light)

	world.add_child(chest)

func _build_abandoned_camp() -> void:
	var base := Vector3(-16, 0, 4)
	_add_static_box(base + Vector3(-2.8, 0.45, 1.7), Vector3(2.4, 0.9, 1.4), Color("493225"), TEX_BARK)
	_add_static_box(base + Vector3(3.2, 0.35, 2.0), Vector3(1.3, 0.7, 1.3), Color("5b3c29"), TEX_BARK)
	_add_static_box(base + Vector3(0, 0.14, -1.0), Vector3(4.5, 0.20, 3.0), Color("4a4035"), TEX_CLOTH)
	_create_torch(base + Vector3(0.0, 0, 1.0), Color("ff8a4d"))
	_create_chest(base + Vector3(-4.4, 0, -1.4), "Ancient Coin", 5, "Camp Strongbox", false)

func _build_secret_grove() -> void:
	var base := Vector3(66, 0, 46)
	for i in range(8):
		var angle: float = TAU * float(i) / 8.0
		var ring_pos := base + Vector3(cos(angle) * 5.2, 1.2, sin(angle) * 5.2)
		_add_static_box(ring_pos, Vector3(1.0, 2.4 + float(i % 3) * 0.5, 0.8), Color("565766"), TEX_STONE)
	_create_chest(base + Vector3(0, 0, 0), "Moon Shard", 3, "Starfall Cache", true)
	var glow := OmniLight3D.new()
	glow.position = base + Vector3(0, 2.0, 0)
	glow.light_color = Color("7c8cff")
	glow.light_energy = 1.4
	glow.omni_range = 9.0
	glow.shadow_enabled = false
	world.add_child(glow)

func _spawn_extra_encounters() -> void:
	if not world.has_method("_create_enemy"):
		return
	world.call("_create_enemy", Vector3(-11, 1.0, 0))
	world.call("_create_enemy", Vector3(69, 1.0, -38))
	world.call("_create_enemy", Vector3(76, 1.0, -40))

func _update_existing_hud() -> void:
	var nodes: Array[Node] = world.find_children("*", "Label", true, false)
	for node in nodes:
		if not node is Label:
			continue
		var label := node as Label
		if label.text.begins_with("0.12"):
			label.text = "0.16  •  WASD move  •  Shift run  •  Space jump  •  E interact  •  LMB attack  •  I inventory"
		elif label.text.begins_with("Follow the old road"):
			label.text = "Explore freely. Find the Old Key at the watchtower, unlock Whispering Crypt and rest at the Moon Shrine."
