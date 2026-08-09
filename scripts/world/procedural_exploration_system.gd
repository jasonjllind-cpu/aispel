extends Node

const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")
const BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")
const CONTENT_GENERATOR_SCRIPT := preload("res://scripts/world/procedural_content_generator.gd")
const JOB_QUEUE_SCRIPT := preload("res://scripts/world/generation_job_queue.gd")
const GENERATED_LOOT_SCRIPT := preload("res://scripts/world/generated_loot.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const TEX_STONE := preload("res://assets/textures/stone.svg")
const TEX_BARK := preload("res://assets/textures/bark.svg")
const TEX_METAL := preload("res://assets/textures/metal.svg")
const TEX_CLOTH := preload("res://assets/textures/cloth.svg")

const REGION_SCAN_INTERVAL: float = 0.40
const DISCOVERY_SCAN_INTERVAL: float = 0.20
const JOB_BUDGET_MSEC: float = 4.0
const GENERATION_FORMAT_VERSION: int = 3
const DEFAULT_WORLD_SEED: int = 8242601

var world: Node3D
var world_state: Node
var content_generator: RefCounted
var job_queue: RefCounted
var queued_regions: Dictionary = {}
var scan_timer: float = 0.0
var discovery_timer: float = 0.0
var status_label: Label
var discovery_card: ColorRect
var discovery_label: Label
var discovery_tween: Tween
var last_build_msec: float = 0.0
var configured_world_seed: int = 0
var generation_epoch: int = 0
var rejected_content_batches: int = 0
var fallback_content_batches: int = 0

func _ready() -> void:
	set_process(false)
	call_deferred("_install")

func _install() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	world = get_parent() as Node3D
	if world == null:
		return
	world_state = get_node_or_null("/root/WorldState")
	configured_world_seed = _normalized_seed(_world_seed())
	generation_epoch = 1
	content_generator = CONTENT_GENERATOR_SCRIPT.new()
	content_generator.call("configure", configured_world_seed)
	job_queue = JOB_QUEUE_SCRIPT.new()
	_build_ui()
	_scan_regions()
	set_process(true)

func _process(delta: float) -> void:
	_sync_generation_context()
	if job_queue != null:
		job_queue.call("process_budget", 1, JOB_BUDGET_MSEC)
	scan_timer += delta
	if scan_timer >= REGION_SCAN_INTERVAL:
		scan_timer = 0.0
		_scan_regions()
	discovery_timer += delta
	if discovery_timer >= DISCOVERY_SCAN_INTERVAL:
		discovery_timer = 0.0
		_scan_poi_discovery()
	_refresh_status()

func _scan_regions() -> void:
	if world == null:
		return
	_schedule_region(world, "starting_valley", "GeneratedExplorationStartingValley")
	var runtime_regions := world.get_node_or_null("RuntimeRegions") as Node3D
	if runtime_regions == null:
		return
	for child in runtime_regions.get_children():
		if not child is Node3D:
			continue
		var region_node := child as Node3D
		var region_id: String = region_node.name.trim_prefix("Region_")
		if REGION_CATALOG.has_region(region_id):
			_schedule_region(region_node, region_id, "GeneratedExploration")

func _schedule_region(parent: Node3D, region_id: String, child_name: String) -> void:
	if not is_instance_valid(parent) or parent.has_node(child_name) or job_queue == null:
		return
	var queue_key := "exploration:%d:%s:%d" % [generation_epoch, region_id, parent.get_instance_id()]
	if queued_regions.has(queue_key):
		return
	queued_regions[queue_key] = true
	var callback := Callable(self, "_build_region_content").bind(
		parent,
		region_id,
		child_name,
		queue_key,
		generation_epoch,
		configured_world_seed
	)
	var accepted: bool = bool(job_queue.call("enqueue", queue_key, callback))
	if not accepted:
		queued_regions.erase(queue_key)

func _build_region_content(parent: Node3D, region_id: String, child_name: String, queue_key: String, expected_epoch: int, expected_seed: int) -> void:
	var started_usec: int = Time.get_ticks_usec()
	queued_regions.erase(queue_key)
	if expected_epoch != generation_epoch or expected_seed != configured_world_seed:
		return
	if not is_instance_valid(parent) or parent.has_node(child_name) or content_generator == null:
		return
	var data_value: Variant = content_generator.call("generate_region_content", region_id)
	if not data_value is Dictionary:
		rejected_content_batches += 1
		return
	if expected_epoch != generation_epoch or expected_seed != configured_world_seed:
		return
	var data: Dictionary = data_value as Dictionary
	if int(data.get("format_version", 0)) != GENERATION_FORMAT_VERSION:
		rejected_content_batches += 1
		return
	if int(data.get("world_seed", 0)) != expected_seed or str(data.get("region_id", "")) != region_id:
		rejected_content_batches += 1
		return
	var validation_value: Variant = content_generator.call("validate_region_content", data)
	if not validation_value is Dictionary or (validation_value as Dictionary).get("ok", false) != true:
		rejected_content_batches += 1
		var error_code := "invalid_content"
		if validation_value is Dictionary:
			error_code = str((validation_value as Dictionary).get("error", error_code))
		push_error("Exploration generation rejected %s: %s" % [region_id, error_code])
		return
	if bool(data.get("fallback", false)):
		fallback_content_batches += 1

	var biome_id: String = str(data.get("biome_id", "green_highlands"))
	var biome: Dictionary = BIOME_CATALOG.get_biome(biome_id)
	var root := Node3D.new()
	root.name = child_name
	root.add_to_group("generated_exploration_root")
	root.set_meta("region_id", region_id)
	root.set_meta("world_seed", expected_seed)
	root.set_meta("generation_epoch", expected_epoch)
	root.set_meta("content_signature", str(data.get("content_signature", "")))

	_build_road(root, data, biome)
	_build_vegetation(root, data, biome)
	_build_pois(root, data, biome)
	_build_loot(root, data, biome)
	_build_encounters(root, data, biome)
	if expected_epoch != generation_epoch or expected_seed != configured_world_seed:
		root.free()
		return
	if not is_instance_valid(parent) or parent.has_node(child_name):
		root.free()
		return
	parent.add_child(root)
	last_build_msec = float(Time.get_ticks_usec() - started_usec) / 1000.0

func _sync_generation_context() -> void:
	if world == null or content_generator == null or job_queue == null:
		return
	var current_seed: int = _normalized_seed(_world_seed())
	if current_seed == configured_world_seed:
		return
	configured_world_seed = current_seed
	generation_epoch += 1
	job_queue.call("clear")
	queued_regions.clear()
	content_generator.call("configure", configured_world_seed)
	_clear_generated_exploration_roots()
	_scan_regions()

func _clear_generated_exploration_roots() -> void:
	if not is_inside_tree():
		return
	for value in get_tree().get_nodes_in_group("generated_exploration_root"):
		if value is Node and is_instance_valid(value):
			(value as Node).free()

func _exit_tree() -> void:
	generation_epoch += 1
	queued_regions.clear()
	if job_queue != null:
		job_queue.call("clear")

func _build_road(root: Node3D, data: Dictionary, biome: Dictionary) -> void:
	var road_value: Variant = data.get("road", [])
	if not road_value is Array:
		return
	var road: Array = road_value as Array
	if road.size() < 2:
		return
	var material := _mat(biome.get("road_color", Color("827760")), TEX_STONE)
	var road_root := Node3D.new()
	road_root.name = "GeneratedRoad"
	root.add_child(road_root)
	for i in range(road.size() - 1):
		if not road[i] is Vector3 or not road[i + 1] is Vector3:
			continue
		var start: Vector3 = road[i]
		var finish: Vector3 = road[i + 1]
		var direction: Vector3 = finish - start
		var length: float = Vector2(direction.x, direction.z).length()
		if length <= 0.01:
			continue
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(4.3, 0.09, length + 0.55)
		mesh_instance.mesh = mesh
		mesh_instance.material_override = material
		mesh_instance.position = (start + finish) * 0.5 + Vector3(0, 0.02, 0)
		mesh_instance.rotation.y = atan2(direction.x, direction.z)
		road_root.add_child(mesh_instance)

func _build_vegetation(root: Node3D, data: Dictionary, biome: Dictionary) -> void:
	var trees_value: Variant = data.get("trees", [])
	var rocks_value: Variant = data.get("rocks", [])
	var trees: Array = trees_value as Array if trees_value is Array else []
	var rocks: Array = rocks_value as Array if rocks_value is Array else []
	var vegetation_root := Node3D.new()
	vegetation_root.name = "GeneratedVegetation"
	root.add_child(vegetation_root)

	if not trees.is_empty():
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.radial_segments = 5
		trunk_mesh.rings = 1
		trunk_mesh.height = 2.0
		trunk_mesh.top_radius = 0.18
		trunk_mesh.bottom_radius = 0.28
		trunk_mesh.material = _mat(biome.get("tree_trunk", Color("5b3826")), TEX_BARK)

		var crown_mesh := CylinderMesh.new()
		crown_mesh.radial_segments = 6
		crown_mesh.rings = 1
		crown_mesh.height = 2.9
		crown_mesh.top_radius = 0.05
		crown_mesh.bottom_radius = 1.15
		crown_mesh.material = _mat(biome.get("tree_leaf", Color("285238")))

		var trunk_multi := MultiMesh.new()
		trunk_multi.transform_format = MultiMesh.TRANSFORM_3D
		trunk_multi.mesh = trunk_mesh
		trunk_multi.instance_count = trees.size()
		var crown_multi := MultiMesh.new()
		crown_multi.transform_format = MultiMesh.TRANSFORM_3D
		crown_multi.mesh = crown_mesh
		crown_multi.instance_count = trees.size()

		for i in range(trees.size()):
			var tree: Dictionary = trees[i] as Dictionary
			var pos: Vector3 = tree.get("position", Vector3.ZERO)
			var scale_value: float = float(tree.get("scale", 1.0))
			var rotation_y: float = float(tree.get("rotation_y", 0.0))
			var dead: bool = bool(tree.get("dead", false))
			var trunk_basis := Basis(Vector3.UP, rotation_y).scaled(Vector3(scale_value, scale_value, scale_value))
			trunk_multi.set_instance_transform(i, Transform3D(trunk_basis, pos + Vector3(0, 1.0 * scale_value, 0)))
			var crown_scale := Vector3(scale_value * (0.46 if dead else 1.0), scale_value * (0.38 if dead else 1.0), scale_value * (0.46 if dead else 1.0))
			var crown_basis := Basis(Vector3.UP, rotation_y).scaled(crown_scale)
			crown_multi.set_instance_transform(i, Transform3D(crown_basis, pos + Vector3(0, 3.0 * scale_value, 0)))

		var trunks := MultiMeshInstance3D.new()
		trunks.name = "TreeTrunks"
		trunks.multimesh = trunk_multi
		vegetation_root.add_child(trunks)
		var crowns := MultiMeshInstance3D.new()
		crowns.name = "TreeCrowns"
		crowns.multimesh = crown_multi
		vegetation_root.add_child(crowns)

	if not rocks.is_empty():
		var rock_mesh := SphereMesh.new()
		rock_mesh.radial_segments = 6
		rock_mesh.rings = 3
		rock_mesh.radius = 0.72
		rock_mesh.height = 1.25
		rock_mesh.material = _mat(biome.get("rock_color", Color("706d72")), TEX_STONE)
		var rock_multi := MultiMesh.new()
		rock_multi.transform_format = MultiMesh.TRANSFORM_3D
		rock_multi.mesh = rock_mesh
		rock_multi.instance_count = rocks.size()
		for i in range(rocks.size()):
			var rock: Dictionary = rocks[i] as Dictionary
			var pos: Vector3 = rock.get("position", Vector3.ZERO)
			var scale_value: Vector3 = rock.get("scale", Vector3.ONE)
			var rotation_y: float = float(rock.get("rotation_y", 0.0))
			var basis := Basis(Vector3.UP, rotation_y).scaled(scale_value)
			rock_multi.set_instance_transform(i, Transform3D(basis, pos))
		var rock_instances := MultiMeshInstance3D.new()
		rock_instances.name = "Rocks"
		rock_instances.multimesh = rock_multi
		vegetation_root.add_child(rock_instances)

func _build_pois(root: Node3D, data: Dictionary, biome: Dictionary) -> void:
	var pois_value: Variant = data.get("pois", [])
	if not pois_value is Array:
		return
	var pois: Array = pois_value as Array
	var poi_root := Node3D.new()
	poi_root.name = "GeneratedPOIs"
	root.add_child(poi_root)
	for value in pois:
		if not value is Dictionary:
			continue
		var poi: Dictionary = value as Dictionary
		var node := Node3D.new()
		node.name = str(poi.get("id", "poi")).replace(":", "_")
		node.position = poi.get("position", Vector3.ZERO)
		node.rotation.y = float(poi.get("rotation_y", 0.0))
		node.set_meta("poi_id", str(poi.get("id", "")))
		node.set_meta("display_name", str(poi.get("display_name", "Unknown Place")))
		node.add_to_group("generated_poi")
		poi_root.add_child(node)
		var poi_type: String = str(poi.get("type", "minor_ruin"))
		match poi_type:
			"camp":
				_build_camp(node, biome)
			"cave":
				_build_cave(node, biome)
			"secret":
				_build_secret(node, biome)
			"grave_site":
				_build_graves(node, biome)
			_:
				_build_minor_ruin(node, biome)

func _build_loot(root: Node3D, data: Dictionary, biome: Dictionary) -> void:
	var loot_value: Variant = data.get("loot", [])
	if not loot_value is Array:
		return
	var loot_root := Node3D.new()
	loot_root.name = "GeneratedLoot"
	root.add_child(loot_root)
	for value in loot_value:
		if not value is Dictionary:
			continue
		var loot: Dictionary = value as Dictionary
		var persistent_id: String = str(loot.get("id", ""))
		if _entity_state_bool(persistent_id, "collected"):
			continue
		var area := Area3D.new()
		area.position = loot.get("position", Vector3.ZERO)
		area.set_script(GENERATED_LOOT_SCRIPT)
		area.set("item_name", str(loot.get("item_name", "Ancient Coin")))
		area.set("amount", int(loot.get("amount", 1)))
		area.set("persistent_id", persistent_id)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.42, 0.42, 0.42)
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _mat(biome.get("accent", Color("a9b3ff")), TEX_METAL, 0.35)
		area.add_child(mesh_instance)
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.65
		collision.shape = shape
		area.add_child(collision)
		loot_root.add_child(area)

