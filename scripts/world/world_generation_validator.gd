extends RefCounted
class_name WorldGenerationValidator

const CHUNK_FORMAT_VERSION: int = 2
const CONTENT_FORMAT_VERSION: int = 2
const MAX_WORLD_HEIGHT: float = 24.0
const MIN_WORLD_HEIGHT: float = -2.0
const MAX_CONTENT_ITEMS: int = 512
const MIN_POI_SEPARATION: float = 12.0

static func validate_chunk(data: Dictionary, expected_vertex_count: int = -1) -> Dictionary:
	if int(data.get("format_version", 0)) != CHUNK_FORMAT_VERSION:
		return _error("unsupported_chunk_format")
	if str(data.get("chunk_id", "")).is_empty() or int(data.get("generation_seed", 0)) <= 0:
		return _error("missing_chunk_identity")

	var vertices_value: Variant = data.get("vertices", PackedVector3Array())
	var normals_value: Variant = data.get("normals", PackedVector3Array())
	var colors_value: Variant = data.get("colors", PackedColorArray())
	var indices_value: Variant = data.get("indices", PackedInt32Array())
	var collision_value: Variant = data.get("collision_faces", PackedVector3Array())
	if not vertices_value is PackedVector3Array or not normals_value is PackedVector3Array:
		return _error("invalid_vertex_arrays")
	if not colors_value is PackedColorArray or not indices_value is PackedInt32Array:
		return _error("invalid_surface_arrays")
	if not collision_value is PackedVector3Array:
		return _error("invalid_collision_array")

	var vertices: PackedVector3Array = vertices_value
	var normals: PackedVector3Array = normals_value
	var colors: PackedColorArray = colors_value
	var indices: PackedInt32Array = indices_value
	var collision_faces: PackedVector3Array = collision_value
	if vertices.is_empty() or indices.is_empty() or indices.size() % 3 != 0:
		return _error("empty_or_untriangulated_chunk")
	if expected_vertex_count > 0 and vertices.size() != expected_vertex_count:
		return _error("unexpected_vertex_count")
	if normals.size() != vertices.size() or colors.size() != vertices.size():
		return _error("surface_array_size_mismatch")
	if collision_faces.size() != indices.size():
		return _error("collision_index_size_mismatch")

	var min_height: float = INF
	var max_height: float = -INF
	for vertex in vertices:
		if not vertex.is_finite():
			return _error("non_finite_vertex")
		min_height = min(min_height, vertex.y)
		max_height = max(max_height, vertex.y)
	for normal in normals:
		if not normal.is_finite() or normal.length_squared() < 0.25:
			return _error("invalid_normal")
	for index in indices:
		if index < 0 or index >= vertices.size():
			return _error("index_out_of_bounds")
	if min_height < MIN_WORLD_HEIGHT or max_height > MAX_WORLD_HEIGHT:
		return _error("height_out_of_bounds")

	return {
		"ok": true,
		"vertex_count": vertices.size(),
		"triangle_count": indices.size() / 3,
		"min_height": min_height,
		"max_height": max_height
	}

static func validate_region_content(data: Dictionary, region_radius: float, reserved_slots: Array[Dictionary] = []) -> Dictionary:
	if int(data.get("format_version", 0)) != CONTENT_FORMAT_VERSION:
		return _error("unsupported_content_format")
	if int(data.get("world_seed", 0)) <= 0 or str(data.get("region_id", "")).is_empty():
		return _error("missing_content_identity")
	var road_value: Variant = data.get("road", [])
	var pois_value: Variant = data.get("pois", [])
	var trees_value: Variant = data.get("trees", [])
	var rocks_value: Variant = data.get("rocks", [])
	var encounters_value: Variant = data.get("encounters", [])
	var loot_value: Variant = data.get("loot", [])
	if not road_value is Array or not pois_value is Array or not trees_value is Array:
		return _error("invalid_primary_content_arrays")
	if not rocks_value is Array or not encounters_value is Array or not loot_value is Array:
		return _error("invalid_secondary_content_arrays")

	var road: Array = road_value
	var pois: Array = pois_value
	var trees: Array = trees_value
	var rocks: Array = rocks_value
	var encounters: Array = encounters_value
	var loot: Array = loot_value
	if road.size() < 8:
		return _error("road_too_short")
	if pois.is_empty():
		return _error("missing_pois")
	if trees.size() + rocks.size() + encounters.size() + loot.size() > MAX_CONTENT_ITEMS:
		return _error("content_budget_exceeded")

	var max_radius: float = max(16.0, region_radius * 1.35)
	for point in road:
		if not point is Vector3 or not (point as Vector3).is_finite():
			return _error("invalid_road_point")
		if Vector2((point as Vector3).x, (point as Vector3).z).length() > max_radius:
			return _error("road_out_of_bounds")

	var ids: Dictionary = {}
	var poi_positions: Array[Vector2] = []
	for value in pois:
		if not value is Dictionary:
			return _error("invalid_poi_record")
		var poi: Dictionary = value
		var stable_id: String = str(poi.get("id", ""))
		var position_value: Variant = poi.get("position", null)
		if stable_id.is_empty() or ids.has(stable_id) or not position_value is Vector3:
			return _error("invalid_or_duplicate_poi")
		var position: Vector3 = position_value
		if not position.is_finite() or Vector2(position.x, position.z).length() > max_radius:
			return _error("poi_out_of_bounds")
		for other in poi_positions:
			if Vector2(position.x, position.z).distance_to(other) < MIN_POI_SEPARATION:
				return _error("poi_overlap")
		if _inside_reserved_slot(Vector2(position.x, position.z), reserved_slots, 4.0):
			return _error("poi_inside_reserved_slot")
		ids[stable_id] = true
		poi_positions.append(Vector2(position.x, position.z))

	for collection in [trees, rocks, encounters, loot]:
		for value in collection:
			if not value is Dictionary:
				return _error("invalid_content_record")
			var record: Dictionary = value
			var stable_id: String = str(record.get("id", ""))
			var position_value: Variant = record.get("position", null)
			if stable_id.is_empty() or ids.has(stable_id) or not position_value is Vector3:
				return _error("invalid_or_duplicate_content")
			var position: Vector3 = position_value
			if not position.is_finite() or Vector2(position.x, position.z).length() > max_radius:
				return _error("content_out_of_bounds")
			ids[stable_id] = true

	return {
		"ok": true,
		"road_points": road.size(),
		"poi_count": pois.size(),
		"tree_count": trees.size(),
		"rock_count": rocks.size(),
		"encounter_count": encounters.size(),
		"loot_count": loot.size()
	}

static func _inside_reserved_slot(point: Vector2, slots: Array[Dictionary], margin: float) -> bool:
	for slot in slots:
		var center: Vector2 = slot.get("center", Vector2.ZERO)
		var radius: float = max(0.0, float(slot.get("radius", 0.0))) + margin
		if point.distance_to(center) <= radius:
			return true
	return false

static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
