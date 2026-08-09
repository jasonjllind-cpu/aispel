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
	_build_ground()
	_spawn_player()
	_build_retro_postprocess()
	_build_hud()

func _install_runtime_performance_monitor() -> void:
	if has_node("RuntimePerformanceMonitor"):
		return
	var monitor := Node.new()
	monitor.name = "RuntimePerformanceMonitor"
	monitor.set_script(RUNTIME_PERFORMANCE_MONITOR)
	add_child(monitor)