func _build_encounters(root: Node3D, data: Dictionary, biome: Dictionary) -> void:
	var encounters_value: Variant = data.get("encounters", [])
	if not encounters_value is Array:
		return
	var encounters: Array = encounters_value as Array
	var encounter_root := Node3D.new()
	encounter_root.name = "GeneratedEncounters"
	root.add_child(encounter_root)
	for value in encounters:
		if not value is Dictionary:
			continue
		var encounter: Dictionary = value as Dictionary
		var entity_id: String = str(encounter.get("id", ""))
		if _entity_state_bool(entity_id, "dead"):
			continue
		_spawn_enemy(encounter_root, encounter, biome)

func _spawn_enemy(parent: Node3D, encounter: Dictionary, biome: Dictionary) -> void:
	var enemy := CharacterBody3D.new()
	enemy.name = str(encounter.get("id", "generated_enemy")).replace(":", "_")
	enemy.position = encounter.get("position", Vector3.ZERO)
	enemy.set_script(ENEMY_SCRIPT)
	enemy.set("persistent_id", str(encounter.get("id", "")))
	var profile: String = str(encounter.get("profile", "warden_patrol"))
	match profile:
		"blackwood_ambush":
			enemy.set("enemy_name", "Blackwood Stalker")
			enemy.set("move_speed", 3.0)
			enemy.set("max_health", 38)
			enemy.set("attack_damage", 11)
		"restless_dead":
			enemy.set("enemy_name", "Pale Warden")
			enemy.set("move_speed", 2.1)
			enemy.set("max_health", 58)
			enemy.set("attack_damage", 15)
		"highland_guardians":
			enemy.set("enemy_name", "Highland Sentinel")
			enemy.set("move_speed", 2.5)
			enemy.set("max_health", 70)
			enemy.set("attack_damage", 17)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.85
	collision.shape = capsule
	collision.position.y = 0.92
	enemy.add_child(collision)
	_build_enemy_visual(enemy, biome)
	parent.add_child(enemy)

