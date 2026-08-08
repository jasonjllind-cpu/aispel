extends Area3D

@export var item_name := "Ancient Coin"
@export var amount := 1
@export var spin_speed := 1.25

var collected := false

func _ready() -> void:
	add_to_group("interactable")

func _process(delta: float) -> void:
	if not collected:
		rotate_y(spin_speed * delta)

func interact(player: Node) -> void:
	if collected:
		return
	collected = true
	if player.has_method("receive_loot"):
		player.receive_loot(item_name, amount)
	queue_free()

func get_interaction_text() -> String:
	return "E  Pick up %s" % item_name
