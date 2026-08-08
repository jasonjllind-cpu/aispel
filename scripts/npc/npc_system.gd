extends Node
class_name NPCSystem

const NPC_CATALOG := preload("res://scripts/npc/npc_catalog.gd")
const NPC_ACTOR_SCRIPT := preload("res://scripts/npc/npc_actor.gd")
const TEX_CLOTH := preload("res://assets/textures/cloth.svg")
const TEX_METAL := preload("res://assets/textures/metal.svg")

const SCAN_INTERVAL: float = 0.50

var world: Node3D
var world_state: Node
var scan_timer: float = 0.0
var active_npc_id: String = ""
var active_player: Node
var active_lines: Array[String] = []
var active_line_index: int = 0

var dialogue_panel: ColorRect
var name_label: Label
var role_label: Label
var dialogue_label: Label
var quest_label: Label

func _ready() -> void:
	add_to_group("npc_system")
	set_process(false)
	call_deferred("_install")

func _install() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	world = get_parent() as Node3D
	if world == null:
		return
	world_state = get_node_or_null("/root/WorldState")
	if DisplayServer.get_name() != "headless":
		_build_ui()
	_scan_regions()
	_refresh_quest_tracker()
	set_process(true)

func _process(delta: float) -> void:
	scan_timer += delta
	if scan_timer >= SCAN_INTERVAL:
		scan_timer = 0.0
		_scan_regions()
		_refresh_quest_tracker()

func _scan_regions() -> void:
	if world == null:
		return
	_spawn_region_npcs(world, "starting_valley", "NPCsStartingValley")
	var runtime_regions := world.get_node_or_null("RuntimeRegions") as Node3D
	if runtime_regions == null:
		return
	for child in runtime_regions.get_children():
		if not child is Node3D:
			continue
		var region_node := child as Node3D
		var region_id: String = region_node.name.trim_prefix("Region_")
		_spawn_region_npcs(region_node, region_id, "NPCs")

func _spawn_region_npcs(parent: Node3D, region_id: String, child_name: String) -> void:
	if parent.has_node(child_name):
		return
	var definitions: Array[Dictionary] = NPC_CATALOG.get_region_npcs(region_id)
	if definitions.is_empty():
		return
	var root := Node3D.new()
	root.name = child_name
	root.set_meta("region_id", region_id)
	parent.add_child(root)
	for definition in definitions:
		_spawn_npc(root, definition)

func _spawn_npc(parent: Node3D, definition: Dictionary) -> void:
	var actor := StaticBody3D.new()
	actor.set_script(NPC_ACTOR_SCRIPT)
	actor.name = "NPC_%s" % str(definition.get("id", "unknown"))
	actor.position = definition.get("position", Vector3.ZERO)
	actor.set("npc_id", str(definition.get("id", "")))
	actor.set("display_name", str(definition.get("display_name", "Unknown Wanderer")))
	actor.set("role", str(definition.get("role", "")))

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.44
	capsule.height = 1.85
	collision.shape = capsule
	collision.position.y = 0.93
	actor.add_child(collision)
	if DisplayServer.get_name() != "headless":
		_build_npc_visual(actor, definition)
	parent.add_child(actor)

func _build_npc_visual(actor: Node3D, definition: Dictionary) -> void:
	var body_color: Color = definition.get("body_color", Color("5c5873"))
	var accent: Color = definition.get("accent_color", Color("9ea9ff"))
	var visual := Node3D.new()
	visual.name = "Visual"
	actor.add_child(visual)
	_mesh_box(visual, "Torso", Vector3(0, 1.25, 0), Vector3(0.72, 0.92, 0.42), body_color, TEX_CLOTH)
	_mesh_box(visual, "Mantle", Vector3(0, 1.48, 0.12), Vector3(0.88, 0.30, 0.50), body_color.lightened(0.12), TEX_CLOTH)
	_mesh_sphere(visual, "Head", Vector3(0, 1.92, 0), 0.27, Color("b99b82"))
	_mesh_cylinder(visual, "LegL", Vector3(-0.19, 0.35, 0), 0.85, 0.13, body_color.darkened(0.24), TEX_CLOTH)
	_mesh_cylinder(visual, "LegR", Vector3(0.19, 0.35, 0), 0.85, 0.13, body_color.darkened(0.24), TEX_CLOTH)
	_mesh_cylinder(visual, "Staff", Vector3(0.52, 0.95, 0.04), 1.90, 0.055, accent.darkened(0.25), TEX_METAL)
	var marker := _mesh_sphere(visual, "Accent", Vector3(0.52, 1.90, 0.04), 0.11, accent)
	marker.scale = Vector3(1.0, 1.2, 1.0)

