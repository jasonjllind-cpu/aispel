extends RefCounted
class_name WorldGenerator

const BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")
const BIOME_MAP_SCRIPT := preload("res://scripts/world/biome_map.gd")
const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const VALIDATOR := preload("res://scripts/world/world_generation_validator.gd")

const FORMAT_VERSION: int = 2
const DEFAULT_WORLD_SEED: int = 8242601
const CHUNK_SIZE: float = 28.0
const CELLS_PER_SIDE: int = 8
const VERTICES_PER_SIDE: int = CELLS_PER_SIDE + 1
const ROAD_HALF_WIDTH: float = 3.6
const ROAD_FEATHER: float = 6.0
const MAX_TERRAIN_HEIGHT: float = 18.0
const MIN_TERRAIN_HEIGHT: float = 0.02

var world_seed: int = DEFAULT_WORLD_SEED
var continental_noise := FastNoiseLite.new()
var hill_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var biome_map: RefCounted
var profile: Dictionary = {}

func configure(seed_value: int) -> void:
	world_seed = _sanitize_seed(seed_value)
	var profile_rng := RandomNumberGenerator.new()
	profile_rng.seed = generation_seed("world", "terrain_profile")
	profile = {
		"format_version": FORMAT_VERSION,
		"world_seed": world_seed,
		"continental_frequency": profile_rng.randf_range(0.0038, 0.0075),
		"hill_frequency": profile_rng.randf_range(0.009, 0.020),
		"ridge_frequency": profile_rng.randf_range(0.005, 0.012),
		"detail_frequency": profile_rng.randf_range(0.030, 0.068),
		"continental_height": profile_rng.randf_range(3.8, 7.2),
		"hill_height": profile_rng.randf_range(1.4, 3.6),
		"ridge_height": profile_rng.randf_range(0.8, 3.8),
		"detail_height": profile_rng.randf_range(0.25, 0.95)
	}
	profile["signature"] = "%d:%d:%d:%d" % [
		world_seed,
		int(float(profile["continental_frequency"]) * 100000.0),
		int(float(profile["continental_height"]) * 1000.0),
		int(float(profile["ridge_height"]) * 1000.0)
	]
	_configure_noise(continental_noise, "terrain:continental", float(profile["continental_frequency"]), 4, 0.48)
	_configure_noise(hill_noise, "terrain:hills", float(profile["hill_frequency"]), 3, 0.52)
	_configure_noise(ridge_noise, "terrain:ridges", float(profile["ridge_frequency"]), 3, 0.50)
	_configure_noise(detail_noise, "terrain:detail", float(profile["detail_frequency"]), 2, 0.46)
	biome_map = BIOME_MAP_SCRIPT.new()
	biome_map.call("configure", generation_seed("world", "biome_map"))

func generation_seed(region_id: String, layer_id: String, chunk_coord: Vector2i = Vector2i.ZERO) -> int:
	var scope := "%d|%s|%s|%d|%d" % [world_seed, region_id, layer_id, chunk_coord.x, chunk_coord.y]
	var value: int = int(scope.hash() & 0x7fffffff)
	return value if value > 0 else DEFAULT_WORLD_SEED

func generation_profile() -> Dictionary:
	return profile.duplicate(true)

func primary_route_points(region_id: String, region_center: Vector3, preferred_biome: String, reserved_slots: Array[Dictionary] = []) -> Array[Vector3]:
	_ensure_configured()
	var route_2d: Array[Vector2] = _primary_route_2d(region_id, reserved_slots)
	var biome: Dictionary = BIOME_CATALOG.get_biome(preferred_biome)
	var result: Array[Vector3] = []
	for point in route_2d:
		var height: float = _sample_height(region_id, region_center, point, biome, reserved_slots, route_2d)
		result.append(Vector3(point.x, height + 0.045, point.y))
	return result

