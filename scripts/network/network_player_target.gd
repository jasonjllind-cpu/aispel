extends Node3D
class_name NetworkPlayerTarget

@export var peer_id: int = 0

func _ready() -> void:
	add_to_group("network_player_target")
	if peer_id > 0:
		set_meta("stable_id", "player:peer:%d" % peer_id)

func receive_damage(amount: int) -> void:
	if amount <= 0 or peer_id <= 0 or get_tree() == null:
		return
	var systems: Array[Node] = get_tree().get_nodes_in_group("network_combat_authority")
	if systems.is_empty():
		return
	var system: Node = systems[0]
	if system.has_method("damage_player"):
		system.call("damage_player", peer_id, amount)
