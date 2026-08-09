extends "res://scripts/world.gd"

const RUNTIME_PERFORMANCE_MONITOR := preload("res://scripts/core/runtime_performance_monitor.gd")
const WORLD_GENERATOR_SCRIPT := preload("res://scripts/world/world_generator.gd")
const REGION_CATALOG := preload("res://scripts/world/region_catalog.gd")

const PLAYER_SURFACE_TOLERANCE: float = 0.12
const PLAYER_RECOVERY_CLEARANCE: float = 0.12
const PLAYER_SPAWN_CLEARANCE: float = 0.08
const PLAYER_RECOVERY_INTERVAL: float = 0.25
const PLAYER_EMERGENCY_RECOVERY_DEPTH: float = 1.0

var player_recovery_elapsed: float = 0.0
var player_recovery_armed: bool = true
var terrain_height_generator: RefCounted
var terrain_height_seed: int = 0

# The playable client now uses the procedural systems in main.tscn as the
# authoritative visible world. Keep only presentation, a safety floor, the
# player and HUD from the original hand-authored prototype.
#
# ProceduralWorldSystem creates seed-driven terrain. ProceduralExplorationSystem
# creates the road, vegetation, POIs, encounters and loot. Avoiding
# super._ready() prevents the old fixed map from being built on top of them.
func _ready() -> void:
	_install_runtime_performance_monitor()
	if DisplayServer.get_name() == "headless":
		return
	_build_environment()
	_build_safety_floor()
	_build_retro_postprocess()
	_build_hud()
	call_deferred("_spawn_player_when_terrain_ready")


func _spawn_player_when_terrain_ready() -> void:
	var terrain_system := get_node_or_null("ProceduralWorldSystem")
	if terrain_system != null and terrain_system.has_signal("starting_terrain_ready"):
		var terrain_ready: bool = (
			terrain_system.has_method("is_starting_terrain_ready")
			and bool(terrain_system.call("is_starting_terrain_ready"))
		)
		if not terrain_ready:
			await Signal(terrain_system, &"starting_terrain_ready")
	if not has_node("Player"):
		_spawn_player()


func _spawn_player() -> void:
	super._spawn_player()
	var player := get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return
	var safe_spawn: Vector3 = generated_player_spawn_position(_active_world_seed())
	player.position = safe_spawn
	# Player._ready() runs inside super._spawn_player() and records the old
	# prototype position. Replace that checkpoint after applying the generated
	# terrain height so death/respawn cannot return below the map.
	player.set("spawn_position", player.global_position)
	player.set("velocity", Vector3.ZERO)


func generated_player_spawn_position(seed_value: int) -> Vector3:
	var region: Dictionary = REGION_CATALOG.get_region("starting_valley")
	var center: Vector3 = region.get("center", Vector3.ZERO)
	var biome_id: String = str(region.get("biome", "green_highlands"))
	var slots: Array[Dictionary] = REGION_CATALOG.get_slots("starting_valley")
	var spawn_local := Vector2(0, 24)
	for slot in slots:
		if str(slot.get("id", "")) == "player_spawn":
			spawn_local = slot.get("center", spawn_local)
			break
	var generator: RefCounted = WORLD_GENERATOR_SCRIPT.new()
	generator.call("configure", seed_value)
	var terrain_height: float = float(generator.call(
		"sample_mesh_height_at",
		center,
		biome_id,
		spawn_local,
		slots,
		"starting_valley"
	))
	return Vector3(
		center.x + spawn_local.x,
		center.y + terrain_height + PLAYER_SPAWN_CLEARANCE,
		center.z + spawn_local.y
	)


func _active_world_seed() -> int:
	var world_state := get_node_or_null("/root/WorldState")
	if world_state != null:
		return int(world_state.get("world_seed"))
	return 8242601


func sanitize_outdoor_player_position(candidate: Vector3, seed_value: int = 0) -> Vector3:
	if seed_value <= 0 and _dungeon_active():
		return candidate
	var resolved_seed: int = seed_value if seed_value > 0 else _active_world_seed()
	var surface: Dictionary = generated_surface_sample(candidate, resolved_seed)
	if surface.is_empty():
		return candidate
	var terrain_y: float = float(surface.get("height", candidate.y))
	if candidate.y >= terrain_y - PLAYER_SURFACE_TOLERANCE:
		return candidate
	return Vector3(candidate.x, terrain_y + PLAYER_RECOVERY_CLEARANCE, candidate.z)


