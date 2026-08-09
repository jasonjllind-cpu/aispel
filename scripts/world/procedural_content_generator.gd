extends RefCounted
class_name ProceduralContentGenerator

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")
const WORLD_GENERATOR_SCRIPT := preload("res://scripts/world/world_generator.gd")

var world_seed: int = 8242601
var terrain_generator: RefCounted

func configure(seed_value: int) -> void:
	world_seed = seed_value if seed_value != 0 else 8242601
	terrain_generator = WORLD_GENERATOR_SCRIPT.new()
	terrain_generator.call("configure", world_seed)

func generate_region_content(region_id: String) -> Dictionary:
	if terrain_generator == null:
		configure(world_seed)
	var region: Dictionary = REGION_CATALOG.get_region(region_id)
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var biome: Dictionary = BIOME_CATALOG.get_biome(biome_id)
	var center: Vector3 = region.get("center", Vector3.ZERO)
	var slots: Array[Dictionary] = REGION_CATALOG.get_slots(region_id)
	var road: Array[Vector3] = _generate_road(region_id, region, center, biome_id, slots)
	var pois: Array[Dictionary] = _generate_pois(region_id, region, center, biome_id, slots, road)
	var vegetation: Dictionary = _generate_vegetation(region_id, region, center, biome_id, biome, slots, road, pois)
	var encounters: Array[Dictionary] = _generate_encounters(region_id, center, biome_id, biome, slots, pois)
	var loot: Array[Dictionary] = _generate_loot(region_id, center, biome_id, slots, pois)
	return {
		"format_version": 1,
		"world_seed": world_seed,
		"region_id": region_id,
		"biome_id": biome_id,
		"road": road,
		"pois": pois,
		"trees": vegetation.get("trees", []),
		"rocks": vegetation.get("rocks", []),
		"encounters": encounters,
		"loot": loot
	}

func _generate_road(region_id: String, region: Dictionary, center: Vector3, biome_id: String, slots: Array[Dictionary]) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(region_id, "roads")
	var entry: Vector2 = region.get("entry", Vector2(0, 48))
	var exit_point: Vector2 = region.get("exit", Vector2(0, -48))
	var landmark: Vector2 = Vector2.ZERO
	if not slots.is_empty():
		landmark = slots[0].get("center", Vector2.ZERO)
	elif region_id == "starting_valley":
		landmark = Vector2(28, -58)
	var anchors: Array[Vector2] = [entry, landmark, exit_point]
	var points: Array[Vector3] = []
	for segment_index in range(anchors.size() - 1):
		var start: Vector2 = anchors[segment_index]
		var finish: Vector2 = anchors[segment_index + 1]
		var distance: float = start.distance_to(finish)
		var steps: int = max(2, int(ceil(distance / 5.0)))
		var curve_strength: float = rng.randf_range(-11.0, 11.0)
		var secondary_curve: float = rng.randf_range(-4.0, 4.0)
		for step_index in range(steps):
			if segment_index > 0 and step_index == 0:
				continue
			var t: float = float(step_index) / float(steps)
			var local: Vector2 = start.lerp(finish, t)
			var tangent: Vector2 = (finish - start).normalized()
			var side := Vector2(-tangent.y, tangent.x)
			var curve: float = sin(t * PI) * curve_strength + sin(t * TAU) * secondary_curve
			local += side * curve
			var y: float = _height(center, biome_id, local, slots)
			points.append(Vector3(local.x, y + 0.035, local.y))
	var final_y: float = _height(center, biome_id, exit_point, slots)
	points.append(Vector3(exit_point.x, final_y + 0.035, exit_point.y))
	return points

func _generate_pois(region_id: String, region: Dictionary, center: Vector3, biome_id: String, slots: Array[Dictionary], road: Array[Vector3]) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(region_id, "poi")
	var base_poi_count: int = int(region.get("poi_count", 3))
	var target_count: int = base_poi_count + rng.randi_range(0, 2)
	var region_radius: float = float(region.get("radius", 62.0))
	var placement_radius: float = min(region_radius - 12.0, 72.0 if region_id == "starting_valley" else 48.0)
	var result: Array[Dictionary] = []
	var attempts: int = 0
	while result.size() < target_count and attempts < target_count * 80:
		attempts += 1
		var candidate: Vector2 = _random_disk_position(rng, placement_radius)
		if _inside_reserved_slot(candidate, slots, 7.0):
			continue
		var road_distance: float = _distance_to_road(candidate, road)
		if road_distance < 9.0 or road_distance > 34.0:
			continue
		if _near_existing_poi(candidate, result, 22.0):
			continue
		var poi_index: int = result.size()
		var poi_type: String = _poi_type_for(biome_id, poi_index, rng)
		var y: float = _height(center, biome_id, candidate, slots)
		result.append({
			"id": "poi:%s:%d:%s" % [region_id, poi_index, poi_type],
			"type": poi_type,
			"display_name": _poi_display_name(poi_type),
			"position": Vector3(candidate.x, y, candidate.y),
			"rotation_y": rng.randf_range(-PI, PI)
		})
	return result

