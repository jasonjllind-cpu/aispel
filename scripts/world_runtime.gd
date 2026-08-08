extends "res://scripts/world.gd"

# Runtime boundary for the legacy hand-authored starting scene.
#
# The visual prototype in world.gd intentionally builds many PrimitiveMesh nodes.
# Those are client presentation only and the Godot dummy renderer used by
# headless/dedicated-server runtimes cannot consume them safely. Procedural world,
# exploration state, collision and persistence live in separate child systems and
# still initialise normally when this legacy presentation layer is skipped.
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	super._ready()
