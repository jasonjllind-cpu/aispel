extends "res://scripts/world/procedural_exploration_system.gd"

func _build_vegetation(root: Node3D, data: Dictionary, biome: Dictionary) -> void:
	# Dedicated/headless runtimes own world state and gameplay, but do not need
	# cosmetic MultiMesh vegetation. Keeping this boundary explicit avoids
	# renderer-only work on future dedicated servers and keeps CI deterministic.
	if DisplayServer.get_name() == "headless":
		return
	super._build_vegetation(root, data, biome)
