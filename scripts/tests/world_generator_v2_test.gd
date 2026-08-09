extends SceneTree

const WORLD_GENERATOR_SCRIPT := preload("res://scripts/world/world_generator.gd")
const CONTENT_GENERATOR_SCRIPT := preload("res://scripts/world/procedural_content_generator.gd")
const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const JOB_QUEUE_SCRIPT := preload("res://scripts/world/generation_job_queue.gd")
const PROCEDURAL_EXPLORATION_SCRIPT := preload("res://scripts/world/procedural_exploration_system.gd")
const LEGACY_EXPLORATION_RUNTIME := preload("res://scripts/exploration_runtime.gd")
const WORLD_RUNTIME_SCRIPT := preload("res://scripts/world_runtime.gd")

const TEST_SEEDS: Array[int] = [1001, 40777, 243840798, 91082601, 2147483000]
const TEST_CHUNKS: Array[Vector2i] = [
	Vector2i(-2, -1),
	Vector2i(0, 0),
	Vector2i(1, -2),
	Vector2i(2, 1)
]
const SAMPLE_POINTS: Array[Vector2] = [
	# Spawn-visible samples make the test fail if only the distant world changes.
	Vector2(-28, 46),
	Vector2(28, 46),
	Vector2(-22, 30),
	Vector2(22, 30),
	Vector2(-24, 8),
	Vector2(24, 8),
	Vector2(-32, -8),
	Vector2(32, -8),
	Vector2(-78, 68),
	Vector2(-72, 18),
	Vector2(-54, 54),
	Vector2(-44, -12),
	Vector2(-22, 72),
	Vector2(18, 68),
	Vector2(42, 20),
	Vector2(52, -2),
	Vector2(58, -70),
	Vector2(82, 14)
]
const EPSILON: float = 0.00001

var executed_jobs: int = 0

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	if not _test_seed_determinism_and_difference():
		return
	if not _test_chunk_seams_and_safe_slots():
		return
	if not _test_spawn_grade_and_runtime_alignment():
		return
	if not _test_road_ribbon_surface():
		return
	if not _test_legacy_overlay_disabled():
		return
	if not _test_validator_rejections():
		return
	if not _test_extreme_seed_sanitization():
		return
	if not _test_job_queue_cancellation():
		return
	print("WORLD_GENERATOR_V3_OK seeds=%d chunks=%d deterministic=true visually_distinct=true legacy_overlay=false" % [
		TEST_SEEDS.size(),
		TEST_CHUNKS.size()
	])
	quit(0)

