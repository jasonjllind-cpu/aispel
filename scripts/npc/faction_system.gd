extends Node
class_name FactionSystem

const NPC_CATALOG := preload("res://scripts/npc/npc_catalog.gd")
const FACTION_CATALOG := preload("res://scripts/npc/faction_catalog.gd")

const SCAN_INTERVAL: float = 0.75

var world_state: Node
var elapsed: float = 0.0

func _ready() -> void:
	add_to_group("faction_system")
	world_state = get_node_or_null("/root/WorldState")
	set_process(world_state != null)
	_apply_completed_quest_rewards()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < SCAN_INTERVAL:
		return
	elapsed = 0.0
	_apply_completed_quest_rewards()

func get_reputation(faction_id: String) -> int:
	if world_state == null or faction_id.is_empty() or not world_state.has_method("get_entity_state"):
		return 0
	var state: Dictionary = world_state.call("get_entity_state", "faction:%s" % faction_id)
	return int(state.get("reputation", 0))

func change_reputation(faction_id: String, amount: int, reason_id: String = "") -> int:
	if world_state == null or faction_id.is_empty() or not world_state.has_method("set_entity_state"):
		return 0
	var value: int = clampi(get_reputation(faction_id) + amount, -100, 100)
	var state := {
		"reputation": value,
		"attitude": FACTION_CATALOG.attitude_for(value),
		"last_reason": reason_id
	}
	world_state.call("set_entity_state", "faction:%s" % faction_id, state)
	return value

func get_attitude(faction_id: String) -> String:
	return FACTION_CATALOG.attitude_for(get_reputation(faction_id))

func get_price_multiplier(faction_id: String) -> float:
	return FACTION_CATALOG.price_multiplier(get_reputation(faction_id))

func _apply_completed_quest_rewards() -> void:
	if world_state == null:
		return
	for npc_id in NPC_CATALOG.get_npc_ids():
		var npc: Dictionary = NPC_CATALOG.get_npc(npc_id)
		var quest_value: Variant = npc.get("quest", {})
		if not quest_value is Dictionary:
			continue
		var quest: Dictionary = quest_value as Dictionary
		var quest_id: String = str(quest.get("id", ""))
		var faction_id: String = str(quest.get("reward_faction", ""))
		var reputation_reward: int = int(quest.get("reward_reputation", 0))
		if quest_id.is_empty() or faction_id.is_empty() or reputation_reward == 0:
			continue
		var quest_state: Dictionary = world_state.call("get_entity_state", "quest:%s" % quest_id)
		if str(quest_state.get("status", "")) != "completed":
			continue
		var reward_flag := "faction_reward:%s:%s" % [quest_id, faction_id]
		if bool(world_state.call("get_flag", reward_flag, false)):
			continue
		change_reputation(faction_id, reputation_reward, "quest:%s" % quest_id)
		world_state.call("set_flag", reward_flag, true)