func _build_enemy_visual(enemy: CharacterBody3D, biome: Dictionary) -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	enemy.add_child(visual)
	var body_color: Color = biome.get("rock_color", Color("555861"))
	var cape_color: Color = biome.get("tree_leaf", Color("24232f")).darkened(0.35)
	var accent: Color = biome.get("accent", Color("9ca8ff"))
	_mesh_box(visual, "Torso", Vector3(0, 1.28, 0), Vector3(0.78, 0.92, 0.46), body_color, TEX_METAL)
	_mesh_box(visual, "Hips", Vector3(0, 0.70, 0), Vector3(0.62, 0.30, 0.40), body_color.darkened(0.2), TEX_CLOTH)
	_mesh_sphere(visual, "Head", Vector3(0, 1.94, 0), 0.27, body_color.lightened(0.12), TEX_METAL)
	_mesh_cylinder(visual, "ArmL", Vector3(-0.48, 1.18, 0), 0.78, 0.14, body_color, Vector3(0, 0, -7), TEX_METAL)
	_mesh_cylinder(visual, "ArmR", Vector3(0.48, 1.18, 0), 0.78, 0.14, body_color, Vector3(0, 0, 7), TEX_METAL)
	_mesh_cylinder(visual, "LegL", Vector3(-0.21, 0.25, 0), 0.90, 0.15, body_color.darkened(0.28), Vector3.ZERO, TEX_CLOTH)
	_mesh_cylinder(visual, "LegR", Vector3(0.21, 0.25, 0), 0.90, 0.15, body_color.darkened(0.28), Vector3.ZERO, TEX_CLOTH)
	_mesh_box(visual, "TatteredCape", Vector3(0, 1.05, 0.27), Vector3(0.78, 1.18, 0.08), cape_color, TEX_CLOTH)
	_mesh_box(visual, "EyeGlow", Vector3(0, 1.98, -0.27), Vector3(0.30, 0.055, 0.04), accent)
	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.54, 1.18, -0.03)
	weapon_pivot.rotation_degrees = Vector3(0, 0, 30)
	visual.add_child(weapon_pivot)
	_mesh_box(weapon_pivot, "Blade", Vector3(0, 0.60, 0), Vector3(0.11, 1.20, 0.08), body_color.lightened(0.3), TEX_METAL)