func _test_seed_determinism_and_difference() -> bool:
	var geometry_fingerprints: Dictionary = {}
	var reference_heights := PackedFloat32Array()
	var reference_route: Array[Vector3] = []
	var reference_content: Dictionary = {}
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var center: Vector3 = region.get("center", Vector3.ZERO)
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var slots: Array[Dictionary] = REGION_CATALOG.get_slots("starting_valley")

	for seed_index in range(TEST_SEEDS.size()):
		var seed_value: int = TEST_SEEDS[seed_index]
		var generator_a: RefCounted = WORLD_GENERATOR_SCRIPT.new()
		var generator_b: RefCounted = WORLD_GENERATOR_SCRIPT.new()
		generator_a.call("configure", seed_value)
		generator_b.call("configure", seed_value)
		var profile_a: Dictionary = generator_a.call("generation_profile")
		var profile_b: Dictionary = generator_b.call("generation_profile")
		if profile_a != profile_b:
			return _fail("Terrain profile changed between identical seed runs: %d" % seed_value)
		if int(profile_a.get("format_version", 0)) != 3 or str(profile_a.get("terrain_style", "")).is_empty():
			return _fail("Seed %d did not produce a named v3 visual terrain style" % seed_value)

		for coord in TEST_CHUNKS:
			var chunk_a: Dictionary = generator_a.call("generate_chunk_data", "starting_valley", biome_id, center, coord, slots)
			var chunk_b: Dictionary = generator_b.call("generate_chunk_data", "starting_valley", biome_id, center, coord, slots)
			if not _valid_nonfallback_chunk(generator_a, chunk_a):
				return _fail("Seed %d produced an invalid or fallback chunk at %s" % [seed_value, coord])
			if str(chunk_a.get("data_signature", "")) != str(chunk_b.get("data_signature", "")):
				return _fail("Chunk signature was not deterministic for seed %d at %s" % [seed_value, coord])
			if not _same_chunk_geometry(chunk_a, chunk_b):
				return _fail("Chunk geometry was not deterministic for seed %d at %s" % [seed_value, coord])

		var heights := PackedFloat32Array()
		for point in SAMPLE_POINTS:
			var height_a: float = float(generator_a.call("sample_height_at", center, biome_id, point, slots, "starting_valley"))
			var height_b: float = float(generator_b.call("sample_height_at", center, biome_id, point, slots, "starting_valley"))
			if not is_equal_approx(height_a, height_b):
				return _fail("Height sampling was not deterministic for seed %d" % seed_value)
			heights.append(height_a)
		if _height_range(heights) < 0.75:
			return _fail("Seed %d generated an implausibly flat terrain profile" % seed_value)

		var route_a: Array[Vector3] = generator_a.call("primary_route_points", "starting_valley", center, biome_id, slots)
		var route_b: Array[Vector3] = generator_b.call("primary_route_points", "starting_valley", center, biome_id, slots)
		if not _same_vector3_array(route_a, route_b):
			return _fail("Primary route was not deterministic for seed %d" % seed_value)
		if not _valid_route(route_a, generator_a, center, biome_id, slots):
			return _fail("Primary route invariants failed for seed %d" % seed_value)

		var content_a_generator: RefCounted = CONTENT_GENERATOR_SCRIPT.new()
		var content_b_generator: RefCounted = CONTENT_GENERATOR_SCRIPT.new()
		content_a_generator.call("configure", seed_value)
		content_b_generator.call("configure", seed_value)
		var content_a: Dictionary = content_a_generator.call("generate_region_content", "starting_valley")
		var content_b: Dictionary = content_b_generator.call("generate_region_content", "starting_valley")
		if not _valid_nonfallback_content(content_a_generator, content_a):
			return _fail("Seed %d produced invalid or fallback exploration content" % seed_value)
		if str(content_a.get("content_signature", "")) != str(content_b.get("content_signature", "")):
			return _fail("Content signature was not deterministic for seed %d" % seed_value)
		if not _same_content_geometry(content_a, content_b):
			return _fail("Content geometry was not deterministic for seed %d" % seed_value)

		var fingerprint: String = _geometry_fingerprint(heights, route_a, content_a)
		if geometry_fingerprints.has(fingerprint):
			return _fail("Two different seeds produced the same actual world geometry")
		geometry_fingerprints[fingerprint] = seed_value

		if seed_index == 0:
			reference_heights = heights
			reference_route = route_a
			reference_content = content_a
		else:
			if _height_delta(reference_heights, heights) < 4.0:
				return _fail("Seed %d did not materially change terrain heights" % seed_value)
			if not _route_differs(reference_route, route_a, 0.35):
				return _fail("Seed %d did not materially change the road layout" % seed_value)
			if not _content_layout_differs(reference_content, content_a, 0.35):
				return _fail("Seed %d did not materially change POI/content placement" % seed_value)
	return true

func _test_chunk_seams_and_safe_slots() -> bool:
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var center: Vector3 = region.get("center", Vector3.ZERO)
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var slots: Array[Dictionary] = REGION_CATALOG.get_slots("starting_valley")
	for seed_value in TEST_SEEDS:
		var generator: RefCounted = WORLD_GENERATOR_SCRIPT.new()
		generator.call("configure", seed_value)
		var left: Dictionary = generator.call("generate_chunk_data", "starting_valley", biome_id, center, Vector2i(0, 0), slots)
		var right: Dictionary = generator.call("generate_chunk_data", "starting_valley", biome_id, center, Vector2i(1, 0), slots)
		if not _matching_x_seam(left, right):
			return _fail("Adjacent chunks had a visible/collision seam for seed %d" % seed_value)
		for slot in slots:
			var slot_center: Vector2 = slot.get("center", Vector2.ZERO)
			var actual_height: float = float(generator.call("sample_height_at", center, biome_id, slot_center, slots, "starting_valley"))
			var target_height: float
			if str(slot.get("height_mode", "absolute")) == "terrain":
				target_height = float(generator.call("resolved_reserved_slot_height", center, biome_id, slot))
			else:
				target_height = max(0.02, float(slot.get("height", 0.08)))
			if abs(actual_height - target_height) > 0.025:
				return _fail("Reserved slot %s was not safely flattened for seed %d" % [str(slot.get("id", "")), seed_value])
			var radius: float = max(1.0, float(slot.get("radius", 6.0)))
			for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				var inner_point: Vector2 = slot_center + direction * radius * 0.75
				var inner_height: float = float(generator.call("sample_height_at", center, biome_id, inner_point, slots, "starting_valley"))
				if abs(inner_height - target_height) > 0.025:
					return _fail("Reserved slot %s was not flat across its safe footprint for seed %d" % [str(slot.get("id", "")), seed_value])
	return true