func generate_chunk_data(region_id: String, preferred_biome: String, region_center: Vector3, chunk_coord: Vector2i, reserved_slots: Array[Dictionary] = []) -> Dictionary:
	_ensure_configured()
	var biome: Dictionary = BIOME_CATALOG.get_biome(preferred_biome)
	var route: Array[Vector2] = _primary_route_2d(region_id, reserved_slots)
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
			var local := Vector2(origin_x + float(x_index) * step, origin_z + float(z_index) * step)
			var height: float = _sample_height(region_id, region_center, local, biome, reserved_slots, route)
			vertices.append(Vector3(local.x, height, local.y))
			var left_h: float = _sample_height(region_id, region_center, local + Vector2(-step, 0), biome, reserved_slots, route)
			var right_h: float = _sample_height(region_id, region_center, local + Vector2(step, 0), biome, reserved_slots, route)
			var down_h: float = _sample_height(region_id, region_center, local + Vector2(0, -step), biome, reserved_slots, route)
			var up_h: float = _sample_height(region_id, region_center, local + Vector2(0, step), biome, reserved_slots, route)
			var normal := Vector3(left_h - right_h, step * 2.0, down_h - up_h).normalized()
			normals.append(normal)
			var global_position := Vector3(region_center.x + local.x, height, region_center.z + local.y)
			var biome_sample: Dictionary = biome_map.call("sample", global_position.x, global_position.z, preferred_biome)
			var color: Color = biome_map.call("ground_color", biome_sample)
			var shade: float = clamp(0.82 + normal.y * 0.16 + height * 0.012, 0.72, 1.12)
			colors.append(Color(color.r * shade, color.g * shade, color.b * shade, 1.0))

	for z_index in range(CELLS_PER_SIDE):
		for x_index in range(CELLS_PER_SIDE):
			var row: int = z_index * VERTICES_PER_SIDE
			var next_row: int = (z_index + 1) * VERTICES_PER_SIDE
			var a: int = row + x_index
			var b: int = a + 1
			var c: int = next_row + x_index
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	for index in indices:
		collision_faces.append(vertices[index])

	var data := {
		"format_version": FORMAT_VERSION,
		"world_seed": world_seed,
		"profile_signature": str(profile.get("signature", "")),
		"region_id": region_id,
		"chunk_coord": chunk_coord,
		"chunk_id": "%s:%d:%d" % [region_id, chunk_coord.x, chunk_coord.y],
		"generation_seed": generation_seed(region_id, "terrain", chunk_coord),
		"data_signature": _chunk_signature(region_id, chunk_coord, vertices),
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"collision_faces": collision_faces,
		"fallback": false
	}
	var validation: Dictionary = VALIDATOR.validate_chunk(data, VERTICES_PER_SIDE * VERTICES_PER_SIDE)
	if validation.get("ok", false) != true:
		return _fallback_chunk_data(region_id, preferred_biome, chunk_coord, str(validation.get("error", "unknown")))
	data["validation"] = validation
	return data

func validate_chunk_data(data: Dictionary) -> Dictionary:
	return VALIDATOR.validate_chunk(data, VERTICES_PER_SIDE * VERTICES_PER_SIDE)

func sample_height_at(region_center: Vector3, preferred_biome: String, local_position: Vector2, reserved_slots: Array[Dictionary] = [], region_id: String = "starting_valley") -> float:
	_ensure_configured()
	var biome: Dictionary = BIOME_CATALOG.get_biome(preferred_biome)
	var route: Array[Vector2] = _primary_route_2d(region_id, reserved_slots)
	return _sample_height(region_id, region_center, local_position, biome, reserved_slots, route)

func sample_biome_at(world_position: Vector3, preferred_biome: String) -> Dictionary:
	_ensure_configured()
	return biome_map.call("sample", world_position.x, world_position.z, preferred_biome)

