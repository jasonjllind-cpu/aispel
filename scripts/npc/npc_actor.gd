extends StaticBody3D
class_name NPCActor

@export var npc_id: String = "":
	set(value):
		npc_id = value
		_sync_stable_id()
@export var display_name: String = "Unknown Wanderer"
@export var role: String = ""

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npc")
	_sync_stable_id()

func _sync_stable_id() -> void:
	if npc_id.is_empty():
		remove_meta("stable_id")
		return
	set_meta("stable_id", "npc:%s" % npc_id)

func get_interaction_text() -> String:
	return "[E] Talk — %s" % display_name

func interact(player: Node) -> void:
	var systems: Array[Node] = get_tree().get_nodes_in_group("npc_system")
	if systems.is_empty():
		return
	var system: Node = systems[0]
	if system.has_method("begin_conversation"):
		system.call("begin_conversation", npc_id, player)
