extends "res://scripts/world.gd"

const RUNTIME_PERFORMANCE_MONITOR := preload("res://scripts/core/runtime_performance_monitor.gd")

# Runtime boundary for the legacy hand-authored starting scene.
#
# The visual prototype in world.gd intentionally builds many PrimitiveMesh nodes.
# Those are client presentation only and the Godot dummy renderer used by
# headless/dedicated-server runtimes cannot consume them safely. Procedural world,
# exploration state, collision and persistence live in separate child systems and
# still initialise normally when this legacy presentation layer is skipped.
func _ready() -> void:
	_install_runtime_performance_monitor()
	if DisplayServer.get_name() == "headless":
		return
	super._ready()

func _install_runtime_performance_monitor() -> void:
	if has_node("RuntimePerformanceMonitor"):
		return
	var monitor := Node.new()
	monitor.name = "RuntimePerformanceMonitor"
	monitor.set_script(RUNTIME_PERFORMANCE_MONITOR)
	add_child(monitor)
