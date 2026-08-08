extends SceneTree

const BUILD := preload("res://scripts/progression/character_build_model.gd")
const EQUIPMENT := preload("res://scripts/equipment/equipment_progression_catalog.gd")
const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")

func _init() -> void:
	if not _validate_equipment_and_stats():
		return
	if not _validate_spell_loadout():
		return
	if not _validate_snapshot_determinism():
		return
	print("CHARACTER_BUILD_MODEL_OK")
	quit(0)

func _validate_equipment_and_stats() -> bool:
	var build: Dictionary = BUILD.create_build("player:test")
	var magic: Dictionary = MAGIC.create_state("player:test")
	var baseline: Dictionary = BUILD.derive_stats(build, 12, magic, {"might": 2, "vitality": 2, "focus": 2, "agility": 2})
	if baseline.is_empty() or float(baseline.get("max_health", 0.0)) <= 100.0:
		return _fail("Baseline character stats are invalid")
	var weapon: Dictionary = EQUIPMENT.roll_item("equipment:moon_blade", 12, 76082601, "quest:frontier", 0)
	var armor: Dictionary = EQUIPMENT.roll_item("equipment:frostmere_mail", 12, 76082601, "dungeon:frost", 1)
	if weapon.is_empty() or armor.is_empty():
		return _fail("Deterministic equipment fixtures failed to roll")
	build = BUILD.equip(build, weapon, 12)
	build = BUILD.equip(build, armor, 12)
	if not BUILD.validate_build(build):
		return _fail("Equipped character build failed validation")
	var equipped: Dictionary = BUILD.derive_stats(build, 12, magic, {"might": 2, "vitality": 2, "focus": 2, "agility": 2})
	if float(equipped.get("damage", 0.0)) <= float(baseline.get("damage", 0.0)):
		return _fail("Weapon equipment did not increase derived damage")
	if float(equipped.get("armor", 0.0)) <= float(baseline.get("armor", 0.0)):
		return _fail("Armor equipment did not increase derived armor")
	var too_high: Dictionary = EQUIPMENT.roll_item("equipment:crypt_fang", 20, 76082601, "dungeon:late", 0)
	var unchanged: Dictionary = BUILD.equip(build, too_high, 12)
	if var_to_str(unchanged) != var_to_str(build):
		return _fail("Build accepted equipment above the player's level")
	var cleared: Dictionary = BUILD.unequip(build, "weapon")
	if not ((cleared.get("equipment", {}) as Dictionary).get("weapon", {}) as Dictionary).is_empty():
		return _fail("Unequip did not clear the weapon slot")
	return true

func _validate_spell_loadout() -> bool:
	var build: Dictionary = BUILD.create_build("player:test")
	var magic: Dictionary = MAGIC.create_state("player:test")
	magic = MAGIC.grant_mastery(magic, "moon", 400, "magic_discovery:test:moon")
	if not MAGIC.available_spells(magic, 12).has("moon_bolt"):
		return _fail("Magic fixture failed to expose Moon Bolt")
	build = BUILD.assign_spell(build, 0, "moon_bolt", 12, magic)
	if str((build.get("spell_slots", []) as Array)[0]) != "moon_bolt":
		return _fail("Unlocked spell was not assigned to the loadout")
	build = BUILD.assign_spell(build, 1, "moon_bolt", 12, magic)
	var slots: Array = build.get("spell_slots", []) as Array
	if str(slots[0]) != "" or str(slots[1]) != "moon_bolt":
		return _fail("Spell reassignment allowed duplicate spell slots")
	var invalid: Dictionary = BUILD.assign_spell(build, 2, "pale_silence", 12, magic)
	if var_to_str(invalid) != var_to_str(build):
		return _fail("Loadout accepted a spell that is not unlocked/level-ready")
	var magic_before: Dictionary = BUILD.derive_stats(build, 12, MAGIC.create_state("player:test"), {})
	var magic_after: Dictionary = BUILD.derive_stats(build, 12, magic, {})
	if float(magic_after.get("magic_power", 0.0)) <= float(magic_before.get("magic_power", 0.0)):
		return _fail("Magic-school ranks did not affect derived magic power")
	return true

func _validate_snapshot_determinism() -> bool:
	var build: Dictionary = BUILD.create_build("player:test")
	var magic: Dictionary = MAGIC.create_state("player:test")
	magic = MAGIC.grant_mastery(magic, "frost", 430, "magic_discovery:test:frost")
	var armor: Dictionary = EQUIPMENT.roll_item("equipment:frostmere_mail", 12, 76082601, "dungeon:frost", 2)
	build = BUILD.equip(build, armor, 12)
	build = BUILD.assign_spell(build, 0, "frost_lance", 12, magic)
	var first: Dictionary = BUILD.build_snapshot(build, 12, magic, {"focus": 3})
	var second: Dictionary = BUILD.build_snapshot(build, 12, magic, {"focus": 3})
	if first.is_empty() or var_to_str(first) != var_to_str(second):
		return _fail("Character build snapshot is empty or non-deterministic")
	if not str(first.get("snapshot_id", "")).begins_with("build:test:"):
		return _fail("Character build snapshot lacks stable identity")
	if str((first.get("equipment_ids", {}) as Dictionary).get("armor", "")).is_empty():
		return _fail("Character build snapshot lost equipped item identity")
	return true

func _fail(message: String) -> bool:
	printerr("CHARACTER_BUILD_MODEL_FAILED: %s" % message)
	quit(1)
	return false
