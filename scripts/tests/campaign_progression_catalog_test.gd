extends SceneTree

const CAMPAIGN := preload("res://scripts/progression/campaign_progression_catalog.gd")

func _init() -> void:
	var validation: Dictionary = CAMPAIGN.validate_catalog()
	if not bool(validation.get("valid", false)):
		_fail("Campaign catalog validation failed: %s" % str(validation.get("errors", [])))
		return
	var ids: Array[String] = CAMPAIGN.milestone_ids()
	if ids.size() != 6 or ids != CAMPAIGN.milestone_ids():
		_fail("Campaign milestone IDs are incomplete or non-deterministic")
		return
	if CAMPAIGN.ending_ids() != ["ending:moon_restored", "ending:veil_bound"]:
		_fail("Ending routes are not stable")
		return

	var completed: Array[String] = ["quest:frontier_oath:frontier_crypt"]
	var world_state: Array[String] = []
	if CAMPAIGN.available_milestones(completed, world_state) != ["campaign:frontier_oath"]:
		_fail("Frontier campaign milestone gate is incorrect")
		return
	completed.append("campaign:frontier_oath")
	completed.append("quest:blackwood_pact:blackwood_root_crypt")
	if not CAMPAIGN.available_milestones(completed, world_state).has("campaign:blackwood_pact"):
		_fail("Blackwood campaign milestone did not unlock")
		return
	completed.append("campaign:blackwood_pact")
	if CAMPAIGN.available_milestones(completed, world_state).has("campaign:convergence"):
		_fail("Convergence bypassed world milestone gate")
		return
	world_state.append("world_milestone:windscar_beacon")
	if not CAMPAIGN.available_milestones(completed, world_state).has("campaign:convergence"):
		_fail("Convergence did not accept any-of world milestone")
		return
	completed.append("campaign:convergence")
	if CAMPAIGN.available_milestones(completed, world_state).has("campaign:endgame_unlocked"):
		_fail("Endgame bypassed guardian gate")
		return
	world_state.append("dungeon_milestone:three_guardians_defeated")
	if not CAMPAIGN.available_milestones(completed, world_state).has("campaign:endgame_unlocked"):
		_fail("Endgame did not unlock after required campaign/dungeon state")
		return
	completed.append("campaign:endgame_unlocked")
	world_state.append("magic_mastery:moon")
	var endings: Array[String] = CAMPAIGN.available_milestones(completed, world_state)
	if not endings.has("campaign:ending_moon") or endings.has("campaign:ending_veil"):
		_fail("Ending prerequisites are not branch-specific")
		return
	var event: Dictionary = CAMPAIGN.completion_event("campaign:ending_moon", 42)
	if str(event.get("event_id", "")) != "campaign_complete:ending_moon:42" or str(event.get("ending_id", "")) != "ending:moon_restored":
		_fail("Campaign completion event is unstable")
		return

	print("CAMPAIGN_PROGRESSION_CATALOG_OK milestones=%d endings=%d" % [ids.size(), CAMPAIGN.ending_ids().size()])
	quit(0)

func _fail(message: String) -> void:
	printerr("CAMPAIGN_PROGRESSION_CATALOG_FAILED: %s" % message)
	quit(1)
