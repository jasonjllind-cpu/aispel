extends "res://scripts/enemy.gd"
class_name DungeonBossActor

@export var boss_id: String = "hollow_king"
@export var dungeon_id: String = "moon_catacombs"
@export var boss_title: String = "The Hollow King"

var enraged: bool = false

func _ready() -> void:
	enemy_name = boss_title
	persistent_id = "boss:%s" % boss_id
	max_health = max(max_health, 180)
	move_speed = max(move_speed, 2.6)
	detection_range = max(detection_range, 24.0)
	attack_damage = max(attack_damage, 22)
	attack_cooldown = min(attack_cooldown, 0.95)
	super._ready()
	add_to_group("boss")

func receive_damage(amount: int, attacker: Node = null) -> void:
	super.receive_damage(amount, attacker)
	if dead or enraged:
		return
	if health <= int(round(float(max_health) * 0.5)):
		enraged = true
		move_speed *= 1.22
		attack_damage += 5
		attack_cooldown = max(0.62, attack_cooldown * 0.78)
		var visual := get_node_or_null("Visual") as Node3D
		if visual != null:
			var tween := create_tween()
			tween.tween_property(visual, "scale", Vector3(1.12, 1.12, 1.12), 0.18)

func _die() -> void:
	if dead:
		return
	var systems: Array[Node] = get_tree().get_nodes_in_group("dungeon_system")
	if not systems.is_empty():
		var system: Node = systems[0]
		if system.has_method("on_boss_defeated"):
			system.call("on_boss_defeated", dungeon_id, boss_id, global_position)
	super._die()
