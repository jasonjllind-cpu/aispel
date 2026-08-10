extends RefCounted
class_name ProceduralContentGenerator

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")
const WORLD_GENERATOR_SCRIPT := preload("res://scripts/world/world_generator.gd")
const VALIDATOR := preload("res://scripts/world/world_generation_validator.gd")

const FORMAT_VERSION: int = 3
const DEFAULT_WORLD_SEED: int = 8242601
const MAX_POIS: int = 6
const MAX_TREES: int = 140
const MAX_ROCKS: int = 70
const POI_MIN_SEPARATION: float = 18.0

var world_seed: int = DEFAULT_WORLD_SEED
var terrain_generator: RefCounted

func configure(seed_value: int) -> void:
	world_seed = int(seed_value & 0x7fffffff)
	if world_seed <= 0:
		world_seed = DEFAULT_WORLD_SEED
	terrain_generator = WORLD_GENERATOR_SCRIPT.new()
	terrain_generator.call("configure", world_seed)

func generate_region_content(region_id: String) -> Dictionary:
	_ensure_configured()
	var region: Dictionary = REGION_CATALOG.get_region(region_id)
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var biome: Dictionary = BIOME_CATALOG.get_biome(biome_id)
	var center: Vector3 = region.get("center", Vector3.ZERO)
	var slots: Array[Dictionary] = REGION_CATALOG.get_slots(region_id)
	var radius: float = max(28.0, float(region.get("radius", 62.0)))
	var road_value: Variant = terrain_generator.call("primary_route_points", region_id, center, biome_id, slots)
	var road: Array[Vector3] = []
	if road_value is Array:
		for point in road_value as Array:
			if point is Vector3:
				road.append(point)
	var pois: Array[Dictionary] = _generate_pois(region_id, region, center, biome_id, slots, road)
	var vegetation: Dictionary = _generate_vegetation(region_id, region, center, biome_id, biome, slots, road, pois)
	var trees: Array[Dictionary] = _typed_dictionary_array(vegetation.get("trees", []))
	var rocks: Array[Dictionary] = _typed_dictionary_array(vegetation.get("rocks", []))
	var encounters: Array[Dictionary] = _generate_encounters(region_id, center, biome_id, biome, slots, pois)
	var loot: Array[Dictionary] = _generate_loot(region_id, center, biome_id, slots, pois)
	var data := {
		"format_version": FORMAT_VERSION,
		"world_seed": world_seed,
		"region_id": region_id,
		"biome_id": biome_id,
		"content_signature": _content_signature(region_id, road, pois, trees, rocks),
		"road": road,
		"pois": pois,
		"trees": trees,
		"rocks": rocks,
		"encounters": encounters,
		"loot": loot,
		"fallback": false
	}
	var validation: Dictionary = VALIDATOR.validate_region_content(data, radius, slots)
	if validation.get("ok", false) != true:
		return _fallback_region_content(region_id, region, center, biome_id, slots, road, str(validation.get("error", "unknown")))
	data["validation"] = validation
	return data

func validate_region_content(data: Dictionary) -> Dictionary:
	var region_id: String = str(data.get("region_id", "starting_valley"))
	var region: Dictionary = REGION_CATALOG.get_region(region_id)
	return VALIDATOR.validate_region_content(data, float(region.get("radius", 62.0)), REGION_CATALOG.get_slots(region_id))

func _generate_pois(region_id: String, region: Dictionary, center: Vector3, biome_id: String, slots: Array[Dictionary], road: Array[Vector3]) -> Array[Dictionary]:
	var rng := _rng(region_id, "poi_layout")
	var base_count: int = max(2, int(region.get("poi_count", 3)))
	var target_count: int = clampi(base_count + rng.randi_range(1, 3), 3, MAX_POIS)
	var region_radius: float = float(region.get("radius", 62.0))
	var placement_radius: float = min(region_radius - 10.0, 78.0 if region_id == "starting_valley" else 52.0)
	var result: Array[Dictionary] = []
	var attempts: int = 0
	var max_attempts: int = target_count * 120
	while result.size() < target_count and attempts < max_attempts:
		attempts += 1
		var candidate: Vector2 = _random_disk_position(rng, placement_radius)
		if not _is_valid_poi_position(candidate, slots, road, result):
			continue
		_append_poi(result, region_id, biome_id, center, slots, candidate, rng)
	if result.size() < target_count:
		_fill_pois_from_fallback_ring(result, target_count, region_id, biome_id, center, slots, road, placement_radius, rng)
	return result