func _generate_vegetation(region_id: String, region: Dictionary, center: Vector3, biome_id: String, biome: Dictionary, slots: Array[Dictionary], road: Array[Vector3], pois: Array[Dictionary]) -> Dictionary:
	var tree_rng := RandomNumberGenerator.new()
	tree_rng.seed = _seed(region_id, "vegetation:trees")
	var rock_rng := RandomNumberGenerator.new()
	rock_rng.seed = _seed(region_id, "vegetation:rocks")
	var region_radius: float = float(region.get("radius", 62.0))
	var placement_radius: float = min(region_radius - 7.0, 78.0 if region_id == "starting_valley" else 51.0)
	var tree_density: float = float(biome.get("tree_density", 0.4))
	var rock_density: float = float(biome.get("rock_density", 0.2))
	var base_tree_target: float = 20.0 + tree_density * (55.0 if region_id == "starting_valley" else 70.0)
	var base_rock_target: float = 10.0 + rock_density * 35.0
	var tree_target: int = max(12, int(base_tree_target * tree_rng.randf_range(0.65, 1.55)))
	var rock_target: int = max(7, int(base_rock_target * rock_rng.randf_range(0.65, 1.55)))
	var trees: Array[Dictionary] = []
	var rocks: Array[Dictionary] = []
	var tree_points: Array[Vector2] = []

	var attempts: int = 0
	while trees.size() < tree_target and attempts < tree_target * 18:
		attempts += 1
		var local: Vector2 = _random_disk_position(tree_rng, placement_radius)
		if _inside_reserved_slot(local, slots, 3.5) or _distance_to_road(local, road) < 5.5 or _near_poi(local, pois, 8.0):
			continue
		if _near_vector2(local, tree_points, 2.8):
			continue
		var y: float = _height(center, biome_id, local, slots)
		var tree_index: int = trees.size()
		var scale_value: float = tree_rng.randf_range(0.72, 1.42)
		trees.append({
			"id": "vegetation:%s:tree:%d" % [region_id, tree_index],
			"position": Vector3(local.x, y, local.y),
			"scale": scale_value,
			"rotation_y": tree_rng.randf_range(-PI, PI),
			"dead": tree_rng.randf() < (0.34 if biome_id == "blackwood" or biome_id == "veilmoor" else 0.12)
		})
		tree_points.append(local)

	attempts = 0
	while rocks.size() < rock_target and attempts < rock_target * 20:
		attempts += 1
		var local: Vector2 = _random_disk_position(rock_rng, placement_radius)
		if _inside_reserved_slot(local, slots, 2.0) or _distance_to_road(local, road) < 3.5 or _near_poi(local, pois, 5.0):
			continue
		var y: float = _height(center, biome_id, local, slots)
		var rock_index: int = rocks.size()
		rocks.append({
			"id": "vegetation:%s:rock:%d" % [region_id, rock_index],
			"position": Vector3(local.x, y + 0.20, local.y),
			"scale": Vector3(rock_rng.randf_range(0.45, 1.25), rock_rng.randf_range(0.35, 0.95), rock_rng.randf_range(0.50, 1.35)),
			"rotation_y": rock_rng.randf_range(-PI, PI)
		})
	return {"trees": trees, "rocks": rocks}

