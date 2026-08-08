extends StaticBody3D

@export var item_name: String = "Ancient Coin"
@export var amount: int = 1
@export var chest_name: String = "Old Chest"

var opened: bool = false

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	if opened:
		return
	opened = true
	remove_from_group("interactable")

	if player.has_method("receive_loot"):
		player.call("receive_loot", item_name, amount)

	var lid: Node3D = get_node_or_null("Lid") as Node3D
	if lid != null:
		var tween: Tween = create_tween()
		tween.tween_property(lid, "rotation_degrees:x", -58.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(lid, "position:y", lid.position.y + 0.18, 0.28)

func get_interaction_text() -> String:
	if opened:
		return ""
	return "E  Open %s" % chest_name
