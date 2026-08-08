extends SceneTree

const GENERATOR_SCRIPT := preload("res://scripts/world/world_graph_generator.gd")
const RUNTIME_SCRIPT := preload("res://scripts/world/world_graph_runtime.gd")

func _init() -> void:
	var root := Node3D.new()
	root.name = "GraphRuntimeTestRoot"
	get_root().add_child(root)
	var regions_root := Node3D.new()
	regions_root.name = "RuntimeGraphRegions"
	root.add_child(regions_root)

	var generator: RefCounted = GENERATOR_SCRIPT.new()
	generator.call("configure", 8242601)
	var graph: Dictionary = generator.call("generate_graph", 18)

	var runtime := Node.new()
	runtime.set_script(RUNTIME_SCRIPT)
	runtime.set("generator", generator)
	runtime.set("graph", graph)
	runtime.set("regions_root", regions_root)
	runtime.call("_index_graph")

	var generated: Dictionary = _first_generated_node(graph)
	if generated.is_empty():
		_fail(runtime, root, "No generated graph region available for lifecycle test")
		return
	var stable_id: String = str(generated.get("stable_id", ""))
	var region_value: Variant = runtime.call("load_region_for_test", stable_id, regions_root)
	if not region_value is Node3D:
		_fail(runtime, root, "Generated graph region did not load")
		return
	var region := region_value as Node3D
	if str(region.get_meta("stable_id", "")) != stable_id:
		_fail(runtime, root, "Loaded graph region lost its stable ID")
		return
	if str(region.get_meta("template_id", "")) != str(generated.get("template_id", "")):
		_fail(runtime, root, "Loaded graph region lost its template ID")
		return
	if region.position != generated.get("center", Vector3.ZERO):
		_fail(runtime, root, "Loaded graph region did not use deterministic world center")
		return
	var loaded_ids: Array[String] = runtime.call("loaded_region_ids")
	if loaded_ids != [stable_id]:
		_fail(runtime, root, "Loaded graph region registry mismatch")
		return
	var nearest: Dictionary = runtime.call("nearest_node", generated.get("center", Vector3.ZERO), false)
	if str(nearest.get("stable_id", "")) != stable_id:
		_fail(runtime, root, "Nearest generated graph region lookup mismatch")
		return

	runtime.call("unload_region_for_test", stable_id)
	if not (runtime.call("loaded_region_ids") as Array).is_empty():
		_fail(runtime, root, "Generated graph region registry did not unload")
		return

	print("WORLD_GRAPH_RUNTIME_OK region=%s biome=%s" % [stable_id, str(generated.get("biome", ""))])
	runtime.free()
	root.queue_free()
	quit(0)

func _first_generated_node(graph: Dictionary) -> Dictionary:
	var nodes_value: Variant = graph.get("nodes", [])
	if not nodes_value is Array:
		return {}
	for value in nodes_value as Array:
		if value is Dictionary and (value as Dictionary).get("anchor", false) != true:
			return (value as Dictionary).duplicate(true)
	return {}

func _fail(runtime: Node, root: Node, message: String) -> void:
	printerr("WORLD_GRAPH_RUNTIME_FAILED: %s" % message)
	runtime.free()
	root.queue_free()
	quit(1)