func _test_spawn_grade_and_runtime_alignment() -> bool:
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var center: Vector3 = region.get("center", Vector3.ZERO)
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var slots: Array[Dictionary] = REGION_CATALOG.get_slots("starting_valley")
	var spawn_local := Vector2(0, 24)
	for slot in slots:
		if str(slot.get("id", "")) == "player_spawn":
			spawn_local = slot.get("center", spawn_local)
			break
	var directions: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.UP,
		Vector2.DOWN,
		Vector2(1, 1).normalized(),
		Vector2(-1, 1).normalized(),
		Vector2(1, -1).normalized(),
		Vector2(-1, -1).normalized()
	]
	for seed_value in TEST_SEEDS:
		var generator: RefCounted = WORLD_GENERATOR_SCRIPT.new()
		generator.call("configure", seed_value)
		var spawn_height: float = float(generator.call("sample_height_at", center, biome_id, spawn_local, slots, "starting_valley"))
		var runtime: Node3D = WORLD_RUNTIME_SCRIPT.new()
		var spawn_position: Vector3 = runtime.call("generated_player_spawn_position", seed_value)
		if abs(spawn_position.y - (spawn_height + 1.2)) > 0.025:
			runtime.free()
			return _fail("Player spawn did not follow generated terrain for seed %d" % seed_value)
		var buried_position := Vector3(spawn_position.x, -2.0, spawn_position.z)
		var recovered_position: Vector3 = runtime.call("sanitize_outdoor_player_position", buried_position, seed_value)
		if recovered_position.distance_to(spawn_position) > 0.025:
			runtime.free()
			return _fail("Under-map recovery did not return to generated terrain for seed %d" % seed_value)
		var valid_position := spawn_position + Vector3(0, 3.0, 0)
		var preserved_position: Vector3 = runtime.call("sanitize_outdoor_player_position", valid_position, seed_value)
		runtime.free()
		if preserved_position != valid_position:
			return _fail("Terrain recovery moved an already-safe player for seed %d" % seed_value)
		for direction in directions:
			var previous_height: float = spawn_height
			for step_index in range(1, 11):
				var sample_point: Vector2 = spawn_local + direction * float(step_index * 2)
				var current_height: float = float(generator.call("sample_height_at", center, biome_id, sample_point, slots, "starting_valley"))
				if abs(current_height - previous_height) > 3.25:
					return _fail("Seed %d created a cliff wall beside player spawn" % seed_value)
				previous_height = current_height
	return true

