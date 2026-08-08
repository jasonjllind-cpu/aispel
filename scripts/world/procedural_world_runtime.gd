extends "res://scripts/world/procedural_world_system.gd"

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")

func _build_starting_valley_terrain() -> void:
	if world == null or world.has_node("GeneratedStartingValley"):
		return
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var reserved_slots: Array[Dictionary] = REGION_CATALOG.get_slots("starting_valley")
	var terrain_root := Node3D.new()
	terrain_root.name = "GeneratedStartingValley"
	world.add_child(terrain_root)
	_build_chunks(terrain_root, "starting_valley", biome_id, REGION_CATALOG.get_center("starting_valley"), reserved_slots, -3, 3)

func _scan_runtime_regions() -> void:
	if world == null:
		return
	var active_generated: int = 1 if world.has_node("GeneratedStartingValley") else 0
	var runtime_regions := world.get_node_or_null("RuntimeRegions") as Node3D
	if runtime_regions != null:
		for child in runtime_regions.get_children():
			if not child is Node3D:
				continue
			var region_node := child as Node3D
			var region_id: String = region_node.name.trim_prefix("Region_")
			if not REGION_CATALOG.has_region(region_id) or region_id == "starting_valley":
				continue
			if not region_node.has_node("GeneratedTerrain"):
				_build_region_terrain(region_node, region_id)
			if region_node.has_node("GeneratedTerrain"):
				active_generated += 1
	generated_region_count = active_generated
	_refresh_status()

func _build_region_terrain(region_node: Node3D, region_id: String) -> void:
	var biome_id: String = REGION_CATALOG.get_biome_id(region_id)
	var reserved_slots: Array[Dictionary] = REGION_CATALOG.get_slots(region_id)
	var terrain_root := Node3D.new()
	terrain_root.name = "GeneratedTerrain"
	region_node.add_child(terrain_root)
	_build_chunks(terrain_root, region_id, biome_id, REGION_CATALOG.get_center(region_id), reserved_slots, -2, 2)
