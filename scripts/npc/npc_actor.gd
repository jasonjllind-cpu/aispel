extends StaticBody3D
class_name NPCActor

const NPC_CATALOG := preload("res://scripts/npc/npc_catalog.gd")

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
	var attitude: String = _faction_attitude()
	if attitude == "Neutral" or attitude.is_empty():
		return "[E] Talk — %s" % display_name
	return "[E] Talk — %s [%s]" % [display_name, attitude]

func interact(player: Node) -> void:
	var systems: Array[Node] = get_tree().get_nodes_in_group("npc_system")
	if systems.is_empty():
		return
	var system: Node = systems[0]
	if system.has_method("begin_conversation"):
		system.call("begin_conversation", npc_id, player)

func _faction_attitude() -> String:
	var definition: Dictionary = NPC_CATALOG.get_npc(npc_id)
	var faction_id: String = str(definition.get("faction_id", ""))
	if faction_id.is_empty():
		return "Neutral"
	var systems: Array[Node] = get_tree().get_nodes_in_group("faction_system")
	if systems.is_empty():
		return "Neutral"
	var system: Node = systems[0]
	if system.has_method("get_attitude"):
		return str(system.call("get_attitude", faction_id))
	return "Neutral"