func _generate_encounters(region_id: String, center: Vector3, biome_id: String, biome: Dictionary, slots: Array[Dictionary], pois: Array[Dictionary]) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(region_id, "encounters")
	var result: Array[Dictionary] = []
	var profile: String = str(biome.get("encounter_profile", "warden_patrol"))
	for i in range(pois.size()):
		var poi_pos: Vector3 = pois[i].get("position", Vector3.ZERO)
		var angle: float = rng.randf_range(-PI, PI)
		var distance: float = rng.randf_range(8.0, 13.0)
		var local := Vector2(poi_pos.x + cos(angle) * distance, poi_pos.z + sin(angle) * distance)
		if _inside_reserved_slot(local, slots, 2.0):
			local += Vector2(8, 0)
		var y: float = _height(center, biome_id, local, slots)
		result.append({
			"id": "enemy:generated:%s:%d" % [region_id, i],
			"profile": profile,
			"position": Vector3(local.x, y + 1.0, local.y)
		})
	return result

func _generate_loot(region_id: String, center: Vector3, biome_id: String, slots: Array[Dictionary], pois: Array[Dictionary]) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(region_id, "loot")
	var result: Array[Dictionary] = []
	var item_pool: Array[String] = ["Ancient Coin", "Moon Shard", "Ancient Coin", "Moon Shard"]
	for i in range(pois.size()):
		var poi: Dictionary = pois[i]
		var poi_pos: Vector3 = poi.get("position", Vector3.ZERO)
		var poi_type: String = str(poi.get("type", "minor_ruin"))
		var angle: float = rng.randf_range(-PI, PI)
		var distance: float = 3.2 if poi_type == "secret" else rng.randf_range(2.8, 5.5)
		var local := Vector2(poi_pos.x + cos(angle) * distance, poi_pos.z + sin(angle) * distance)
		var y: float = _height(center, biome_id, local, slots)
		var item_name: String = item_pool[rng.randi_range(0, item_pool.size() - 1)]
		var amount: int = 2 if poi_type == "secret" else 1
		result.append({
			"id": "loot:generated:%s:%d" % [region_id, i],
			"item_name": item_name,
			"amount": amount,
			"position": Vector3(local.x, y + 0.65, local.y),
			"secret": poi_type == "secret" or poi_type == "cave"
		})
	return result

func _height(center: Vector3, biome_id: String, local: Vector2, slots: Array[Dictionary]) -> float:
	return float(terrain_generator.call("sample_height_at", center, biome_id, local, slots))

func _seed(region_id: String, layer_id: String) -> int:
	return int(terrain_generator.call("generation_seed", region_id, layer_id, Vector2i.ZERO))

func _random_disk_position(rng: RandomNumberGenerator, radius: float) -> Vector2:
	var angle: float = rng.randf_range(-PI, PI)
	var distance: float = sqrt(rng.randf()) * radius
	return Vector2(cos(angle), sin(angle)) * distance

func _inside_reserved_slot(point: Vector2, slots: Array[Dictionary], margin: float) -> bool:
	for slot in slots:
		var center: Vector2 = slot.get("center", Vector2.ZERO)
		var radius: float = float(slot.get("radius", 8.0)) + margin
		if point.distance_to(center) <= radius:
			return true
	return false

func _distance_to_road(point: Vector2, road: Array[Vector3]) -> float:
	var best: float = INF
	for road_point in road:
		var distance: float = point.distance_to(Vector2(road_point.x, road_point.z))
		best = min(best, distance)
	return best

func _near_existing_poi(point: Vector2, pois: Array[Dictionary], distance_limit: float) -> bool:
	for poi in pois:
		var pos: Vector3 = poi.get("position", Vector3.ZERO)
		if point.distance_to(Vector2(pos.x, pos.z)) < distance_limit:
			return true
	return false

func _near_poi(point: Vector2, pois: Array[Dictionary], distance_limit: float) -> bool:
	return _near_existing_poi(point, pois, distance_limit)

func _near_vector2(point: Vector2, points: Array[Vector2], distance_limit: float) -> bool:
	for other in points:
		if point.distance_to(other) < distance_limit:
			return true
	return false

func _poi_type_for(biome_id: String, index: int, rng: RandomNumberGenerator) -> String:
	var options: Array[String]
	match biome_id:
		"blackwood":
			options = ["cave", "camp", "secret", "minor_ruin"]
		"veilmoor":
			options = ["minor_ruin", "secret", "cave", "grave_site"]
		"windscar_highlands":
			options = ["minor_ruin", "camp", "cave", "secret"]
		_:
			options = ["camp", "minor_ruin", "secret", "cave"]
	var offset: int = rng.randi_range(0, options.size() - 1)
	return options[(index + offset) % options.size()]

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