func _build_minor_ruin(parent: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("68666d"))
	_add_static_box(parent, Vector3(-2.2, 1.25, 0), Vector3(1.1, 2.5, 1.1), stone, TEX_STONE)
	_add_static_box(parent, Vector3(2.2, 1.65, 0.4), Vector3(1.1, 3.3, 1.1), stone.darkened(0.08), TEX_STONE)
	_add_static_box(parent, Vector3(0.2, 0.65, -1.6), Vector3(4.2, 1.3, 0.8), stone.darkened(0.14), TEX_STONE)

func _build_camp(parent: Node3D, biome: Dictionary) -> void:
	var wood: Color = biome.get("tree_trunk", Color("5b3826"))
	var accent: Color = biome.get("accent", Color("d2b06d"))
	for angle in [-0.55, 0.55]:
		var log := _mesh_cylinder(parent, "CampLog", Vector3(sin(angle) * 0.5, 0.20, cos(angle) * 0.5), 2.1, 0.14, wood, Vector3(90, rad_to_deg(angle), 0), TEX_BARK)
		log.position.y = 0.20
	var flame := _mesh_sphere(parent, "ColdFire", Vector3(0, 0.48, 0), 0.24, accent)
	flame.scale = Vector3(0.75, 1.35, 0.75)
	_add_static_box(parent, Vector3(2.2, 0.55, -1.2), Vector3(2.0, 1.1, 1.1), wood.darkened(0.18), TEX_BARK)

