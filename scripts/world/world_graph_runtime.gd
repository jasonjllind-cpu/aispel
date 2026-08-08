extends Node
class_name WorldGraphRuntime

const GRAPH_GENERATOR_SCRIPT := preload("res://scripts/world/world_graph_generator.gd")
const SUBREGION_GRAPH_GENERATOR := preload("res://scripts/world/subregion_graph_generator.gd")

const UPDATE_INTERVAL: float = 0.30
const LOAD_RADIUS: float = 245.0
const UNLOAD_RADIUS: float = 330.0
const DEFAULT_GRAPH_NODES: int = 18

var world: Node3D
var world_state: Node
var player: Node3D
var generator: RefCounted
var graph: Dictionary = {}
var nodes_by_id: Dictionary = {}
var loaded_regions: Dictionary = {}
var subregion_cache: Dictionary = {}
var regions_root: Node3D
var elapsed: float = 0.0
var active_world_seed: int = 8242601

func _ready() -> void:
	add_to_group("world_graph_runtime")
	set_process(false)
	call_deferred("_install")

func _install() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	world = get_parent() as Node3D
	world_state = get_node_or_null("/root/WorldState")
	if world == null:
		return
	active_world_seed = _world_seed()
	generator = GRAPH_GENERATOR_SCRIPT.new()
	generator.call("configure", active_world_seed)
	graph = generator.call("generate_graph", DEFAULT_GRAPH_NODES)
	_index_graph()
	regions_root = world.get_node_or_null("RuntimeGraphRegions") as Node3D
	if regions_root == null:
		regions_root = Node3D.new()
		regions_root.name = "RuntimeGraphRegions"
		regions_root.add_to_group("graph_region_root")
		world.add_child(regions_root)
	player = _find_player()
	_update_streaming()
	set_process(true)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < UPDATE_INTERVAL:
		return
	elapsed = 0.0
	if player == null or not is_instance_valid(player):
		player = _find_player()
	_update_streaming()

func rebuild_for_seed(seed_value: int, target_nodes: int = DEFAULT_GRAPH_NODES) -> void:
	_release_all()
	subregion_cache.clear()
	active_world_seed = seed_value
	if generator == null:
		generator = GRAPH_GENERATOR_SCRIPT.new()
	generator.call("configure", seed_value)
	graph = generator.call("generate_graph", target_nodes)
	_index_graph()
	_update_streaming()

func graph_node(stable_id: String) -> Dictionary:
	var value: Variant = nodes_by_id.get(stable_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func subregion_graph(stable_id: String) -> Dictionary:
	var cached: Variant = subregion_cache.get(stable_id)
	if cached is Dictionary:
		return (cached as Dictionary).duplicate(true)
	var parent_region: Dictionary = graph_node(stable_id)
	if parent_region.is_empty():
		return {}
	var generated: Dictionary = SUBREGION_GRAPH_GENERATOR.generate(active_world_seed, parent_region)
	if generated.is_empty():
		return {}
	subregion_cache[stable_id] = generated.duplicate(true)
	return generated.duplicate(true)

func cached_subregion_ids() -> Array[String]:
	var result: Array[String] = []
	for key in subregion_cache.keys():
		result.append(str(key))
	result.sort()
	return result

func nearest_node(world_position: Vector3, include_anchors: bool = true) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance: float = INF
	for value in nodes_by_id.values():
		if not value is Dictionary:
			continue
		var node: Dictionary = value as Dictionary
		if not include_anchors and node.get("anchor", false) == true:
			continue
		var center_value: Variant = node.get("center", null)
		if not center_value is Vector3:
			continue
		var center: Vector3 = center_value as Vector3
		var distance: float = _flat_distance(world_position, center)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = node
	return nearest.duplicate(true)

func loaded_region_ids() -> Array[String]:
	var result: Array[String] = []
	for key in loaded_regions.keys():
		result.append(str(key))
	result.sort()
	return result

func load_region_for_test(stable_id: String, parent: Node3D) -> Node3D:
	if regions_root == null:
		regions_root = parent
	return _load_graph_region(graph_node(stable_id))

func unload_region_for_test(stable_id: String) -> void:
	_unload_graph_region(stable_id)

func _index_graph() -> void:
	nodes_by_id.clear()
	var nodes_value: Variant = graph.get("nodes", [])
	if not nodes_value is Array:
		return
	for value in nodes_value as Array:
		if not value is Dictionary:
			continue
		var node: Dictionary = value as Dictionary
		var stable_id: String = str(node.get("stable_id", ""))
		if not stable_id.is_empty():
			nodes_by_id[stable_id] = node.duplicate(true)

func _update_streaming() -> void:
	if player == null or regions_root == null:
		return
	var position: Vector3 = player.global_position
	for value in nodes_by_id.values():
		if not value is Dictionary:
			continue
		var node: Dictionary = value as Dictionary
		# The original four regions remain owned by RegionManager during the
		# migration. Only new graph-generated instances are streamed here.
		if node.get("anchor", false) == true:
			continue
		var stable_id: String = str(node.get("stable_id", ""))
		var center: Vector3 = node.get("center", Vector3.ZERO)
		var distance: float = _flat_distance(position, center)
		if distance <= LOAD_RADIUS and not loaded_regions.has(stable_id):
			_load_graph_region(node)
		elif distance >= UNLOAD_RADIUS and loaded_regions.has(stable_id):
			_unload_graph_region(stable_id)

func _load_graph_region(node: Dictionary) -> Node3D:
	if node.is_empty() or regions_root == null:
		return null
	var stable_id: String = str(node.get("stable_id", ""))
	if stable_id.is_empty():
		return null
	var existing_value: Variant = loaded_regions.get(stable_id)
	if existing_value is Node3D and is_instance_valid(existing_value):
		return existing_value as Node3D
	var region := Node3D.new()
	region.name = _node_name(stable_id)
	region.position = node.get("center", Vector3.ZERO)
	region.set_meta("stable_id", stable_id)
	region.set_meta("generation_key", str(node.get("generation_key", "")))
	region.set_meta("biome", str(node.get("biome", "green_highlands")))
	region.set_meta("template_id", str(node.get("template_id", "")))
	region.set_meta("landmark_module", str(node.get("landmark_module", "")))
	region.set_meta("graph_cell", node.get("graph_cell", Vector2i.ZERO))
	region.set_meta("subregion_graph_id", "subgraph:%s" % stable_id)
	region.add_to_group("generated_graph_region")
	regions_root.add_child(region)
	loaded_regions[stable_id] = region
	return region

func _unload_graph_region(stable_id: String) -> void:
	var value: Variant = loaded_regions.get(stable_id)
	if value is Node and is_instance_valid(value):
		(value as Node).queue_free()
	loaded_regions.erase(stable_id)

func _release_all() -> void:
	for stable_id in loaded_region_ids():
		_unload_graph_region(stable_id)
	loaded_regions.clear()

func _find_player() -> Node3D:
	if get_tree() == null:
		return null
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty() or not players[0] is Node3D:
		return null
	return players[0] as Node3D

func _world_seed() -> int:
	if world_state != null:
		return int(world_state.get("world_seed"))
	return 8242601

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _node_name(stable_id: String) -> String:
	return "GraphRegion_%s" % stable_id.trim_prefix("region:").replace(":", "_").replace("-", "_")
