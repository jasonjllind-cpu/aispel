extends SceneTree

const CONTENT_GENERATOR := preload("res://scripts/world/procedural_content_generator.gd")

func _initialize() -> void:
	var first := CONTENT_GENERATOR.new()
	first.configure(8242601)
	var a: Dictionary = first.generate_region_content("blackwood")

	var second := CONTENT_GENERATOR.new()
	second.configure(8242601)
	var b: Dictionary = second.generate_region_content("blackwood")

	if a != b:
		printerr("Determinism failure: identical seeds produced different Blackwood content")
		quit(1)
		return

	var third := CONTENT_GENERATOR.new()
	third.configure(8242602)
	var c: Dictionary = third.generate_region_content("blackwood")
	if a == c:
		printerr("Seed variation failure: different seeds produced identical Blackwood content")
		quit(1)
		return

	var required_layers: Array[String] = ["road", "pois", "trees", "rocks", "encounters", "loot"]
	for layer_name in required_layers:
		if not a.has(layer_name):
			printerr("Generation schema failure: missing layer %s" % layer_name)
			quit(1)
			return

	print("GENERATION_DETERMINISM_OK seed=8242601 region=blackwood")
	quit(0)