func _test_road_ribbon_surface() -> bool:
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	for seed_value in TEST_SEEDS:
		var generator: RefCounted = WORLD_GENERATOR_SCRIPT.new()
		generator.call("configure", seed_value)
		var route: Array[Vector3] = generator.call(
			"primary_route_points",
			"starting_valley",
			region.get("center", Vector3.ZERO),
			str(region.get("biome", "green_highlands")),
			REGION_CATALOG.get_slots("starting_valley")
		)
		for index in range(1, route.size() - 1):
			var incoming := Vector2(
				route[index].x - route[index - 1].x,
				route[index].z - route[index - 1].z
			).normalized()
			var outgoing := Vector2(
				route[index + 1].x - route[index].x,
				route[index + 1].z - route[index].z
			).normalized()
			if incoming.dot(outgoing) <= 0.0:
				return _fail("Road reversed direction and could fold at seed %d" % seed_value)

		var exploration: Node = PROCEDURAL_EXPLORATION_SCRIPT.new()
		var surface: Dictionary = exploration.call("build_road_surface_data", route)
		exploration.free()
		var vertices: PackedVector3Array = surface.get("vertices", PackedVector3Array())
		var normals: PackedVector3Array = surface.get("normals", PackedVector3Array())
		var uvs: PackedVector2Array = surface.get("uvs", PackedVector2Array())
		var indices: PackedInt32Array = surface.get("indices", PackedInt32Array())
		if vertices.size() != route.size() * 2 or normals.size() != vertices.size() or uvs.size() != vertices.size():
			return _fail("Road ribbon surface arrays did not match the route")
		if indices.size() != (route.size() - 1) * 6:
			return _fail("Road ribbon did not contain exactly two triangles per segment")
		for index in range(route.size()):
			var width: float = vertices[index * 2].distance_to(vertices[index * 2 + 1])
			if abs(width - 3.3) > 0.01:
				return _fail("Road ribbon width was not stable")
			if index > 0:
				var left_edge: float = vertices[index * 2].distance_to(vertices[(index - 1) * 2])
				var right_edge: float = vertices[index * 2 + 1].distance_to(vertices[(index - 1) * 2 + 1])
				if max(left_edge, right_edge) > 10.0:
					return _fail("Road ribbon formed an implausibly tall connector at seed %d" % seed_value)
		for vertex_index in indices:
			if vertex_index < 0 or vertex_index >= vertices.size():
				return _fail("Road ribbon contained an out-of-bounds index")
	return true


func _test_legacy_overlay_disabled() -> bool:
	var legacy_runtime: Node = LEGACY_EXPLORATION_RUNTIME.new()
	var enabled: bool = bool(legacy_runtime.get("legacy_presentation_enabled"))
	legacy_runtime.free()
	if enabled:
		return _fail("Fixed prototype exploration presentation was still enabled")
	return true

func _test_validator_rejections() -> bool:
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var center: Vector3 = region.get("center", Vector3.ZERO)
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var slots: Array[Dictionary] = REGION_CATALOG.get_slots("starting_valley")
	var generator: RefCounted = WORLD_GENERATOR_SCRIPT.new()
	generator.call("configure", TEST_SEEDS[0])
	var valid_chunk: Dictionary = generator.call("generate_chunk_data", "starting_valley", biome_id, center, Vector2i.ZERO, slots)

	var bad_format: Dictionary = valid_chunk.duplicate(true)
	bad_format["format_version"] = 999
	if _validation_ok(generator.call("validate_chunk_data", bad_format)):
		return _fail("Chunk validator accepted an unknown data format")

	var bad_index: Dictionary = valid_chunk.duplicate(true)
	var bad_indices: PackedInt32Array = bad_index.get("indices", PackedInt32Array())
	bad_indices[0] = 999999
	bad_index["indices"] = bad_indices
	if _validation_ok(generator.call("validate_chunk_data", bad_index)):
		return _fail("Chunk validator accepted an out-of-bounds mesh index")

	var content_generator: RefCounted = CONTENT_GENERATOR_SCRIPT.new()
	content_generator.call("configure", TEST_SEEDS[0])
	var valid_content: Dictionary = content_generator.call("generate_region_content", "starting_valley")
	var duplicate_content: Dictionary = valid_content.duplicate(true)
	var pois_value: Variant = duplicate_content.get("pois", [])
	if not pois_value is Array or (pois_value as Array).size() < 2:
		return _fail("Content generator did not produce enough POIs for validator test")
	var pois: Array = pois_value as Array
	var first_poi: Dictionary = pois[0] as Dictionary
	var second_poi: Dictionary = (pois[1] as Dictionary).duplicate(true)
	second_poi["id"] = str(first_poi.get("id", ""))
	pois[1] = second_poi
	duplicate_content["pois"] = pois
	if _validation_ok(content_generator.call("validate_region_content", duplicate_content)):
		return _fail("Content validator accepted duplicate stable IDs")
	return true