func begin_conversation(npc_id: String, player: Node) -> void:
	if npc_id.is_empty():
		return
	if active_npc_id == npc_id and dialogue_panel != null and dialogue_panel.visible:
		_advance_dialogue()
		return
	var definition: Dictionary = NPC_CATALOG.get_npc(npc_id)
	if definition.is_empty():
		return
	active_npc_id = npc_id
	active_player = player
	active_lines = _conversation_lines(definition, player)
	active_line_index = 0
	if active_lines.is_empty():
		active_lines = ["..."]
	if dialogue_panel != null:
		name_label.text = str(definition.get("display_name", "Unknown Wanderer"))
		role_label.text = str(definition.get("role", ""))
		dialogue_panel.visible = true
		_show_current_line()

func _conversation_lines(definition: Dictionary, player: Node) -> Array[String]:
	var lines: Array[String] = []
	var quest_value: Variant = definition.get("quest", {})
	if quest_value is Dictionary and not (quest_value as Dictionary).is_empty():
		var quest: Dictionary = quest_value as Dictionary
		var quest_id: String = str(quest.get("id", ""))
		var state: Dictionary = _get_quest_state(quest_id)
		var status: String = str(state.get("status", "not_started"))
		if status == "active" and _quest_objective_complete(quest):
			_complete_quest(quest, player)
			lines.append(str(quest.get("complete_text", "The task is complete.")))
			lines.append("Quest completed — %s" % str(quest.get("title", quest_id)))
			return lines
		if status == "not_started":
			_append_dialogue(lines, definition.get("dialogue", []))
			lines.append(str(quest.get("offer_text", "I have a task for you.")))
			_start_quest(quest)
			lines.append("Quest started — %s\n%s" % [str(quest.get("title", quest_id)), str(quest.get("objective_text", ""))])
			return lines
		if status == "active":
			lines.append(str(quest.get("active_text", quest.get("objective_text", "The task remains."))))
			return lines
		if status == "completed":
			_append_dialogue(lines, definition.get("dialogue", []))
			return lines
	_append_dialogue(lines, definition.get("dialogue", []))
	if definition.has("merchant_id"):
		lines.append("I am sorting the relic stock. Trading will open when the next caravan reaches the valley.")
	return lines

func _append_dialogue(lines: Array[String], value: Variant) -> void:
	if not value is Array:
		return
	for line in value as Array:
		lines.append(str(line))

func _advance_dialogue() -> void:
	active_line_index += 1
	if active_line_index >= active_lines.size():
		_close_dialogue()
		return
	_show_current_line()

func _show_current_line() -> void:
	if dialogue_label == null or active_lines.is_empty():
		return
	dialogue_label.text = "%s\n\n[E] Continue" % active_lines[active_line_index]

func _close_dialogue() -> void:
	if dialogue_panel != null:
		dialogue_panel.visible = false
	active_npc_id = ""
	active_player = null
	active_lines.clear()
	active_line_index = 0
	_refresh_quest_tracker()

func _start_quest(quest: Dictionary) -> void:
	var quest_id: String = str(quest.get("id", ""))
	if quest_id.is_empty():
		return
	_set_quest_state(quest_id, {
		"status": "active",
		"title": str(quest.get("title", quest_id)),
		"objective_type": str(quest.get("objective_type", "")),
		"objective_id": str(quest.get("objective_id", ""))
	})
	_refresh_quest_tracker()

