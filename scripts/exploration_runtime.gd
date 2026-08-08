extends "res://scripts/exploration_system.gd"

# Compatibility wrapper for the original authored exploration prototype.
# Its crypt/camp/grove helpers build presentation meshes eagerly. Headless and
# dedicated-server runtimes use the deterministic ProceduralExplorationSystem
# for authoritative exploration state and therefore skip this legacy client layer.
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	super._ready()
