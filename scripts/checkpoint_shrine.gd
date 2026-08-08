extends Node3D

@export var checkpoint_name: String = "Moon Shrine"
@export var respawn_offset: Vector3 = Vector3(0, 1.2, 5.0)

var activated: bool = false

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	var checkpoint_position: Vector3 = global_position + respawn_offset
	player.set("spawn_position", checkpoint_position)

	var max_health_value: int = int(player.get("max_health"))
	if max_health_value > 0:
		player.set("health", max_health_value)
	if player.has_method("_refresh_hud"):
		player.call("_refresh_hud")
	if player.has_method("_set_status"):
		player.call("_set_status", "Checkpoint set: %s — health restored" % checkpoint_name)

	activated = true
	var orb: MeshInstance3D = get_node_or_null("CheckpointOrb") as MeshInstance3D
	if orb != null:
		var tween: Tween = create_tween()
		tween.tween_property(orb, "scale", Vector3(1.35, 1.35, 1.35), 0.16)
		tween.tween_property(orb, "scale", Vector3.ONE, 0.32)

func get_interaction_text() -> String:
	return "E  Rest at %s" % checkpoint_name