func _build_cave(parent: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("56545f"))
	_add_static_box(parent, Vector3(-2.0, 1.6, 0), Vector3(2.2, 3.2, 2.8), stone, TEX_STONE)
	_add_static_box(parent, Vector3(2.0, 1.6, 0), Vector3(2.2, 3.2, 2.8), stone.darkened(0.05), TEX_STONE)
	_add_static_box(parent, Vector3(0, 3.25, 0), Vector3(5.8, 1.1, 2.8), stone.darkened(0.10), TEX_STONE)
	var mouth := _mesh_box(parent, "CaveMouth", Vector3(0, 1.35, 0.75), Vector3(2.2, 2.7, 0.18), Color("090a12"))
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_secret(parent: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("625f70"))
	var accent: Color = biome.get("accent", Color("9ca8ff"))
	for i in range(5):
		var angle: float = TAU * float(i) / 5.0
		_add_static_box(parent, Vector3(cos(angle) * 2.6, 0.9, sin(angle) * 2.6), Vector3(0.7, 1.8, 0.7), stone, TEX_STONE)
	var orb := _mesh_sphere(parent, "SecretGlow", Vector3(0, 1.1, 0), 0.36, accent)
	orb.scale = Vector3(1, 1.2, 1)

func _build_graves(parent: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("5e5b6d"))
	for i in range(4):
		var x: float = -2.4 + float(i) * 1.6
		var grave := _add_static_box(parent, Vector3(x, 0.75, sin(float(i)) * 0.6), Vector3(0.7, 1.5, 0.28), stone.darkened(float(i) * 0.03), TEX_STONE)
		grave.rotation_degrees.y = float(i - 2) * 8.0