func _test_extreme_seed_sanitization() -> bool:
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var generator: RefCounted = WORLD_GENERATOR_SCRIPT.new()
	var world_state: Node = WORLD_STATE_SCRIPT.new()
	for raw_seed in [0, -1, -2147483648, 2147483647]:
		generator.call("configure", raw_seed)
		var generator_seed: int = int(generator.get("world_seed"))
		var state_seed: int = int(world_state.call("sanitize_seed", raw_seed))
		if generator_seed <= 0:
			world_state.free()
			return _fail("Seed sanitization left a non-positive world seed")
		if generator_seed != state_seed:
			world_state.free()
			return _fail("WorldState and WorldGenerator normalized seed %d differently" % raw_seed)
		var chunk: Dictionary = generator.call(
			"generate_chunk_data",
			"starting_valley",
			str(region.get("biome", "green_highlands")),
			region.get("center", Vector3.ZERO),
			Vector2i.ZERO,
			REGION_CATALOG.get_slots("starting_valley")
		)
		if not _valid_nonfallback_chunk(generator, chunk):
			world_state.free()
			return _fail("Sanitized seed %d could not generate a valid chunk" % raw_seed)
	world_state.free()
	return true

func _test_job_queue_cancellation() -> bool:
	var queue: RefCounted = JOB_QUEUE_SCRIPT.new()
	executed_jobs = 0
	if not bool(queue.call("enqueue", "old-world", Callable(self, "_record_job").bind(1))):
		return _fail("Generation queue rejected a valid job")
	if bool(queue.call("enqueue", "old-world", Callable(self, "_record_job").bind(10))):
		return _fail("Generation queue accepted a duplicate job ID")
	queue.call("clear")
	queue.call("process_budget", 8, 50.0)
	if executed_jobs != 0:
		return _fail("Cleared generation job executed after seed invalidation")
	if not bool(queue.call("enqueue", "new-world", Callable(self, "_record_job").bind(2))):
		return _fail("Generation queue rejected a new-epoch job")
	queue.call("process_budget", 1, 50.0)
	if executed_jobs != 2:
		return _fail("New generation job did not execute exactly once")
	return true

func _record_job(amount: int) -> void:
	executed_jobs += amount

func _valid_nonfallback_chunk(generator: RefCounted, chunk: Dictionary) -> bool:
	if chunk.is_empty() or bool(chunk.get("fallback", true)):
		return false
	return _validation_ok(generator.call("validate_chunk_data", chunk))

func _valid_nonfallback_content(generator: RefCounted, content: Dictionary) -> bool:
	if content.is_empty() or bool(content.get("fallback", true)):
		return false
	return _validation_ok(generator.call("validate_region_content", content))

func _validation_ok(value: Variant) -> bool:
	return value is Dictionary and (value as Dictionary).get("ok", false) == true

func _same_chunk_geometry(first: Dictionary, second: Dictionary) -> bool:
	var first_vertices: PackedVector3Array = first.get("vertices", PackedVector3Array())
	var second_vertices: PackedVector3Array = second.get("vertices", PackedVector3Array())
	var first_indices: PackedInt32Array = first.get("indices", PackedInt32Array())
	var second_indices: PackedInt32Array = second.get("indices", PackedInt32Array())
	if first_vertices.size() != second_vertices.size() or first_indices != second_indices:
		return false
	for index in range(first_vertices.size()):
		if first_vertices[index].distance_to(second_vertices[index]) > EPSILON:
			return false
	return true

func _same_vector3_array(first: Array[Vector3], second: Array[Vector3]) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if first[index].distance_to(second[index]) > EPSILON:
			return false
	return true

func _same_content_geometry(first: Dictionary, second: Dictionary) -> bool:
	var first_road: Array[Vector3] = first.get("road", [])
	var second_road: Array[Vector3] = second.get("road", [])
	if not _same_vector3_array(first_road, second_road):
		return false
	for key in ["pois", "trees", "rocks", "encounters", "loot"]:
		var first_values: Array = first.get(key, [])
		var second_values: Array = second.get(key, [])
		if first_values.size() != second_values.size():
			return false
		for index in range(first_values.size()):
			var first_record: Dictionary = first_values[index] as Dictionary
			var second_record: Dictionary = second_values[index] as Dictionary
			if str(first_record.get("id", "")) != str(second_record.get("id", "")):
				return false
			var first_position: Vector3 = first_record.get("position", Vector3.ZERO)
			var second_position: Vector3 = second_record.get("position", Vector3.ZERO)
			if first_position.distance_to(second_position) > EPSILON:
				return false
	return true

