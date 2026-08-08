extends Area3D
class_name DungeonPortal

@export var dungeon_id: String = ""
@export_enum("enter", "exit") var portal_mode: String = "enter"
@export var display_name: String = "Dungeon"

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("dungeon_portal")
	_sync_stable_id()

func _sync_stable_id() -> void:
	if dungeon_id.is_empty():
		return
	set_meta("stable_id", "portal:%s:%s" % [dungeon_id, portal_mode])

func get_interaction_text() -> String:
	if portal_mode == "exit":
		return "[E] Leave %s" % display_name
	return "[E] Enter %s" % display_name

func interact(player: Node) -> void:
	var systems: Array[Node] = get_tree().get_nodes_in_group("dungeon_system")
	if systems.is_empty():
		return
	var system: Node = systems[0]
	if portal_mode == "exit" and system.has_method("exit_dungeon"):
		system.call("exit_dungeon", dungeon_id, player)
	elif portal_mode == "enter" and system.has_method("enter_dungeon"):
		system.call("enter_dungeon", dungeon_id, player)
