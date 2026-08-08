extends "res://scripts/world/region_manager.gd"

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const RUNTIME_BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")
const LANDMARK_BUILDER_SCRIPT := preload("res://scripts/world/authored_landmark_builder.gd")
const CATALOG_LOAD_RADIUS: float = 145.0
const CATALOG_UNLOAD_RADIUS: float = 185.0

var landmark_builder: RefCounted = LANDMARK_BUILDER_SCRIPT.new()

func _build_backbone_routes() -> void:
	# The inherited manager creates the prototype route geometry during install,
	# before player/streaming checks. Headless and dedicated-server runtimes only
	# need deterministic route data, not client presentation meshes.
	if DisplayServer.get_name() == "headless":
		return
	super._build_backbone_routes()

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

	# RegionManager owns lifecycle only. Authored landmark geometry is delegated
	# to a reusable module; generated terrain/exploration use separate systems.
	landmark_builder.call("build_landmark", region_node, region_id, biome)

func _unload_region(region_id: String) -> void:
	# Return reusable terrain chunks to the generator pool before the region
	# node is freed. Generated exploration content is deterministic and can be
	# rebuilt from data; terrain chunks are the heavier reusable runtime nodes.
	if world != null:
		var procedural_world := world.get_node_or_null("ProceduralWorldSystem")
		if procedural_world != null and procedural_world.has_method("release_region_terrain"):
			procedural_world.call("release_region_terrain", region_id)
	super._unload_region(region_id)

func _get_region_definition(region_id: String) -> Dictionary:
	return REGION_CATALOG.get_region(region_id)