func _append_poi(result: Array[Dictionary], region_id: String, biome_id: String, center: Vector3, slots: Array[Dictionary], candidate: Vector2, rng: RandomNumberGenerator) -> void:
	var poi_index: int = result.size()
	var poi_type: String = _poi_type_for(biome_id, poi_index, rng)
	var height: float = _height(region_id, center, biome_id, candidate, slots)
	result.append({
		"id": "poi:%s:%d:%s" % [region_id, poi_index, poi_type],
		"type": poi_type,
		"display_name": _poi_display_name(poi_type),
		"position": Vector3(candidate.x, height, candidate.y),
		"rotation_y": rng.randf_range(-PI, PI)
	})

func _fill_pois_from_fallback_ring(result: Array[Dictionary], target_count: int, region_id: String, biome_id: String, center: Vector3, slots: Array[Dictionary], road: Array[Vector3], placement_radius: float, rng: RandomNumberGenerator) -> void:
	var phase: float = rng.randf_range(-PI, PI)
	for ring_index in range(36):
		if result.size() >= target_count:
			return
		var angle: float = phase + TAU * float(ring_index) / 36.0
		var radius: float = placement_radius * (0.48 + 0.38 * float((ring_index % 3)) / 2.0)
		var candidate := Vector2(cos(angle), sin(angle)) * radius
		if _is_valid_poi_position(candidate, slots, road, result):
			_append_poi(result, region_id, biome_id, center, slots, candidate, rng)
	if result.is_empty():
		var emergency: Vector2 = _emergency_position(slots, placement_radius)
		_append_poi(result, region_id, biome_id, center, slots, emergency, rng)

func _is_valid_poi_position(candidate: Vector2, slots: Array[Dictionary], road: Array[Vector3], existing: Array[Dictionary]) -> bool:
	if _inside_reserved_slot(candidate, slots, 6.0):
		return false
	var road_distance: float = _distance_to_road(candidate, road)
	if road_distance < 8.0 or road_distance > 38.0:
		return false
	for poi in existing:
		var position: Vector3 = poi.get("position", Vector3.ZERO)
		if candidate.distance_to(Vector2(position.x, position.z)) < POI_MIN_SEPARATION:
			return false
	return true

func _generate_vegetation(region_id: String, region: Dictionary, center: Vector3, biome_id: String, biome: Dictionary, slots: Array[Dictionary], road: Array[Vector3], pois: Array[Dictionary]) -> Dictionary:
	var tree_rng := _rng(region_id, "vegetation_trees")
	var rock_rng := _rng(region_id, "vegetation_rocks")
	var region_radius: float = float(region.get("radius", 62.0))
	var placement_radius: float = min(region_radius - 6.0, 82.0 if region_id == "starting_valley" else 53.0)
	var tree_density: float = clamp(float(biome.get("tree_density", 0.4)), 0.05, 1.0)
	var rock_density: float = clamp(float(biome.get("rock_density", 0.2)), 0.05, 1.0)
	var tree_target: int = clampi(int((28.0 + tree_density * 78.0) * tree_rng.randf_range(0.68, 1.35)), 20, MAX_TREES)
	var rock_target: int = clampi(int((12.0 + rock_density * 48.0) * rock_rng.randf_range(0.72, 1.32)), 8, MAX_ROCKS)
	var trees: Array[Dictionary] = []
	var rocks: Array[Dictionary] = []
	var tree_points: Array[Vector2] = []

	var attempts: int = 0
	while trees.size() < tree_target and attempts < tree_target * 28:
		attempts += 1
		var local: Vector2 = _random_disk_position(tree_rng, placement_radius)
		if _inside_reserved_slot(local, slots, 3.5) or _distance_to_road(local, road) < 6.0 or _near_pois(local, pois, 8.5):
			continue
		if _near_points(local, tree_points, 2.9):
			continue
		var index: int = trees.size()
		trees.append({
			"id": "vegetation:%s:tree:%d" % [region_id, index],
			"position": Vector3(local.x, _height(region_id, center, biome_id, local, slots), local.y),
			"scale": tree_rng.randf_range(0.70, 1.48),
			"rotation_y": tree_rng.randf_range(-PI, PI),
			"dead": tree_rng.randf() < (0.34 if biome_id == "blackwood" or biome_id == "veilmoor" else 0.10)
		})
		tree_points.append(local)

	attempts = 0
	while rocks.size() < rock_target and attempts < rock_target * 25:
		attempts += 1
		var local: Vector2 = _random_disk_position(rock_rng, placement_radius)
		if _inside_reserved_slot(local, slots, 2.0) or _distance_to_road(local, road) < 3.8 or _near_pois(local, pois, 5.0):
			continue
		var index: int = rocks.size()
		rocks.append({
			"id": "vegetation:%s:rock:%d" % [region_id, index],
			"position": Vector3(local.x, _height(region_id, center, biome_id, local, slots) + 0.18, local.y),
			"scale": Vector3(rock_rng.randf_range(0.45, 1.35), rock_rng.randf_range(0.32, 1.0), rock_rng.randf_range(0.48, 1.42)),
			"rotation_y": rock_rng.randf_range(-PI, PI)
		})
	return {"trees": trees, "rocks": rocks}

