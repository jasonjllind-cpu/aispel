extends "res://scripts/world/region_manager.gd"

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const RUNTIME_BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")
const CATALOG_LOAD_RADIUS: float = 145.0
const CATALOG_UNLOAD_RADIUS: float = 185.0

func _update_streaming() -> void:
	var player: Node3D = _get_player()
	if player == null:
		return

	var player_pos: Vector3 = player.global_position
	var nearest_id: String = "starting_valley"
	var nearest_distance: float = INF

	for region_id in REGION_CATALOG.get_region_ids():
		var definition: Dictionary = REGION_CATALOG.get_region(region_id)
		var center: Vector3 = definition.get("center", Vector3.ZERO)
		var distance: float = _flat_distance(player_pos, center)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = region_id

		if bool(definition.get("external", false)):
			continue
		if distance <= CATALOG_LOAD_RADIUS and not loaded_regions.has(region_id):
			_load_region(definition)
		elif distance >= CATALOG_UNLOAD_RADIUS and loaded_regions.has(region_id):
			_unload_region(region_id)

	var nearest_definition: Dictionary = REGION_CATALOG.get_region(nearest_id)
	var nearest_radius: float = float(nearest_definition.get("radius", 70.0))
	if nearest_distance <= nearest_radius and nearest_id != current_region_id:
		_enter_region(nearest_id)

	if debug_label != null:
		var seed_value: int = 8242601
		if world_state != null:
			seed_value = int(world_state.get("world_seed"))
		debug_label.text = "Region: %s   •   World seed: %d" % [_region_display_name(current_region_id), seed_value]

func _load_region(definition: Dictionary) -> void:
	var region_id: String = str(definition.get("id", "unknown"))
	var biome_id: String = str(definition.get("biome", "green_highlands"))
	var center: Vector3 = definition.get("center", Vector3.ZERO)
	var biome: Dictionary = RUNTIME_BIOME_CATALOG.get_biome(biome_id)

	var region_node := Node3D.new()
	region_node.name = "Region_%s" % region_id
	region_node.position = center
	regions_root.add_child(region_node)
	loaded_regions[region_id] = region_node

	# RegionManager owns only lifecycle and authored landmark modules.
	# Terrain, roads, vegetation, minor POIs, encounters and loot are generated
	# by their dedicated deterministic systems.
	_build_region_landmark(region_node, region_id, biome)

func _get_region_definition(region_id: String) -> Dictionary:
	return REGION_CATALOG.get_region(region_id)
