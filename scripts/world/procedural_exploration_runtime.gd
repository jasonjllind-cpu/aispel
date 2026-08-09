extends "res://scripts/world/procedural_exploration_system.gd"

func _build_ui() -> void:
	super._build_ui()
	if status_label != null:
		status_label.free()
		status_label = null
	if discovery_card != null:
		discovery_card.position = Vector2(145, 42)

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless"

func _build_road(root: Node3D, data: Dictionary, biome: Dictionary) -> void:
	if _is_headless_runtime():
		return
	super._build_road(root, data, biome)

func _build_vegetation(root: Node3D, data: Dictionary, biome: Dictionary) -> void:
	# Dedicated/headless runtimes own world state and gameplay, but do not need
	# cosmetic MultiMesh vegetation. Keeping this boundary explicit avoids
	# renderer-only work on future dedicated servers and keeps CI deterministic.
	if _is_headless_runtime():
		return
	super._build_vegetation(root, data, biome)

func _build_minor_ruin(parent: Node3D, biome: Dictionary) -> void:
	if _is_headless_runtime():
		return
	super._build_minor_ruin(parent, biome)

func _build_camp(parent: Node3D, biome: Dictionary) -> void:
	if _is_headless_runtime():
		return
	super._build_camp(parent, biome)

func _build_cave(parent: Node3D, biome: Dictionary) -> void:
	if _is_headless_runtime():
		return
	super._build_cave(parent, biome)

func _build_secret(parent: Node3D, biome: Dictionary) -> void:
	if _is_headless_runtime():
		return
	super._build_secret(parent, biome)

func _build_graves(parent: Node3D, biome: Dictionary) -> void:
	if _is_headless_runtime():
		return
	super._build_graves(parent, biome)

func _build_enemy_visual(enemy: CharacterBody3D, biome: Dictionary) -> void:
	if _is_headless_runtime():
		return
	super._build_enemy_visual(enemy, biome)

func _build_loot(root: Node3D, data: Dictionary, biome: Dictionary) -> void:
	if not _is_headless_runtime():
		super._build_loot(root, data, biome)
		return

	# Loot remains authoritative and interactable on a server. Only its visual
	# mesh is omitted; collision, stable ID and persistence stay intact.
	var loot_value: Variant = data.get("loot", [])
	if not loot_value is Array:
		return
	var loot_root := Node3D.new()
	loot_root.name = "GeneratedLoot"
	root.add_child(loot_root)
	for value in loot_value:
		if not value is Dictionary:
			continue
		var loot: Dictionary = value as Dictionary
		var persistent_id: String = str(loot.get("id", ""))
		if _entity_state_bool(persistent_id, "collected"):
			continue
		var area := Area3D.new()
		area.position = loot.get("position", Vector3.ZERO)
		area.set_script(GENERATED_LOOT_SCRIPT)
		area.set("item_name", str(loot.get("item_name", "Ancient Coin")))
		area.set("amount", int(loot.get("amount", 1)))
		area.set("persistent_id", persistent_id)
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.65
		collision.shape = shape
		area.add_child(collision)
		loot_root.add_child(area)
