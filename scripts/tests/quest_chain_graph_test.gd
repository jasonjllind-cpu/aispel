extends SceneTree

const QuestGraph = preload("res://scripts/progression/quest_chain_graph.gd")

func _initialize() -> void:
	_assert(QuestGraph.validate_graph().is_empty(), "quest graph validation failed")
	var ids: Array[String] = QuestGraph.get_quest_ids()
	_assert(ids.size() == 5, "unexpected quest graph size")
	_assert(ids == QuestGraph.get_quest_ids(), "quest ordering is not deterministic")
	_assert(QuestGraph.progression_id("quest:blackwood_whispers") == "progression:quest:blackwood_whispers", "stable progression id changed")

	var completed: Array[String] = []
	var active: Array[String] = []
	var branches: Dictionary = {}
	_assert(QuestGraph.available_quests(completed, active, branches) == ["quest:blackwood_whispers"], "root quest availability incorrect")
	completed.append("quest:blackwood_whispers")
	_assert(QuestGraph.can_start("quest:fallen_chapel_echoes", completed, active, branches), "prerequisite chain did not unlock")
	completed.append("quest:fallen_chapel_echoes")
	var branch_options: Array[String] = QuestGraph.available_quests(completed, active, branches)
	_assert(branch_options.has("quest:moon_oath") and branch_options.has("quest:veil_bargain"), "branch choices unavailable")
	branches = QuestGraph.choose_branch("quest:moon_oath", branches)
	_assert(QuestGraph.can_start("quest:moon_oath", completed, active, branches), "chosen branch was blocked")
	_assert(not QuestGraph.can_start("quest:veil_bargain", completed, active, branches), "exclusive branch was not blocked")
	completed.append("quest:moon_oath")
	_assert(QuestGraph.can_start("quest:rekindle_beacon", completed, active, branches), "any-prerequisite convergence did not unlock")
	_assert(QuestGraph.objective_ids("quest:fallen_chapel_echoes") == ["objective:chapel:discover", "objective:chapel:relic"], "objective ids unstable")

	print("QUEST_CHAIN_GRAPH_OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
