extends SceneTree

const CONTENT_GENERATOR := preload("res://scripts/world/procedural_content_generator.gd")
const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")

const BASE_SEED: int = 8242601
const DIFFERENT_SEED: int = 8242602
const REQUIRED_LAYERS: Array[String] = ["road", "pois", "trees", "rocks", "encounters", "loot"]

func _initialize() -> void:
	var checked_regions: int = 0
	for region_id in REGION_CATALOG.get_region_ids():
		if not _verify_region(region_id):
			quit(1)
			return
		checked_regions += 1
	print("GENERATION_DETERMINISM_OK seed=%d regions=%d" % [BASE_SEED, checked_regions])
	quit(0)

func _verify_region(region_id: String) -> bool:
	var first := CONTENT_GENERATOR.new()
	first.configure(BASE_SEED)
	var a: Dictionary = first.generate_region_content(region_id)

	var second := CONTENT_GENERATOR.new()
	second.configure(BASE_SEED)
	var b: Dictionary = second.generate_region_content(region_id)
	if a != b:
		printerr("Determinism failure: identical seeds produced different content for %s" % region_id)
		return false

	var third := CONTENT_GENERATOR.new()
	third.configure(DIFFERENT_SEED)
	var c: Dictionary = third.generate_region_content(region_id)
	if a == c:
		printerr("Seed variation failure: different seeds produced identical content for %s" % region_id)
		return false

	for layer_name in REQUIRED_LAYERS:
		if not a.has(layer_name):
			printerr("Generation schema failure: %s missing layer %s" % [region_id, layer_name])
			return false

	var expected_region_id: String = str(a.get("region_id", ""))
	if expected_region_id != region_id:
		printerr("Generation identity failure: expected %s, got %s" % [region_id, expected_region_id])
		return false
	return true
