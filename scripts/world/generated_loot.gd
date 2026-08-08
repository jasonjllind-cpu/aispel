extends Area3D
class_name GeneratedLoot

@export var item_name: String = "Ancient Coin"
@export var amount: int = 1
@export var persistent_id: String = ""
@export var spin_speed: float = 1.1

var collected: bool = false
var base_y: float = 0.0
var hover_time: float = 0.0

func _ready() -> void:
	if _was_collected():
		queue_free()
		return
	add_to_group("interactable")
	base_y = position.y
	hover_time = abs(global_position.x * 0.11 + global_position.z * 0.09)

func _process(delta: float) -> void:
	if collected:
		return
	hover_time += delta
	rotate_y(spin_speed * delta)
	position.y = base_y + sin(hover_time * 2.0) * 0.08

func interact(player: Node) -> void:
	if collected:
		return
	collected = true
	if player.has_method("receive_loot"):
		player.call("receive_loot", item_name, amount)
	_record_collected()
	queue_free()

func get_interaction_text() -> String:
	return "E  Pick up %s" % item_name

func _was_collected() -> bool:
	if persistent_id.is_empty():
		return false
	var world_state := get_node_or_null("/root/WorldState")
	if world_state == null or not world_state.has_method("get_entity_state"):
		return false
	var state_value: Variant = world_state.call("get_entity_state", persistent_id)
	if state_value is Dictionary:
		return bool((state_value as Dictionary).get("collected", false))
	return false

func _record_collected() -> void:
	if persistent_id.is_empty():
		return
	var world_state := get_node_or_null("/root/WorldState")
	if world_state != null and world_state.has_method("set_entity_state"):
		world_state.call("set_entity_state", persistent_id, {"collected": true})
