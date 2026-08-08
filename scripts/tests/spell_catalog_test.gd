extends SceneTree

const SpellCatalogScript = preload("res://scripts/magic/spell_catalog.gd")

func _initialize() -> void:
	var ids: Array[String] = SpellCatalogScript.get_ids()
	_assert(ids.size() >= 12, "spell catalog coverage too small")
	_assert(ids == SpellCatalogScript.get_ids(), "spell ordering is not deterministic")
	_assert(SpellCatalogScript.get_school_ids().has("moon"), "moon school missing")
	_assert(SpellCatalogScript.get_school_ids().has("ember"), "ember school missing")
	for spell_id in ids:
		_assert(SpellCatalogScript.validate_spell(SpellCatalogScript.get_spell(spell_id)), "invalid spell: %s" % spell_id)

	var caster: Dictionary = {
		"player_id": "player:test",
		"level": 20,
		"unlocked_spells": ids.duplicate(),
		"resources": {"mana": 100, "stamina": 100},
		"cooldowns": {}
	}
	var gate: Dictionary = SpellCatalogScript.can_cast("moon_bolt", caster, 1000)
	_assert(bool(gate.get("allowed", false)), "valid cast denied")
	var built: Dictionary = SpellCatalogScript.build_cast_command("moon_bolt", caster, 1000, 7, {"direction": Vector3.FORWARD})
	_assert(bool(built.get("accepted", false)), "cast command rejected")
	var command: Dictionary = built.get("command", {}) as Dictionary
	_assert(str(command.get("command_id", "")) == "cast:test:7:moon_bolt", "unstable command id")
	_assert(int(command.get("resource_cost", 0)) == 12, "incorrect resource cost")
	var applied: Dictionary = SpellCatalogScript.apply_cast_cost(command, caster)
	_assert(int((applied.get("resources", {}) as Dictionary).get("mana", 0)) == 88, "cast cost not applied")
	_assert(int((applied.get("cooldowns", {}) as Dictionary).get("moon_bolt", 0)) > 1000, "cooldown not applied")

	var locked: Dictionary = caster.duplicate(true)
	locked["level"] = 1
	_assert(str(SpellCatalogScript.can_cast("moon_bolt", locked, 1000).get("reason", "")) == "level_locked", "level gate ignored")

	print("SPELL_CATALOG_OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
