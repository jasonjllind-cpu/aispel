extends SceneTree

const SpellCatalogScript = preload("res://scripts/progression/spell_catalog.gd")

func _initialize() -> void:
	var catalog = SpellCatalogScript.new()
	_assert(catalog.validate_catalog().is_empty(), "catalog validation failed")
	_assert(catalog.has_spell("spell:ember_bolt"), "starter spell missing")
	_assert(not catalog.has_spell("spell:not_real"), "unknown spell unexpectedly exists")
	_assert(catalog.school_ids().has("pyromancy"), "pyromancy school missing")
	_assert(catalog.spells_for_school("mooncraft") == ["spell:moonward"], "school filtering unstable")

	var locked_rewards: Array[String] = []
	_assert(not catalog.can_unlock("spell:ember_bolt", 2, locked_rewards), "level gate ignored")
	var rewards: Array[String] = ["reward:magic:first_spell_slot"]
	_assert(catalog.can_unlock("spell:ember_bolt", 3, rewards), "starter spell should unlock")
	_assert(not catalog.can_unlock("spell:moonward", 8, rewards), "reward prerequisite ignored")

	var contract: Dictionary = catalog.casting_contract("spell:grave_grasp")
	_assert(contract.get("spell_id", "") == "spell:grave_grasp", "stable spell id missing from contract")
	_assert(contract.get("targeting", "") == "ground_area", "targeting contract incorrect")
	_assert(int(contract.get("cost", -1)) == 26, "resource cost incorrect")
	_assert(float(contract.get("range", -1.0)) == 18.0, "range contract incorrect")

	var first: Array[String] = catalog.spell_ids()
	var second: Array[String] = catalog.spell_ids()
	_assert(first == second, "catalog ordering is not deterministic")
	_assert(first.size() == 4, "unexpected spell count")

	print("SPELL_CATALOG_OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