func generated_surface_sample(world_position: Vector3, seed_value: int) -> Dictionary:
	var closest_region_id := ""
	var closest_distance: float = INF
	for region_id in REGION_CATALOG.get_region_ids():
		var region: Dictionary = REGION_CATALOG.get_region(region_id)
		var center: Vector3 = region.get("center", Vector3.ZERO)
		var distance: float = Vector2(world_position.x - center.x, world_position.z - center.z).length()
		if distance < closest_distance:
			closest_distance = distance
			closest_region_id = region_id
	if closest_region_id.is_empty():
		return {}

	var closest_region: Dictionary = REGION_CATALOG.get_region(closest_region_id)
	var radius: float = max(24.0, float(closest_region.get("radius", 62.0)))
	if closest_distance > radius * 1.35:
		return {}
	var center: Vector3 = closest_region.get("center", Vector3.ZERO)
	var biome_id: String = str(closest_region.get("biome", "green_highlands"))
	var local_position := Vector2(world_position.x - center.x, world_position.z - center.z)
	var generator: RefCounted = _terrain_generator_for_seed(seed_value)
	var terrain_height: float = float(generator.call(
		"sample_mesh_height_at",
		center,
		biome_id,
		local_position,
		REGION_CATALOG.get_slots(closest_region_id),
		closest_region_id
	))
	return {
		"region_id": closest_region_id,
		"height": center.y + terrain_height
	}


func _terrain_generator_for_seed(seed_value: int) -> RefCounted:
	if terrain_height_generator == null:
		terrain_height_generator = WORLD_GENERATOR_SCRIPT.new()
	if terrain_height_seed != seed_value:
		terrain_height_seed = seed_value
		terrain_height_generator.call("configure", terrain_height_seed)
	return terrain_height_generator


func _physics_process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player_recovery_elapsed += delta
	if player_recovery_elapsed < PLAYER_RECOVERY_INTERVAL:
		return
	player_recovery_elapsed = 0.0
	if _dungeon_active():
		return
	var player := get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return
	var surface: Dictionary = generated_surface_sample(player.global_position, _active_world_seed())
	if not surface.is_empty():
		var terrain_y: float = float(surface.get("height", player.global_position.y))
		if player.is_on_floor() and player.global_position.y >= terrain_y - PLAYER_SURFACE_TOLERANCE:
			player_recovery_armed = true
	var corrected: Vector3 = sanitize_outdoor_player_position(player.global_position)
	if not consume_emergency_recovery(player.global_position, corrected):
		return
	player.global_position = corrected
	player.set("spawn_position", corrected)
	player.set("velocity", Vector3.ZERO)


func consume_emergency_recovery(current: Vector3, corrected: Vector3) -> bool:
	if not player_recovery_armed or not should_apply_emergency_recovery(current, corrected):
		return false
	# Recovery is edge-triggered. It may fire once after a real fall-through,
	# then stays disarmed until normal floor contact is established.
	player_recovery_armed = false
	return true


func should_apply_emergency_recovery(current: Vector3, corrected: Vector3) -> bool:
	# Ordinary floor contact on a faceted slope can place the capsule root a
	# few centimeters below the vertical surface sample. Never teleport for
	# that; only recover an unmistakable fall through the terrain.
	return corrected.y - current.y >= PLAYER_EMERGENCY_RECOVERY_DEPTH


func _dungeon_active() -> bool:
	var dungeon_system := get_node_or_null("DungeonSystem")
	if dungeon_system == null:
		return false
	var value: Variant = dungeon_system.get("active_dungeon_id")
	return value != null and not str(value).is_empty()


func _build_safety_floor() -> void:
	# A hidden fallback below generated terrain catches the player only if a
	# terrain chunk has not finished building yet.
	_add_static_box(self, Vector3(0, -6.0, 0), Vector3(230, 8.0, 230), Color("171722"))

func _install_runtime_performance_monitor() -> void:
	if has_node("RuntimePerformanceMonitor"):
		return
	var monitor := Node.new()
	monitor.name = "RuntimePerformanceMonitor"
	monitor.set_script(RUNTIME_PERFORMANCE_MONITOR)
	add_child(monitor)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	var seed_value: int = 8242601
	var world_state := get_node_or_null("/root/WorldState")
	if world_state != null:
		seed_value = int(world_state.get("world_seed"))
	label.text = "WASD move  •  Shift run  •  G world seed  •  Seed %d" % seed_value
	label.position = Vector2(8, 6)
	label.size = Vector2(624, 16)
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 8)
	layer.add_child(label)
	add_child(layer)
