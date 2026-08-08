extends StaticBody3D
class_name MerchantStall

@export var merchant_id: String = "":
	set(value):
		merchant_id = value
		_sync_stable_id()
@export var display_name: String = "Merchant"

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("merchant_stall")
	_sync_stable_id()

func _sync_stable_id() -> void:
	if merchant_id.is_empty():
		remove_meta("stable_id")
		return
	set_meta("stable_id", "merchant:%s" % merchant_id)

func get_interaction_text() -> String:
	return "[E] Trade — %s" % display_name

func interact(player: Node) -> void:
	var systems: Array[Node] = get_tree().get_nodes_in_group("merchant_system")
	if systems.is_empty():
		return
	var system: Node = systems[0]
	if system.has_method("open_merchant"):
		system.call("open_merchant", merchant_id, player)
