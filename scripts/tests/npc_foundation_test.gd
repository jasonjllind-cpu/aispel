extends SceneTree

const NPC_CATALOG := preload("res://scripts/npc/npc_catalog.gd")
const NPC_SYSTEM_SCRIPT := preload("res://scripts/npc/npc_system.gd")

func _init() -> void:
	var failed := false
	failed = not _test_catalog() or failed
	failed = not _test_headless_actor_spawn() or failed
	if failed:
		printerr("NPC_FOUNDATION_FAILED")
		quit(1)
		return
	print("NPC_FOUNDATION_OK npcs=%d" % NPC_CATALOG.get_npc_ids().size())
	quit(0)

func _test_catalog() -> bool:
	var ids: Array[String] = NPC_CATALOG.get_npc_ids()
	if ids.size() < 5:
		printerr("NPC catalog unexpectedly small: %d" % ids.size())
		return false
	for npc_id in ids:
		var definition: Dictionary = NPC_CATALOG.get_npc(npc_id)
		if str(definition.get("id", "")) != npc_id:
			printerr("NPC catalog ID mismatch for %s" % npc_id)
			return false
		if str(definition.get("display_name", "")).is_empty():
			printerr("NPC display name missing for %s" % npc_id)
			return false
		if str(definition.get("region_id", "")).is_empty():
			printerr("NPC region missing for %s" % npc_id)
			return false
	var elowen: Dictionary = NPC_CATALOG.get_npc("elowen_wayfinder")
	var quest_value: Variant = elowen.get("quest", {})
	if not quest_value is Dictionary:
		printerr("Elowen quest definition missing")
		return false
	var quest: Dictionary = quest_value as Dictionary
	if str(quest.get("id", "")) != "whispers_in_blackwood":
		printerr("Expected starter quest is missing")
		return false
	if str(quest.get("objective_type", "")) != "discover_region" or str(quest.get("objective_id", "")) != "blackwood":
		printerr("Starter quest objective is invalid")
		return false
	return true

func _test_headless_actor_spawn() -> bool:
	var world := Node3D.new()
	world.name = "TestWorld"
	get_root().add_child(world)
	var system := Node.new()
	system.set_script(NPC_SYSTEM_SCRIPT)
	world.add_child(system)
	system.set("world", world)
	system.call("_spawn_region_npcs", world, "starting_valley", "NPCsStartingValley")
	var root := world.get_node_or_null("NPCsStartingValley") as Node3D
	if root == null:
		printerr("Starting valley NPC root was not created")
		world.queue_free()
		return false
	var definitions: Array[Dictionary] = NPC_CATALOG.get_region_npcs("starting_valley")
	if root.get_child_count() != definitions.size():
		printerr("Starting valley NPC count mismatch: %d != %d" % [root.get_child_count(), definitions.size()])
		world.queue_free()
		return false
	for definition in definitions:
		var npc_id: String = str(definition.get("id", ""))
		var actor := root.get_node_or_null("NPC_%s" % npc_id)
		if actor == null:
			printerr("NPC actor missing for %s" % npc_id)
			world.queue_free()
			return false
		if str(actor.get_meta("stable_id", "")) != "npc:%s" % npc_id:
			printerr("Stable NPC ID mismatch for %s" % npc_id)
			world.queue_free()
			return false
		if actor.get_node_or_null("CollisionShape3D") == null:
			printerr("NPC collision missing for %s" % npc_id)
			world.queue_free()
			return false
		if DisplayServer.get_name() == "headless" and actor.get_node_or_null("Visual") != null:
			printerr("NPC visual leaked into headless runtime for %s" % npc_id)
			world.queue_free()
			return false
	world.queue_free()
	return true