func _generate_encounters(region_id: String, center: Vector3, biome_id: String, biome: Dictionary, slots: Array[Dictionary], pois: Array[Dictionary]) -> Array[Dictionary]:
	var rng := _rng(region_id, "encounters")
	var result: Array[Dictionary] = []
	var profile_id: String = str(biome.get("encounter_profile", "warden_patrol"))
	for i in range(pois.size()):
		var poi_position: Vector3 = pois[i].get("position", Vector3.ZERO)
		var angle: float = rng.randf_range(-PI, PI)
		var distance: float = rng.randf_range(9.0, 14.0)
		var local := Vector2(poi_position.x + cos(angle) * distance, poi_position.z + sin(angle) * distance)
		if _inside_reserved_slot(local, slots, 2.0):
			local += Vector2(cos(angle + PI * 0.5), sin(angle + PI * 0.5)) * 9.0
		result.append({
			"id": "enemy:generated:%s:%d" % [region_id, i],
			"profile": profile_id,
			"position": Vector3(local.x, _height(region_id, center, biome_id, local, slots) + 1.0, local.y)
		})
	return result

func _generate_loot(region_id: String, center: Vector3, biome_id: String, slots: Array[Dictionary], pois: Array[Dictionary]) -> Array[Dictionary]:
	var rng := _rng(region_id, "loot")
	var result: Array[Dictionary] = []
	var item_pool: Array[String] = ["Ancient Coin", "Moon Shard", "Ancient Coin", "Moon Shard"]
	for i in range(pois.size()):
		var poi: Dictionary = pois[i]
		var poi_position: Vector3 = poi.get("position", Vector3.ZERO)
		var poi_type: String = str(poi.get("type", "minor_ruin"))
		var angle: float = rng.randf_range(-PI, PI)
		var distance: float = 3.0 if poi_type == "secret" else rng.randf_range(2.8, 5.4)
		var local := Vector2(poi_position.x + cos(angle) * distance, poi_position.z + sin(angle) * distance)
		result.append({
			"id": "loot:generated:%s:%d" % [region_id, i],
			"item_name": item_pool[rng.randi_range(0, item_pool.size() - 1)],
			"amount": 2 if poi_type == "secret" else 1,
			"position": Vector3(local.x, _height(region_id, center, biome_id, local, slots) + 0.65, local.y),
			"secret": poi_type == "secret" or poi_type == "cave"
		})
	return result

func _fallback_region_content(region_id: String, region: Dictionary, center: Vector3, biome_id: String, slots: Array[Dictionary], road: Array[Vector3], error_code: String) -> Dictionary:
	var safe_road: Array[Vector3] = road
	if safe_road.size() < 8:
		var road_value: Variant = terrain_generator.call("primary_route_points", region_id, center, biome_id, slots)
		safe_road = []
		if road_value is Array:
			for point in road_value as Array:
				if point is Vector3:
					safe_road.append(point)
	var rng := _rng(region_id, "fallback")
	var placement_radius: float = max(24.0, float(region.get("radius", 62.0)) * 0.62)
	var local: Vector2 = _emergency_position(slots, placement_radius)
	var poi_type: String = "camp"
	var pois: Array[Dictionary] = [{
		"id": "poi:%s:0:%s" % [region_id, poi_type],
		"type": poi_type,
		"display_name": _poi_display_name(poi_type),
		"position": Vector3(local.x, _height(region_id, center, biome_id, local, slots), local.y),
		"rotation_y": rng.randf_range(-PI, PI)
	}]
	var data := {
		"format_version": FORMAT_VERSION,
		"world_seed": world_seed,
		"region_id": region_id,
		"biome_id": biome_id,
		"content_signature": "fallback:%d:%s" % [world_seed, region_id],
		"road": safe_road,
		"pois": pois,
		"trees": [],
		"rocks": [],
		"encounters": [],
		"loot": [],
		"fallback": true,
		"validation_error": error_code
	}
	data["validation"] = VALIDATOR.validate_region_content(data, float(region.get("radius", 62.0)), slots)
	return data

