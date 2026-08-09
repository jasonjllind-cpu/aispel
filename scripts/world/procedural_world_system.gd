extends Node

const WORLD_GENERATOR_SCRIPT := preload("res://scripts/world/world_generator.gd")
const TERRAIN_CHUNK_SCRIPT := preload("res://scripts/world/terrain_chunk.gd")

const CHECK_INTERVAL: float = 0.35
const REGION_CONFIG: Dictionary = {
	"starting_valley": {
		"biome": "green_highlands",
		"slots": [
			{"id": "player_spawn", "center": Vector2(0, 24), "radius": 6.0, "feather": 14.0, "height_mode": "terrain"}
		]
	},
	"blackwood": {
		"biome": "blackwood",
		"slots": [
			{"id": "fallen_chapel", "center": Vector2(-12, -17), "radius": 14.0, "feather": 7.0, "height": 0.035}
		]
	},
	"windscar_highlands": {
		"biome": "windscar_highlands",
		"slots": [
			{"id": "windscar_beacon", "center": Vector2(14, -15), "radius": 13.0, "feather": 8.0, "height": 0.035}
		]
	},
	"veilmoor": {
		"biome": "veilmoor",
		"slots": [
			{"id": "pale_grave_ring", "center": Vector2(0, -11), "radius": 15.0, "feather": 8.0, "height": 0.035}
		]
	}
}

var world: Node3D
var world_state: Node
var generator: RefCounted
var elapsed: float = 0.0
var chunk_data_cache: Dictionary = {}
var generated_region_count: int = 0
var status_label: Label

func _ready() -> void:
	set_process(false)
	call_deferred("_install")

func _install() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	world = get_parent() as Node3D
	if world == null:
		return
	world_state = get_node_or_null("/root/WorldState")
	generator = WORLD_GENERATOR_SCRIPT.new()
	var seed_value: int = 8242601
	if world_state != null:
		seed_value = int(world_state.get("world_seed"))
	generator.call("configure", seed_value)
	_build_status_ui(seed_value)
	_build_starting_valley_terrain()
	_scan_runtime_regions()
	set_process(true)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < CHECK_INTERVAL:
		return
	elapsed = 0.0
	_scan_runtime_regions()

func _build_starting_valley_terrain() -> void:
	if world == null or world.has_node("GeneratedStartingValley"):
		return
	var config: Dictionary = REGION_CONFIG.get("starting_valley", {})
	var biome_id: String = str(config.get("biome", "green_highlands"))
	var reserved_slots: Array[Dictionary] = _reserved_slots_from_config(config)
	var terrain_root := Node3D.new()
	terrain_root.name = "GeneratedStartingValley"
	world.add_child(terrain_root)
	_build_chunks(terrain_root, "starting_valley", biome_id, Vector3.ZERO, reserved_slots, -3, 3)

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
			if not REGION_CONFIG.has(region_id) or region_id == "starting_valley":
				continue
			if not region_node.has_node("GeneratedTerrain"):
				_build_region_terrain(region_node, region_id)
			if region_node.has_node("GeneratedTerrain"):
				active_generated += 1
	generated_region_count = active_generated
	_refresh_status()

func _build_region_terrain(region_node: Node3D, region_id: String) -> void:
	var config: Dictionary = REGION_CONFIG.get(region_id, {})
	var biome_id: String = str(config.get("biome", "green_highlands"))
	var reserved_slots: Array[Dictionary] = _reserved_slots_from_config(config)

	var terrain_root := Node3D.new()
	terrain_root.name = "GeneratedTerrain"
	region_node.add_child(terrain_root)
	_build_chunks(terrain_root, region_id, biome_id, region_node.global_position, reserved_slots, -2, 2)

func _reserved_slots_from_config(config: Dictionary) -> Array[Dictionary]:
	var reserved_slots: Array[Dictionary] = []
	var slots_variant: Variant = config.get("slots", [])
	if slots_variant is Array:
		for slot in slots_variant:
			if slot is Dictionary:
				reserved_slots.append((slot as Dictionary).duplicate(true))
	return reserved_slots

func _build_chunks(parent: Node3D, region_id: String, biome_id: String, region_center: Vector3, reserved_slots: Array[Dictionary], min_coord: int, max_coord_exclusive: int) -> void:
	for chunk_z in range(min_coord, max_coord_exclusive):
		for chunk_x in range(min_coord, max_coord_exclusive):
			var coord := Vector2i(chunk_x, chunk_z)
			var cache_key: String = "%d:%s:%d:%d" % [_world_seed(), region_id, chunk_x, chunk_z]
			var chunk_data: Dictionary
			if chunk_data_cache.has(cache_key):
				chunk_data = (chunk_data_cache[cache_key] as Dictionary).duplicate(true)
			else:
				chunk_data = generator.call("generate_chunk_data", region_id, biome_id, region_center, coord, reserved_slots)
				chunk_data_cache[cache_key] = chunk_data.duplicate(true)

			var chunk := Node3D.new()
			chunk.set_script(TERRAIN_CHUNK_SCRIPT)
			parent.add_child(chunk)
			chunk.call("build_from_data", chunk_data)

func _world_seed() -> int:
	if world_state != null:
		return int(world_state.get("world_seed"))
	return 8242601

func clear_generation_cache() -> void:
	chunk_data_cache.clear()

func get_chunk_data(region_id: String, chunk_coord: Vector2i) -> Dictionary:
	var key: String = "%d:%s:%d:%d" % [_world_seed(), region_id, chunk_coord.x, chunk_coord.y]
	var value: Variant = chunk_data_cache.get(key, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func get_generation_seed(region_id: String, layer_id: String, chunk_coord: Vector2i = Vector2i.ZERO) -> int:
	if generator == null:
		return 0
	return int(generator.call("generation_seed", region_id, layer_id, chunk_coord))

func _build_status_ui(seed_value: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 127
	status_label = Label.new()
	status_label.position = Vector2(350, 25)
	status_label.size = Vector2(280, 18)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", 9)
	status_label.text = "Seed %d  •  Starting Valley generated  •  G seed menu" % seed_value
	layer.add_child(status_label)
	world.add_child(layer)

func _refresh_status() -> void:
	if status_label == null:
		return
	status_label.text = "Seed %d  •  %d generated terrain regions  •  G seed menu" % [_world_seed(), generated_region_count]
