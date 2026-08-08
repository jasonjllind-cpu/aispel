extends Area3D

@export var item_name: String = "Ancient Coin"
@export var amount: int = 1
@export var spin_speed: float = 1.25

var collected: bool = false
var base_y: float = 0.0
var hover_time: float = 0.0

func _ready() -> void:
	add_to_group("interactable")
	base_y = position.y
	hover_time = abs(global_position.x * 0.13 + global_position.z * 0.07)

func _process(delta: float) -> void:
	if collected:
		return
	hover_time += delta
	rotate_y(spin_speed * delta)
	position.y = base_y + sin(hover_time * 2.2) * 0.10
	var mesh := get_child(0) as Node3D if get_child_count() > 0 else null
	if mesh != null:
		var pulse: float = 1.0 + sin(hover_time * 3.0) * 0.035
		mesh.scale = Vector3(pulse, pulse, pulse)

func interact(player: Node) -> void:
	if collected:
		return
	collected = true
	if player.has_method("receive_loot"):
		player.call("receive_loot", item_name, amount)
	queue_free()

func get_interaction_text() -> String:
	return "E  Pick up %s" % item_name