func _height(region_id: String, center: Vector3, biome_id: String, local: Vector2, slots: Array[Dictionary]) -> float:
	return float(terrain_generator.call("sample_height_at", center, biome_id, local, slots, region_id))

func _rng(region_id: String, layer_id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(terrain_generator.call("generation_seed", region_id, layer_id, Vector2i.ZERO))
	return rng

func _random_disk_position(rng: RandomNumberGenerator, radius: float) -> Vector2:
	var angle: float = rng.randf_range(-PI, PI)
	var distance: float = sqrt(rng.randf()) * radius
	return Vector2(cos(angle), sin(angle)) * distance

func _inside_reserved_slot(point: Vector2, slots: Array[Dictionary], margin: float) -> bool:
	for slot in slots:
		var center: Vector2 = slot.get("center", Vector2.ZERO)
		var radius: float = max(0.0, float(slot.get("radius", 0.0))) + margin
		if point.distance_to(center) <= radius:
			return true
	return false

func _distance_to_road(point: Vector2, road: Array[Vector3]) -> float:
	var best: float = INF
	for road_point in road:
		best = min(best, point.distance_to(Vector2(road_point.x, road_point.z)))
	return best

func _near_pois(point: Vector2, pois: Array[Dictionary], limit: float) -> bool:
	for poi in pois:
		var position: Vector3 = poi.get("position", Vector3.ZERO)
		if point.distance_to(Vector2(position.x, position.z)) < limit:
			return true
	return false

func _near_points(point: Vector2, points: Array[Vector2], limit: float) -> bool:
	for other in points:
		if point.distance_to(other) < limit:
			return true
	return false

func _emergency_position(slots: Array[Dictionary], radius: float) -> Vector2:
	for index in range(24):
		var angle: float = TAU * float(index) / 24.0
		var candidate := Vector2(cos(angle), sin(angle)) * radius * 0.72
		if not _inside_reserved_slot(candidate, slots, 4.0):
			return candidate
	return Vector2(radius * 0.72, 0)

func _poi_type_for(biome_id: String, index: int, rng: RandomNumberGenerator) -> String:
	var options: Array[String]
	match biome_id:
		"blackwood":
			options = ["cave", "camp", "secret", "minor_ruin"]
		"veilmoor":
			options = ["grave_site", "secret", "cave", "minor_ruin"]
		"windscar_highlands":
			options = ["minor_ruin", "camp", "cave", "secret"]
		_:
			options = ["camp", "minor_ruin", "secret", "cave"]
	return options[(index + rng.randi_range(0, options.size() - 1)) % options.size()]

func _poi_display_name(poi_type: String) -> String:
	match poi_type:
		"camp":
			return "Lost Camp"
		"cave":
			return "Hollow Cave"
		"secret":
			return "Moon-marked Hollow"
		"grave_site":
			return "Forgotten Graves"
		_:
			return "Forgotten Stones"

func _content_signature(region_id: String, road: Array[Vector3], pois: Array[Dictionary], trees: Array[Dictionary], rocks: Array[Dictionary]) -> String:
	var parts: Array[String] = [str(FORMAT_VERSION), str(world_seed), region_id, str(road.size()), str(pois.size()), str(trees.size()), str(rocks.size())]
	for index in range(0, road.size(), 5):
		parts.append("%.2f,%.2f" % [road[index].x, road[index].z])
	for poi in pois:
		var position: Vector3 = poi.get("position", Vector3.ZERO)
		parts.append("%s:%.2f,%.2f" % [str(poi.get("type", "")), position.x, position.z])
	return str("|".join(parts).hash())

func _typed_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item in value as Array:
			if item is Dictionary:
				result.append(item as Dictionary)
	return result

func _ensure_configured() -> void:
	if terrain_generator == null:
		configure(world_seed)
