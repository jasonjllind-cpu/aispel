extends "res://scripts/world.gd"

const RUNTIME_PERFORMANCE_MONITOR := preload("res://scripts/core/runtime_performance_monitor.gd")

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
	_spawn_player()
	_build_retro_postprocess()
	_build_hud()

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