func _sample_height(region_id: String, region_center: Vector3, local: Vector2, biome: Dictionary, reserved_slots: Array[Dictionary], route: Array[Vector2]) -> float:
	var world_x: float = region_center.x + local.x
	var world_z: float = region_center.z + local.y
	var terrain_scale: float = clamp(float(biome.get("terrain_scale", 1.0)), 0.45, 1.8)
	var elevation: float = clamp(float(biome.get("elevation", 1.0)), 0.25, 2.5)
	var continental: float = clamp((continental_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5, 0.0, 1.0)
	var hills: float = clamp((hill_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5, 0.0, 1.0)
	var ridge: float = 1.0 - abs(ridge_noise.get_noise_2d(world_x, world_z))
	var detail: float = detail_noise.get_noise_2d(world_x, world_z)
	var height: float = 0.12
	height += pow(continental, 1.65) * float(profile.get("continental_height", 5.0)) * terrain_scale
	height += pow(hills, 1.35) * float(profile.get("hill_height", 2.0)) * elevation
	height += pow(clamp(ridge, 0.0, 1.0), 3.1) * float(profile.get("ridge_height", 2.0))
	height += detail * float(profile.get("detail_height", 0.5))
	height = clamp(height, MIN_TERRAIN_HEIGHT, MAX_TERRAIN_HEIGHT)

	var road_distance: float = _distance_to_route(local, route)
	var road_blend: float = _feather_blend(road_distance, ROAD_HALF_WIDTH, ROAD_FEATHER)
	if road_blend > 0.0:
		height = lerp(height, 0.08, road_blend * 0.985)

	for slot in reserved_slots:
		var center: Vector2 = slot.get("center", Vector2.ZERO)
		var radius: float = max(1.0, float(slot.get("radius", 8.0)))
		var feather: float = max(2.0, float(slot.get("feather", 6.0)))
		var target_height: float = clamp(float(slot.get("height", 0.08)), MIN_TERRAIN_HEIGHT, 2.0)
		var blend: float = _feather_blend(local.distance_to(center), radius, feather)
		if blend > 0.0:
			height = lerp(height, target_height, blend)
	return clamp(height, MIN_TERRAIN_HEIGHT, MAX_TERRAIN_HEIGHT)

func _primary_route_2d(region_id: String, reserved_slots: Array[Dictionary]) -> Array[Vector2]:
	var region: Dictionary = REGION_CATALOG.get_region(region_id)
	var entry: Vector2 = region.get("entry", Vector2(0, 50))
	var exit_point: Vector2 = region.get("exit", Vector2(0, -50))
	var anchor: Vector2 = entry.lerp(exit_point, 0.48)
	for slot in reserved_slots:
		if str(slot.get("id", "")) == "player_spawn":
			anchor = slot.get("center", anchor)
			break
	var anchors: Array[Vector2] = [entry, anchor, exit_point]
	var result: Array[Vector2] = []
	var region_radius: float = max(24.0, float(region.get("radius", 62.0)))
	for segment_index in range(anchors.size() - 1):
		var start: Vector2 = anchors[segment_index]
		var finish: Vector2 = anchors[segment_index + 1]
		var direction: Vector2 = (finish - start).normalized()
		var side := Vector2(-direction.y, direction.x)
		var rng := RandomNumberGenerator.new()
		rng.seed = generation_seed(region_id, "primary_route_segment_%d" % segment_index)
		var bend: float = rng.randf_range(-region_radius * 0.22, region_radius * 0.22)
		var secondary: float = rng.randf_range(-region_radius * 0.07, region_radius * 0.07)
		var steps: int = max(6, int(ceil(start.distance_to(finish) / 4.0)))
		for step_index in range(steps + 1):
			if segment_index > 0 and step_index == 0:
				continue
			var t: float = float(step_index) / float(steps)
			var point: Vector2 = start.lerp(finish, t)
			point += side * (sin(t * PI) * bend + sin(t * TAU) * secondary)
			var max_length: float = region_radius * 1.12
			if point.length() > max_length:
				point = point.normalized() * max_length
			result.append(point)
	return result

func _distance_to_route(point: Vector2, route: Array[Vector2]) -> float:
	if route.is_empty():
		return INF
	var best: float = INF
	for route_point in route:
		best = min(best, point.distance_to(route_point))
	return best

func _feather_blend(distance: float, radius: float, feather: float) -> float:
	if distance <= radius:
		return 1.0
	if distance >= radius + feather:
		return 0.0
	var t: float = 1.0 - (distance - radius) / feather
	return t * t * (3.0 - 2.0 * t)

func _fallback_chunk_data(region_id: String, preferred_biome: String, chunk_coord: Vector2i, error_code: String) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var collision_faces := PackedVector3Array()
	var origin_x: float = float(chunk_coord.x) * CHUNK_SIZE
	var origin_z: float = float(chunk_coord.y) * CHUNK_SIZE
	var step: float = CHUNK_SIZE / float(CELLS_PER_SIDE)
	var biome: Dictionary = BIOME_CATALOG.get_biome(preferred_biome)
	var safe_color: Color = biome.get("ground_color", Color("4f7545"))
	for z_index in range(VERTICES_PER_SIDE):
		for x_index in range(VERTICES_PER_SIDE):
			vertices.append(Vector3(origin_x + float(x_index) * step, 0.08, origin_z + float(z_index) * step))
			normals.append(Vector3.UP)
			colors.append(safe_color)
	for z_index in range(CELLS_PER_SIDE):
		for x_index in range(CELLS_PER_SIDE):
			var row: int = z_index * VERTICES_PER_SIDE
			var next_row: int = (z_index + 1) * VERTICES_PER_SIDE
			var a: int = row + x_index
			var b: int = a + 1
			var c: int = next_row + x_index
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	for index in indices:
		collision_faces.append(vertices[index])
	var data := {
		"format_version": FORMAT_VERSION,
		"world_seed": world_seed,
		"profile_signature": str(profile.get("signature", "")),
		"region_id": region_id,
		"chunk_coord": chunk_coord,
		"chunk_id": "%s:%d:%d" % [region_id, chunk_coord.x, chunk_coord.y],
		"generation_seed": generation_seed(region_id, "fallback_terrain", chunk_coord),
		"data_signature": "fallback:%d:%s:%d:%d" % [world_seed, region_id, chunk_coord.x, chunk_coord.y],
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"collision_faces": collision_faces,
		"fallback": true,
		"validation_error": error_code
	}
	data["validation"] = VALIDATOR.validate_chunk(data, VERTICES_PER_SIDE * VERTICES_PER_SIDE)
	return data

func _chunk_signature(region_id: String, chunk_coord: Vector2i, vertices: PackedVector3Array) -> String:
	var parts: Array[String] = [
		str(FORMAT_VERSION),
		str(world_seed),
		region_id,
		str(chunk_coord.x),
		str(chunk_coord.y),
		str(profile.get("signature", ""))
	]
	for index in range(0, vertices.size(), 8):
		parts.append("%.4f" % vertices[index].y)
	return str("|".join(parts).hash())

func _configure_noise(noise: FastNoiseLite, scope: String, frequency: float, octaves: int, gain: float) -> void:
	noise.seed = generation_seed("world", scope)
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.0

func _sanitize_seed(seed_value: int) -> int:
	var sanitized: int = int(seed_value & 0x7fffffff)
	return sanitized if sanitized > 0 else DEFAULT_WORLD_SEED

func _ensure_configured() -> void:
	if profile.is_empty() or biome_map == null:
		configure(world_seed)
