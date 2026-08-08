extends SceneTree

const THEME_CATALOG := preload("res://scripts/world/region_content_theme_catalog.gd")
const GRAPH_GENERATOR := preload("res://scripts/world/world_graph_generator.gd")
const GRAPH_RUNTIME := preload("res://scripts/world/world_graph_runtime.gd")

const TEST_SEED: int = 8242601
const TEST_NODE_COUNT: int = 128

func _init() -> void:
	if not _validate_catalog():
		return
	var generator: RefCounted = GRAPH_GENERATOR.new()
	generator.call("configure", TEST_SEED)
	var first: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	var second: Dictionary = generator.call("generate_graph", TEST_NODE_COUNT)
	if not _validate_graph_themes(first, second):
		return
	if not _validate_runtime_boundary(first, generator):
		return
	print("REGION_CONTENT_THEME_OK themes=%d nodes=%d" % [THEME_CATALOG.get_ids().size(), TEST_NODE_COUNT])
	quit(0)

func _validate_catalog() -> bool:
	var ids: Array[String] = THEME_CATALOG.get_ids()
	if ids.size() < 8:
		return _fail("Content expansion requires at least eight reusable themes")
	for biome_id in ["green_highlands", "blackwood", "windscar_highlands", "veilmoor"]:
		var biome_themes: Array[String] = THEME_CATALOG.get_ids_for_biome(biome_id)
		if biome_themes.size() < 2:
			return _fail("Biome %s does not have enough theme variety" % biome_id)
		for theme_id in biome_themes:
			if not THEME_CATALOG.validate_theme(THEME_CATALOG.get_theme(theme_id)):
				return _fail("Theme %s failed catalog validation" % theme_id)
	var a: Dictionary = THEME_CATALOG.select_theme(TEST_SEED, "region:cell:7:-3", "blackwood", "wilds")
	var b: Dictionary = THEME_CATALOG.select_theme(TEST_SEED, "region:cell:7:-3", "blackwood", "wilds")
	if var_to_str(a) != var_to_str(b):
		return _fail("Theme selection is not deterministic")
	return true

func _validate_graph_themes(first: Dictionary, second: Dictionary) -> bool:
	if int(first.get("content_theme_format_version", 0)) != THEME_CATALOG.FORMAT_VERSION:
		return _fail("Graph did not expose content theme format version")
	var first_nodes: Array = first.get("nodes", []) as Array
	var second_nodes: Array = second.get("nodes", []) as Array
	if first_nodes.size() != TEST_NODE_COUNT or var_to_str(first_nodes) != var_to_str(second_nodes):
		return _fail("Graph theme annotation changed deterministic regeneration")
	var counts: Dictionary = first.get("content_theme_counts", {}) as Dictionary
	var count_total: int = 0
	for value in counts.values():
		count_total += int(value)
	if count_total != TEST_NODE_COUNT:
		return _fail("Content theme summary does not cover the graph")
	var observed_themes: Dictionary = {}
	for node_value in first_nodes:
		if not node_value is Dictionary:
			return _fail("Graph contains invalid themed node")
		var node: Dictionary = node_value as Dictionary
		var theme_id: String = str(node.get("content_theme_id", ""))
		var theme: Dictionary = node.get("content_theme", {}) as Dictionary
		if theme_id.is_empty() or theme_id != str(theme.get("id", "")):
			return _fail("Graph node is missing canonical content theme identity")
		if str(theme.get("biome", "")) != str(node.get("biome", "")):
			return _fail("Graph content theme does not match region biome")
		if not THEME_CATALOG.validate_theme(theme):
			return _fail("Graph node contains invalid content theme")
		observed_themes[theme_id] = true
	if observed_themes.size() < 4:
		return _fail("Large graph did not produce meaningful theme variety")
	return true

func _validate_runtime_boundary(graph: Dictionary, generator: RefCounted) -> bool:
	var root := Node3D.new()
	get_root().add_child(root)
	var regions_root := Node3D.new()
	root.add_child(regions_root)
	var runtime := Node.new()
	runtime.set_script(GRAPH_RUNTIME)
	runtime.set("generator", generator)
	runtime.set("graph", graph)
	runtime.set("regions_root", regions_root)
	runtime.call("_index_graph")
	var target: Dictionary = {}
	for node_value in graph.get("nodes", []) as Array:
		if node_value is Dictionary and (node_value as Dictionary).get("anchor", false) != true:
			target = node_value as Dictionary
			break
	if target.is_empty():
		runtime.free()
		root.queue_free()
		return _fail("No generated region available for theme runtime test")
	var stable_id: String = str(target.get("stable_id", ""))
	var loaded_value: Variant = runtime.call("load_region_for_test", stable_id, regions_root)
	if not loaded_value is Node3D:
		runtime.free()
		root.queue_free()
		return _fail("Themed region did not cross runtime boundary")
	var loaded := loaded_value as Node3D
	var ok: bool = str(loaded.get_meta("content_theme_id", "")) == str(target.get("content_theme_id", ""))
	runtime.call("unload_region_for_test", stable_id)
	runtime.free()
	root.queue_free()
	if not ok:
		return _fail("Streamed region lost content theme identity")
	return true

func _fail(message: String) -> bool:
	printerr("REGION_CONTENT_THEME_FAILED: %s" % message)
	quit(1)
	return false
