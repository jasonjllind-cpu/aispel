extends SceneTree

const EVENTS := preload("res://scripts/world/world_event_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 66082601
const TEST_NODE_COUNT: int = 240

func _init() -> void:
	if not _validate_catalog():
		return
	if not _validate_schedules():
		return
	print("WORLD_EVENT_SCHEDULE_OK events=%d nodes=%d" % [EVENTS.get_ids().size(), TEST_NODE_COUNT])
	quit(0)

func _validate_catalog() -> bool:
	if EVENTS.get_ids().size() < 11:
		return _fail("World event expansion requires at least eleven archetypes")
	var covered_biomes: Dictionary = {}
	for event_id in EVENTS.get_ids():
		var event: Dictionary = EVENTS.get_event(event_id)
		if not EVENTS.validate_event(event):
			return _fail("World event %s failed validation" % event_id)
		for biome_value in event.get("biomes", []) as Array:
			covered_biomes[str(biome_value)] = true
	for biome_id in ["green_highlands", "blackwood", "windscar_highlands", "veilmoor", "ashen_fen", "frostmere"]:
		if not covered_biomes.has(biome_id):
			return _fail("World event catalog does not cover biome %s" % biome_id)
	return true

func _validate_schedules() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var stable_ids: Dictionary = {}
	var scheduled_count: int = 0
	var two_event_regions: int = 0
	for node_value in graph.get("nodes", []) as Array:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value as Dictionary
		var first: Dictionary = EVENTS.build_region_schedule(TEST_SEED, node)
		var second: Dictionary = EVENTS.build_region_schedule(TEST_SEED, node)
		if var_to_str(first) != var_to_str(second):
			return _fail("World event schedule is not deterministic")
		var entries: Array = first.get("entries", []) as Array
		if entries.size() > 1:
			two_event_regions += 1
		for entry_value in entries:
			if not entry_value is Dictionary:
				return _fail("World event schedule contains invalid entry")
			var entry: Dictionary = entry_value as Dictionary
			scheduled_count += 1
			var stable_id: String = str(entry.get("stable_id", ""))
			if stable_id.is_empty() or stable_ids.has(stable_id):
				return _fail("World event stable IDs are missing or duplicated")
			stable_ids[stable_id] = true
			if str(entry.get("persistent_state_id", "")).is_empty() or str(entry.get("cycle_namespace", "")).is_empty():
				return _fail("World event lacks persistent scheduling metadata")
			var event: Dictionary = EVENTS.get_event(str(entry.get("event_id", "")))
			if not (event.get("biomes", []) as Array).has(str(node.get("biome", ""))):
				return _fail("World event does not match region biome")
			var period_hours: int = int(entry.get("period_days", 0)) * 24
			var phase_hour: int = int(entry.get("phase_hour", -1))
			if period_hours <= 0 or phase_hour < 0 or phase_hour >= period_hours:
				return _fail("World event phase is outside its deterministic cycle")
	if scheduled_count < TEST_NODE_COUNT:
		return _fail("World event schedule did not cover the macro world")
	if two_event_regions < 8:
		return _fail("Deep dangerous regions did not receive secondary world events")
	return true

func _fail(message: String) -> bool:
	printerr("WORLD_EVENT_SCHEDULE_FAILED: %s" % message)
	quit(1)
	return false
