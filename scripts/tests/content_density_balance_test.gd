extends SceneTree

const BALANCER := preload("res://scripts/world/content_density_balancer.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")

const TEST_SEED: int = 68082601
const TEST_NODE_COUNT: int = 1024

func _init() -> void:
	if not _validate_large_world():
		return
	print("CONTENT_DENSITY_BALANCE_OK nodes=%d" % TEST_NODE_COUNT)
	quit(0)

func _validate_large_world() -> bool:
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var graph: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var nodes: Array = graph.get("nodes", []) as Array
	if nodes.size() != TEST_NODE_COUNT:
		return _fail("Large-world density gate received the wrong node count")
	var biome_counts: Dictionary = {}
	var band_counts: Dictionary = {}
	var biome_score_sum: Dictionary = {}
	for node_value in nodes:
		if not node_value is Dictionary:
			return _fail("Density gate encountered invalid graph node")
		var node: Dictionary = node_value as Dictionary
		var budget: Dictionary = BALANCER.balance(node)
		if not BALANCER.validate_budget(budget):
			return _fail("Density budget violated configured band limits")
		var biome: String = str(budget.get("biome", ""))
		var band: String = str(budget.get("progression_band", ""))
		biome_counts[biome] = int(biome_counts.get(biome, 0)) + 1
		band_counts[band] = int(band_counts.get(band, 0)) + 1
		biome_score_sum[biome] = float(biome_score_sum.get(biome, 0.0)) + float(budget.get("density_score", 0.0))
	for biome_id in ["green_highlands", "blackwood", "windscar_highlands", "veilmoor", "ashen_fen", "frostmere"]:
		if int(biome_counts.get(biome_id, 0)) < 12:
			return _fail("Large-world gate has insufficient coverage for biome %s" % biome_id)
	for band in ["heartland", "frontier", "wilds"]:
		if int(band_counts.get(band, 0)) <= 0:
			return _fail("Large-world gate is missing progression band %s" % band)
	var min_average: float = INF
	var max_average: float = 0.0
	for biome_id in biome_counts.keys():
		var count: int = int(biome_counts.get(biome_id, 0))
		if count <= 0:
			continue
		var average: float = float(biome_score_sum.get(biome_id, 0.0)) / float(count)
		min_average = minf(min_average, average)
		max_average = maxf(max_average, average)
	if min_average <= 0.0 or max_average / min_average > 1.45:
		return _fail("Biome content-density averages drifted outside the balancing envelope")
	var heartland: Dictionary = {"stable_id": "region:test:heartland", "biome": "green_highlands", "progression_band": "heartland", "content_profile": {"encounter_budget": 2, "poi_budget": 3, "loot_tier": 1, "danger": 0.30, "secret_chance": 0.18}}
	var wilds: Dictionary = {"stable_id": "region:test:wilds", "biome": "green_highlands", "progression_band": "wilds", "content_profile": {"encounter_budget": 5, "poi_budget": 4, "loot_tier": 3, "danger": 0.76, "secret_chance": 0.52}}
	if float(BALANCER.balance(wilds).get("density_score", 0.0)) <= float(BALANCER.balance(heartland).get("density_score", 0.0)):
		return _fail("Progression-aware density does not increase from heartland to wilds")
	return true

func _fail(message: String) -> bool:
	printerr("CONTENT_DENSITY_BALANCE_FAILED: %s" % message)
	quit(1)
	return false
