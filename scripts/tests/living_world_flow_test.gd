extends SceneTree

const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const NPC_CATALOG := preload("res://scripts/npc/npc_catalog.gd")
const NPC_SYSTEM_SCRIPT := preload("res://scripts/npc/npc_system.gd")
const FACTION_SYSTEM_SCRIPT := preload("res://scripts/npc/faction_system.gd")
const MERCHANT_SYSTEM_SCRIPT := preload("res://scripts/npc/merchant_system.gd")

class MockPlayer:
	extends Node
	var inventory: Dictionary = {"Ancient Coin": 10}

	func receive_loot(item_name: String, amount: int = 1) -> void:
		inventory[item_name] = int(inventory.get(item_name, 0)) + amount

func _init() -> void:
	var world_state := Node.new()
	world_state.set_script(WORLD_STATE_SCRIPT)
	world_state.name = "FlowWorldState"
	get_root().add_child(world_state)

	var player := MockPlayer.new()
	get_root().add_child(player)

	var npc_system := Node.new()
	npc_system.set_script(NPC_SYSTEM_SCRIPT)
	get_root().add_child(npc_system)
	npc_system.set("world_state", world_state)

	if not _run_quest_flow(npc_system, world_state, player):
		quit(1)
		return

	var faction_system := Node.new()
	faction_system.set_script(FACTION_SYSTEM_SCRIPT)
	get_root().add_child(faction_system)
	faction_system.set("world_state", world_state)
	faction_system.add_to_group("faction_system")
	if not _run_faction_reward_flow(faction_system, world_state):
		quit(1)
		return

	var merchant_system := Node.new()
	merchant_system.set_script(MERCHANT_SYSTEM_SCRIPT)
	get_root().add_child(merchant_system)
	if not _run_merchant_flow(merchant_system, faction_system, player):
		quit(1)
		return

	print("LIVING_WORLD_FLOW_OK quest=whispers_in_blackwood moon_wardens=%d coins=%d" % [
		int(faction_system.call("get_reputation", "moon_wardens")),
		int(player.inventory.get("Ancient Coin", 0))
	])
	quit(0)

func _run_quest_flow(npc_system: Node, world_state: Node, player: MockPlayer) -> bool:
	var elowen: Dictionary = NPC_CATALOG.get_npc("elowen_wayfinder")
	var quest: Dictionary = elowen.get("quest", {})
	var first_lines: Array[String] = npc_system.call("_conversation_lines", elowen, player)
	if first_lines.is_empty():
		return _fail("Elowen produced no starter conversation")
	var state: Dictionary = world_state.call("get_entity_state", "quest:whispers_in_blackwood")
	if str(state.get("status", "")) != "active":
		return _fail("Starter quest was not persisted as active")
	if not bool(world_state.call("mark_region_discovered", "blackwood")):
		return _fail("Blackwood discovery did not register")
	if not bool(npc_system.call("_quest_objective_complete", quest)):
		return _fail("Blackwood discovery did not complete the quest objective")
	var complete_lines: Array[String] = npc_system.call("_conversation_lines", elowen, player)
	if complete_lines.is_empty():
		return _fail("Elowen produced no completion conversation")
	state = world_state.call("get_entity_state", "quest:whispers_in_blackwood")
	if str(state.get("status", "")) != "completed":
		return _fail("Starter quest was not persisted as completed")
	if int(player.inventory.get("Moon Shard", 0)) != 2:
		return _fail("Quest reward was not granted exactly once")
	# Re-opening completed dialogue must not duplicate the item reward.
	npc_system.call("_conversation_lines", elowen, player)
	if int(player.inventory.get("Moon Shard", 0)) != 2:
		return _fail("Completed quest duplicated its item reward")
	return true

func _run_faction_reward_flow(faction_system: Node, world_state: Node) -> bool:
	faction_system.call("_apply_completed_quest_rewards")
	if int(faction_system.call("get_reputation", "moon_wardens")) != 20:
		return _fail("Quest completion did not grant Moon Warden reputation")
	faction_system.call("_apply_completed_quest_rewards")
	if int(faction_system.call("get_reputation", "moon_wardens")) != 20:
		return _fail("Faction reward was applied more than once")
	if not bool(world_state.call("get_flag", "faction_reward:whispers_in_blackwood:moon_wardens", false)):
		return _fail("Faction reward idempotency flag is missing")
	return true

func _run_merchant_flow(merchant_system: Node, faction_system: Node, player: MockPlayer) -> bool:
	merchant_system.set("active_player", player)
	merchant_system.set("active_merchant_id", "orrik_relics")
	merchant_system.call("_buy_offer", 0)
	if int(player.inventory.get("Ancient Coin", 0)) != 7:
		return _fail("Neutral merchant purchase did not remove the expected currency")
	if int(player.inventory.get("Moon Shard", 0)) != 3:
		return _fail("Merchant purchase did not add the purchased item")
	merchant_system.call("_sell_offer", 0)
	if int(player.inventory.get("Ancient Coin", 0)) != 9:
		return _fail("Merchant sale did not add the expected currency")
	if int(player.inventory.get("Moon Shard", 0)) != 2:
		return _fail("Merchant sale did not remove exactly one item")
	faction_system.call("change_reputation", "roadfolk", 40, "flow_test")
	merchant_system.call("_buy_offer", 0)
	if int(player.inventory.get("Ancient Coin", 0)) != 7:
		return _fail("Trusted Roadfolk price was not applied to merchant purchase")
	if int(player.inventory.get("Moon Shard", 0)) != 3:
		return _fail("Trusted merchant purchase did not add its item")
	return true

func _fail(message: String) -> bool:
	printerr("LIVING_WORLD_FLOW_FAILED: %s" % message)
	return false
