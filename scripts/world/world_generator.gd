extends RefCounted
class_name WorldGenerator

const BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")
const BIOME_MAP_SCRIPT := preload("res://scripts/world/biome_map.gd")

const CHUNK_SIZE: float = 28.0
const CELLS_PER_SIDE: int = 8
const VERTICES_PER_SIDE: int = CELLS_PER_SIDE + 1

var world_seed: int = 8242601
var height_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var biome_map: RefCounted

func configure(seed_value: int) -> void:
	world_seed = seed_value if seed_value != 0 else 8242601
	height_noise.seed = _layer_seed("terrain:base")
	height_noise.frequency = 0.0105
	detail_noise.seed = _layer_seed("terrain:detail")
	detail_noise.frequency = 0.031
	ridge_noise.seed = _layer_seed("terrain:ridge")
	ridge_noise.frequency = 0.0065
	biome_map = BIOME_MAP_SCRIPT.new()
	biome_map.call("configure", _layer_seed("biome_map"))

func generation_seed(region_id: String, layer_id: String, chunk_coord: Vector2i = Vector2i.ZERO) -> int:
	return _layer_seed("%s:%s:%d:%d" % [region_id, layer_id, chunk_coord.x, chunk_coord.y])

func generate_chunk_data(region_id: String, preferred_biome: String, region_center: Vector3, chunk_coord: Vector2i, reserved_slots: Array[Dictionary] = []) -> Dictionary:
	if biome_map == null:
		configure(world_seed)

	var biome: Dictionary = BIOME_CATALOG.get_biome(preferred_biome)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var collision_faces := PackedVector3Array()
	var origin_x: float = float(chunk_coord.x) * CHUNK_SIZE
	var origin_z: float = float(chunk_coord.y) * CHUNK_SIZE
	var step: float = CHUNK_SIZE / float(CELLS_PER_SIDE)

	for z_index in range(VERTICES_PER_SIDE):
		for x_index in range(VERTICES_PER_SIDE):
			var local_x: float = origin_x + float(x_index) * step
			var local_z: float = origin_z + float(z_index) * step
			var global_x: float = region_center.x + local_x
			var global_z: float = region_center.z + local_z
			var height: float = _sample_height(global_x, global_z, local_x, local_z, biome, reserved_slots)
			vertices.append(Vector3(local_x, height, local_z))

			var left_h: float = _sample_height(global_x - step, global_z, local_x - step, local_z, biome, reserved_slots)
			var right_h: float = _sample_height(global_x + step, global_z, local_x + step, local_z, biome, reserved_slots)
			var down_h: float = _sample_height(global_x, global_z - step, local_x, local_z - step, biome, reserved_slots)
			var up_h: float = _sample_height(global_x, global_z + step, local_x, local_z + step, biome, reserved_slots)
			var normal := Vector3(left_h - right_h, step * 2.0, down_h - up_h).normalized()
			normals.append(normal)

			var biome_sample: Dictionary = biome_map.call("sample", global_x, global_z, preferred_biome)
			var color: Color = biome_map.call("ground_color", biome_sample)
			var shade: float = clamp(0.94 + normal.y * 0.08 + height * 0.018, 0.86, 1.08)
			colors.append(Color(color.r * shade, color.g * shade, color.b * shade, 1.0))

	for z_index in range(CELLS_PER_SIDE):
		for x_index in range(CELLS_PER_SIDE):
			var row: int = z_index * VERTICES_PER_SIDE
			var next_row: int = (z_index + 1) * VERTICES_PER_SIDE
			var a: int = row + x_index
			var b: int = row + x_index + 1
			var c: int = next_row + x_index
			var d: int = next_row + x_index + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)

	for index in indices:
		collision_faces.append(vertices[index])

	var center_global := Vector2(region_center.x + origin_x + CHUNK_SIZE * 0.5, region_center.z + origin_z + CHUNK_SIZE * 0.5)
	var center_biome: Dictionary = biome_map.call("sample", center_global.x, center_global.y, preferred_biome)
	return {
		"format_version": 1,
		"region_id": region_id,
		"chunk_coord": chunk_coord,
		"chunk_id": "%s:%d:%d" % [region_id, chunk_coord.x, chunk_coord.y],
		"generation_seed": generation_seed(region_id, "terrain", chunk_coord),
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"collision_faces": collision_faces,
		"center_biome": center_biome
	}

func sample_height_at(region_center: Vector3, preferred_biome: String, local_position: Vector2, reserved_slots: Array[Dictionary] = []) -> float:
	var biome: Dictionary = BIOME_CATALOG.get_biome(preferred_biome)
	return _sample_height(region_center.x + local_position.x, region_center.z + local_position.y, local_position.x, local_position.y, biome, reserved_slots)

func sample_biome_at(world_position: Vector3, preferred_biome: String) -> Dictionary:
	if biome_map == null:
		configure(world_seed)
	return biome_map.call("sample", world_position.x, world_position.z, preferred_biome)

func _sample_height(global_x: float, global_z: float, local_x: float, local_z: float, biome: Dictionary, reserved_slots: Array[Dictionary]) -> float:
	var elevation: float = float(biome.get("elevation", 1.0))
	var terrain_scale: float = float(biome.get("terrain_scale", 1.0))
	var detail_strength: float = float(biome.get("terrain_detail", 0.4))
	var ridge_strength: float = float(biome.get("terrain_ridge", 0.15))
	var base_value: float = (height_noise.get_noise_2d(global_x, global_z) + 1.0) * 0.5
	var detail_value: float = detail_noise.get_noise_2d(global_x, global_z)
	var ridge_value: float = abs(ridge_noise.get_noise_2d(global_x, global_z))
	var amplitude: float = (0.55 + elevation * 0.20) * terrain_scale
	var height: float = 0.10 + base_value * amplitude + detail_value * detail_strength * 0.22 + ridge_value * ridge_strength * 0.55

	var road_t: float = clamp((48.0 - local_z) / 96.0, 0.0, 1.0)
	var road_x: float = sin(road_t * TAU * 1.15) * 5.0
	var road_distance: float = abs(local_x - road_x)
	var road_flatten: float = clamp((9.0 - road_distance) / 5.0, 0.0, 1.0)
	height = lerp(height, 0.015, road_flatten * 0.96)

	var encounter_slots: Array[Vector2] = [Vector2(-20, 12), Vector2(18, -2), Vector2(-8, -32)]
	for encounter_center in encounter_slots:
		var encounter_distance: float = Vector2(local_x, local_z).distance_to(encounter_center)
		var encounter_flatten: float = clamp((6.0 - encounter_distance) / 3.5, 0.0, 1.0)
		height = lerp(height, 0.04, encounter_flatten * 0.88)

	for slot in reserved_slots:
		var slot_center: Vector2 = slot.get("center", Vector2.ZERO)
		var radius: float = float(slot.get("radius", 10.0))
		var feather: float = max(2.0, float(slot.get("feather", 6.0)))
		var slot_height: float = float(slot.get("height", 0.04))
		var distance: float = Vector2(local_x, local_z).distance_to(slot_center)
		var flatten: float = clamp((radius + feather - distance) / feather, 0.0, 1.0)
		height = lerp(height, slot_height, flatten)

	return max(0.012, height)

func _layer_seed(scope_id: String) -> int:
	return int(("%d:%s" % [world_seed, scope_id]).hash() & 0x7fffffff)