func _valid_route(route: Array[Vector3], generator: RefCounted, center: Vector3, biome_id: String, slots: Array[Dictionary]) -> bool:
	if route.size() < 8:
		return false
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var entry: Vector2 = region.get("entry", Vector2.ZERO)
	var exit_point: Vector2 = region.get("exit", Vector2.ZERO)
	if Vector2(route[0].x, route[0].z).distance_to(entry) > EPSILON:
		return false
	if Vector2(route[-1].x, route[-1].z).distance_to(exit_point) > EPSILON:
		return false
	var spawn_anchor := Vector2(0, 24)
	var reached_spawn: bool = false
	for index in range(route.size()):
		var local := Vector2(route[index].x, route[index].z)
		if local.distance_to(spawn_anchor) <= EPSILON:
			reached_spawn = true
		var terrain_height: float = float(generator.call("sample_height_at", center, biome_id, local, slots, "starting_valley"))
		if abs(route[index].y - (terrain_height + 0.045)) > EPSILON:
			return false
		if index > 0 and local.distance_to(Vector2(route[index - 1].x, route[index - 1].z)) > 6.0:
			return false
	return reached_spawn

func _matching_x_seam(left: Dictionary, right: Dictionary) -> bool:
	var left_vertices: PackedVector3Array = left.get("vertices", PackedVector3Array())
	var right_vertices: PackedVector3Array = right.get("vertices", PackedVector3Array())
	var left_normals: PackedVector3Array = left.get("normals", PackedVector3Array())
	var right_normals: PackedVector3Array = right.get("normals", PackedVector3Array())
	if left_vertices.size() != right_vertices.size() or left_vertices.is_empty():
		return false
	var side: int = int(round(sqrt(float(left_vertices.size()))))
	if side * side != left_vertices.size():
		return false
	for row in range(side):
		var left_index: int = row * side + side - 1
		var right_index: int = row * side
		if left_vertices[left_index].distance_to(right_vertices[right_index]) > EPSILON:
			return false
		if left_normals[left_index].distance_to(right_normals[right_index]) > EPSILON:
			return false
	return true

func _height_range(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var minimum: float = INF
	var maximum: float = -INF
	for value in values:
		minimum = min(minimum, value)
		maximum = max(maximum, value)
	return maximum - minimum

func _height_delta(first: PackedFloat32Array, second: PackedFloat32Array) -> float:
	if first.size() != second.size():
		return INF
	var total: float = 0.0
	for index in range(first.size()):
		total += abs(first[index] - second[index])
	return total

func _route_differs(first: Array[Vector3], second: Array[Vector3], minimum_delta: float) -> bool:
	if first.size() != second.size():
		return true
	for index in range(first.size()):
		if Vector2(first[index].x, first[index].z).distance_to(Vector2(second[index].x, second[index].z)) >= minimum_delta:
			return true
	return false

func _content_layout_differs(first: Dictionary, second: Dictionary, minimum_delta: float) -> bool:
	var first_pois: Array = first.get("pois", [])
	var second_pois: Array = second.get("pois", [])
	if first_pois.size() != second_pois.size():
		return true
	for index in range(first_pois.size()):
		var first_position: Vector3 = (first_pois[index] as Dictionary).get("position", Vector3.ZERO)
		var second_position: Vector3 = (second_pois[index] as Dictionary).get("position", Vector3.ZERO)
		if Vector2(first_position.x, first_position.z).distance_to(Vector2(second_position.x, second_position.z)) >= minimum_delta:
			return true
	return _route_differs(first.get("road", []), second.get("road", []), minimum_delta)

func _geometry_fingerprint(heights: PackedFloat32Array, route: Array[Vector3], content: Dictionary) -> String:
	var fingerprint := ""
	for height in heights:
		fingerprint += "%.3f|" % height
	for index in range(0, route.size(), 5):
		fingerprint += "%.2f,%.2f|" % [route[index].x, route[index].z]
	var pois: Array = content.get("pois", [])
	for value in pois:
		var position: Vector3 = (value as Dictionary).get("position", Vector3.ZERO)
		fingerprint += "%.2f,%.2f|" % [position.x, position.z]
	return fingerprint

func _fail(message: String) -> bool:
	printerr("WORLD_GENERATOR_V3_FAILED: %s" % message)
	quit(1)
	return false