func _scan_poi_discovery() -> void:
	var player := _get_player()
	if player == null:
		return
	for node in get_tree().get_nodes_in_group("generated_poi"):
		if not node is Node3D or not is_instance_valid(node):
			continue
		var poi_node := node as Node3D
		var poi_id: String = str(poi_node.get_meta("poi_id", ""))
		if poi_id.is_empty() or _flag_value("discovered:%s" % poi_id):
			continue
		if player.global_position.distance_to(poi_node.global_position) <= 8.5:
			_set_flag("discovered:%s" % poi_id, true)
			_show_discovery(str(poi_node.get_meta("display_name", "Unknown Place")))

func _show_discovery(display_name: String) -> void:
	if discovery_card == null or discovery_label == null:
		return
	if discovery_tween != null and discovery_tween.is_valid():
		discovery_tween.kill()
	discovery_label.text = "DISCOVERED — %s\nGenerated from world seed %d" % [display_name, _world_seed()]
	discovery_card.modulate = Color.WHITE
	discovery_card.visible = true
	discovery_tween = create_tween()
	discovery_tween.tween_interval(2.4)
	discovery_tween.tween_property(discovery_card, "modulate", Color(1, 1, 1, 0), 0.8)
	discovery_tween.tween_callback(_hide_discovery)

func _hide_discovery() -> void:
	if discovery_card != null:
		discovery_card.visible = false

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 129
	status_label = Label.new()
	status_label.position = Vector2(322, 42)
	status_label.size = Vector2(308, 18)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", 9)
	layer.add_child(status_label)

	discovery_card = ColorRect.new()
	discovery_card.position = Vector2(145, 170)
	discovery_card.size = Vector2(350, 54)
	discovery_card.color = Color(0.025, 0.018, 0.055, 0.90)
	discovery_card.visible = false
	discovery_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(discovery_card)
	discovery_label = Label.new()
	discovery_label.position = Vector2(10, 6)
	discovery_label.size = Vector2(330, 42)
	discovery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discovery_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discovery_label.add_theme_font_size_override("font_size", 10)
	discovery_card.add_child(discovery_label)
	world.add_child(layer)

func _refresh_status() -> void:
	if status_label == null or job_queue == null:
		return
	var root_count: int = get_tree().get_nodes_in_group("generated_exploration_root").size()
	var pending: int = int(job_queue.call("pending_count"))
	var batch_msec: float = float(job_queue.get("last_batch_msec"))
	status_label.text = "Seed %d • gen %d • queue %d • rejected %d • %.1f ms" % [
		configured_world_seed,
		root_count,
		pending,
		rejected_content_batches,
		max(last_build_msec, batch_msec)
	]

func _get_player() -> Node3D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty() or not players[0] is Node3D:
		return null
	return players[0] as Node3D

func _world_seed() -> int:
	if world_state != null:
		return int(world_state.get("world_seed"))
	return DEFAULT_WORLD_SEED

func _normalized_seed(seed_value: int) -> int:
	var normalized: int = int(seed_value & 0x7fffffff)
	return normalized if normalized > 0 else DEFAULT_WORLD_SEED

func _entity_state_bool(entity_id: String, key: String) -> bool:
	if entity_id.is_empty() or world_state == null or not world_state.has_method("get_entity_state"):
		return false
	var state_value: Variant = world_state.call("get_entity_state", entity_id)
	if state_value is Dictionary:
		return bool((state_value as Dictionary).get(key, false))
	return false

func _flag_value(flag_id: String) -> bool:
	if world_state != null and world_state.has_method("get_flag"):
		return bool(world_state.call("get_flag", flag_id, false))
	return false

func _set_flag(flag_id: String, value: bool) -> void:
	if world_state != null and world_state.has_method("set_flag"):
		world_state.call("set_flag", flag_id, value)

func _mat(color: Color, texture: Texture2D = null, roughness: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if texture != null:
		material.albedo_texture = texture
	return material

func _add_static_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, texture)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func _mesh_box(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = pos
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, texture)
	parent.add_child(mesh_instance)
	return mesh_instance

func _mesh_cylinder(parent: Node3D, node_name: String, pos: Vector3, height: float, radius: float, color: Color, rotation: Vector3 = Vector3.ZERO, texture: Texture2D = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rotation
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.height = height
	mesh.top_radius = radius * 0.75
	mesh.bottom_radius = radius
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, texture)
	parent.add_child(mesh_instance)
	return mesh_instance

func _mesh_sphere(parent: Node3D, node_name: String, pos: Vector3, radius: float, color: Color, texture: Texture2D = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = pos
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color, texture, 0.35)
	parent.add_child(mesh_instance)
	return mesh_instance