func _complete_quest(quest: Dictionary, player: Node) -> void:
	var quest_id: String = str(quest.get("id", ""))
	var reward_item: String = str(quest.get("reward_item", ""))
	var reward_amount: int = int(quest.get("reward_amount", 0))
	if not reward_item.is_empty() and reward_amount > 0 and player != null and player.has_method("receive_loot"):
		player.call("receive_loot", reward_item, reward_amount)
	_set_quest_state(quest_id, {
		"status": "completed",
		"title": str(quest.get("title", quest_id)),
		"reward_item": reward_item,
		"reward_amount": reward_amount
	})
	_refresh_quest_tracker()

func _quest_objective_complete(quest: Dictionary) -> bool:
	var objective_type: String = str(quest.get("objective_type", ""))
	var objective_id: String = str(quest.get("objective_id", ""))
	if objective_type == "discover_region" and world_state != null and world_state.has_method("is_region_discovered"):
		return bool(world_state.call("is_region_discovered", objective_id))
	return false

func _get_quest_state(quest_id: String) -> Dictionary:
	if world_state == null or not world_state.has_method("get_entity_state"):
		return {}
	return world_state.call("get_entity_state", "quest:%s" % quest_id)

func _set_quest_state(quest_id: String, state: Dictionary) -> void:
	if world_state != null and world_state.has_method("set_entity_state"):
		world_state.call("set_entity_state", "quest:%s" % quest_id, state)

func _refresh_quest_tracker() -> void:
	if quest_label == null:
		return
	var active_text: String = ""
	for npc_id in NPC_CATALOG.get_npc_ids():
		var definition: Dictionary = NPC_CATALOG.get_npc(npc_id)
		var quest_value: Variant = definition.get("quest", {})
		if not quest_value is Dictionary:
			continue
		var quest: Dictionary = quest_value as Dictionary
		var quest_id: String = str(quest.get("id", ""))
		var state: Dictionary = _get_quest_state(quest_id)
		if str(state.get("status", "")) == "active":
			var suffix: String = " — RETURN" if _quest_objective_complete(quest) else ""
			active_text = "%s\n%s%s" % [str(quest.get("title", quest_id)), str(quest.get("objective_text", "")), suffix]
			break
	quest_label.text = active_text

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 132

	dialogue_panel = ColorRect.new()
	dialogue_panel.position = Vector2(88, 242)
	dialogue_panel.size = Vector2(464, 105)
	dialogue_panel.color = Color(0.025, 0.020, 0.055, 0.95)
	dialogue_panel.visible = false
	dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dialogue_panel)

	name_label = Label.new()
	name_label.position = Vector2(12, 8)
	name_label.size = Vector2(160, 20)
	name_label.add_theme_font_size_override("font_size", 13)
	dialogue_panel.add_child(name_label)

	role_label = Label.new()
	role_label.position = Vector2(174, 9)
	role_label.size = Vector2(278, 18)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	role_label.add_theme_font_size_override("font_size", 9)
	dialogue_panel.add_child(role_label)

	dialogue_label = Label.new()
	dialogue_label.position = Vector2(12, 31)
	dialogue_label.size = Vector2(440, 66)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.add_theme_font_size_override("font_size", 10)
	dialogue_panel.add_child(dialogue_label)

	quest_label = Label.new()
	quest_label.position = Vector2(10, 56)
	quest_label.size = Vector2(210, 44)
	quest_label.add_theme_font_size_override("font_size", 9)
	layer.add_child(quest_label)

	world.add_child(layer)

func _material(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if texture != null:
		material.albedo_texture = texture
	return material

func _mesh_box(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.position = pos
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(color, texture)
	parent.add_child(node)
	return node

func _mesh_sphere(parent: Node3D, node_name: String, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.position = pos
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	node.mesh = mesh
	node.material_override = _material(color)
	parent.add_child(node)
	return node

func _mesh_cylinder(parent: Node3D, node_name: String, pos: Vector3, height: float, radius: float, color: Color, texture: Texture2D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.position = pos
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.radial_segments = 6
	mesh.rings = 1
	node.mesh = mesh
	node.material_override = _material(color, texture)
	parent.add_child(node)
	return node
