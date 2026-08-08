extends StaticBody3D

@export var required_item: String = "Old Key"
@export var door_name: String = "Whispering Crypt Gate"

var unlocked: bool = false

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	if unlocked:
		return

	var inventory_value: Variant = player.get("inventory")
	if typeof(inventory_value) != TYPE_DICTIONARY:
		_show_status(player, "The lock does not respond.")
		return

	var inventory: Dictionary = inventory_value
	var amount: int = int(inventory.get(required_item, 0))
	if amount <= 0:
		_show_status(player, "Locked — requires %s" % required_item)
		return

	amount -= 1
	if amount <= 0:
		inventory.erase(required_item)
	else:
		inventory[required_item] = amount
	player.set("inventory", inventory)
	if player.has_method("_refresh_hud"):
		player.call("_refresh_hud")

	unlocked = true
	remove_from_group("interactable")
	_show_status(player, "%s unlocked" % door_name)

	var tween: Tween = create_tween()
	tween.tween_property(self, "position:y", position.y + 4.2, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func get_interaction_text() -> String:
	if unlocked:
		return ""
	return "E  Unlock %s" % door_name

func _show_status(player: Node, text: String) -> void:
	if player.has_method("_set_status"):
		player.call("_set_status", text)
