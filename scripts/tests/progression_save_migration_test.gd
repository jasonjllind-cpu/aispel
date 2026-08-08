extends SceneTree

const CODEC := preload("res://scripts/progression/progression_save_codec.gd")
const PROGRESSION := preload("res://scripts/progression/player_progression_state.gd")
const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")
const BUILD := preload("res://scripts/progression/character_build_model.gd")
const EQUIPMENT := preload("res://scripts/equipment/equipment_progression_catalog.gd")
const GATES := preload("res://scripts/progression/regional_progression_gate.gd")

func _init() -> void:
	if not _validate_current_round_trip():
		return
	if not _validate_legacy_migration():
		return
	if not _validate_corruption_rejection():
		return
	if not _validate_balance_coverage():
		return
	print("PROGRESSION_SAVE_MIGRATION_OK version=%d" % CODEC.CURRENT_VERSION)
	quit(0)

func _validate_current_round_trip() -> bool:
	var player_id: String = "player:test"
	var progression_state: RefCounted = PROGRESSION.new()
	progression_state.call("configure", player_id)
	progression_state.call("grant_xp", int(progression_state.call("total_xp_required_for_level", 12)) + 31, "quest:test")
	var progression: Dictionary = progression_state.call("to_dict") as Dictionary
	var magic: Dictionary = MAGIC.create_state(player_id)
	magic = MAGIC.grant_mastery(magic, "moon", 400, "magic_discovery:test:moon")
	var build: Dictionary = BUILD.create_build(player_id)
	var weapon: Dictionary = EQUIPMENT.roll_item("equipment:moon_blade", 12, 78082601, "quest:test", 0)
	build = BUILD.equip(build, weapon, 12)
	build = BUILD.assign_spell(build, 0, "moon_bolt", 12, magic)
	var quests: Array[String] = ["quest:frontier_oath:frontier_arrival", "quest:frontier_oath:frontier_warden"]
	var encoded: Dictionary = CODEC.encode(player_id, progression, magic, build, quests, 9)
	if encoded.is_empty() or not CODEC.validate(encoded):
		return _fail("Current progression save failed validation")
	var decoded: Dictionary = CODEC.decode(encoded)
	if decoded.is_empty() or int(decoded.get("revision", -1)) != 9:
		return _fail("Current progression save failed to decode")
	if var_to_str(decoded.get("progression", {})) != var_to_str(progression):
		return _fail("Progression changed during save round trip")
	if var_to_str(decoded.get("magic", {})) != var_to_str(magic):
		return _fail("Magic state changed during save round trip")
	if var_to_str(decoded.get("build", {})) != var_to_str(build):
		return _fail("Character build changed during save round trip")
	if var_to_str(decoded.get("completed_quests", [])) != var_to_str(quests):
		return _fail("Quest state changed during save round trip")
	return true

func _validate_legacy_migration() -> bool:
	var helper: RefCounted = PROGRESSION.new()
	var level: int = 5
	var lifetime_xp: int = int(helper.call("total_xp_required_for_level", level)) + 20
	var legacy: Dictionary = CODEC.build_legacy_v1(
		"player:legacy",
		level,
		20,
		lifetime_xp,
		4,
		["moon_bolt"],
		["quest:frontier_oath:frontier_arrival"]
	)
	var migrated: Dictionary = CODEC.migrate(legacy)
	if migrated.is_empty() or int(migrated.get("version", 0)) != CODEC.CURRENT_VERSION:
		return _fail("Legacy progression save did not migrate")
	if not CODEC.validate(migrated):
		return _fail("Migrated legacy save failed current validation")
	var progression: Dictionary = migrated.get("progression", {}) as Dictionary
	if int(progression.get("level", 0)) != 5 or int(progression.get("current_xp", -1)) != 20:
		return _fail("Legacy player level/XP changed during migration")
	var magic: Dictionary = migrated.get("magic", {}) as Dictionary
	if not (magic.get("unlocked_spells", []) as Array).has("moon_bolt"):
		return _fail("Legacy unlocked spell was lost during migration")
	var build: Dictionary = migrated.get("build", {}) as Dictionary
	if not BUILD.validate_build(build):
		return _fail("Legacy migration did not create a valid build state")
	var remigrated: Dictionary = CODEC.migrate(migrated)
	if var_to_str(remigrated) != var_to_str(migrated):
		return _fail("Current save migration is not idempotent")
	return true

func _validate_corruption_rejection() -> bool:
	if not CODEC.migrate({"version": 99, "player_id": "player:test"}).is_empty():
		return _fail("Unsupported progression save version was accepted")
	var bad_legacy: Dictionary = CODEC.build_legacy_v1("player:legacy", 3, 0, 100, 0, ["unknown_spell"], [])
	if not CODEC.migrate(bad_legacy).is_empty():
		return _fail("Legacy save with unknown spell was accepted")
	var duplicate_quests: Dictionary = CODEC.build_legacy_v1("player:legacy", 3, 0, 100, 0, [], ["quest:test:a", "quest:test:a"])
	if not CODEC.migrate(duplicate_quests).is_empty():
		return _fail("Legacy save with duplicate quest state was accepted")
	var progression_state: RefCounted = PROGRESSION.new()
	progression_state.call("configure", "player:test")
	var current: Dictionary = CODEC.encode("player:test", progression_state.call("to_dict"), MAGIC.create_state("player:test"), BUILD.create_build("player:test"), [], 0)
	current["player_id"] = "player:spoofed"
	if CODEC.validate(current):
		return _fail("Cross-player save payload was accepted")
	return true

func _validate_balance_coverage() -> bool:
	var previous_damage: float = 0.0
	var previous_health: float = 0.0
	for level in [1, 5, 10, 20, 50]:
		var player_id: String = "player:balance:%d" % level
		var progression_state: RefCounted = PROGRESSION.new()
		progression_state.call("configure", player_id)
		if level > 1:
			progression_state.call("grant_xp", int(progression_state.call("total_xp_required_for_level", level)), "balance:test")
		var progression: Dictionary = progression_state.call("to_dict") as Dictionary
		if int(progression.get("level", 0)) != level:
			return _fail("Balance fixture did not reach level %d" % level)

		var magic: Dictionary = MAGIC.create_state(player_id)
		var mastery_amount: int = 0
		if level >= 5:
			mastery_amount = 160
		if level >= 10:
			mastery_amount = 430
		if level >= 20:
			mastery_amount = 900
		if level >= 50:
			mastery_amount = 1800
		if mastery_amount > 0:
			for school_id in MAGIC.get_school_ids():
				magic = MAGIC.grant_mastery(magic, school_id, mastery_amount, "magic_discovery:balance:%s:%d" % [school_id, level])

		var build: Dictionary = BUILD.create_build(player_id)
		var weapon_id: String = "equipment:iron_sword"
		if level >= 10:
			weapon_id = "equipment:crypt_fang"
		elif level >= 5:
			weapon_id = "equipment:moon_blade"
		var weapon: Dictionary = EQUIPMENT.roll_item(weapon_id, level, 78082601, "balance:%d" % level, 0)
		if weapon.is_empty():
			return _fail("Balance equipment failed to roll at level %d" % level)
		build = BUILD.equip(build, weapon, level)
		var armor: Dictionary = {}
		if level >= 12:
			armor = EQUIPMENT.roll_item("equipment:frostmere_mail", level, 78082601, "balance:%d" % level, 1)
		elif level >= 4:
			armor = EQUIPMENT.roll_item("equipment:warden_mail", level, 78082601, "balance:%d" % level, 1)
		if not armor.is_empty():
			build = BUILD.equip(build, armor, level)

		var attributes: Dictionary = {
			"might": maxi(0, level / 5),
			"vitality": maxi(0, level / 6),
			"focus": maxi(0, level / 7),
			"agility": maxi(0, level / 8)
		}
		var stats: Dictionary = BUILD.derive_stats(build, level, magic, attributes)
		if float(stats.get("damage", 0.0)) <= previous_damage or float(stats.get("max_health", 0.0)) <= previous_health:
			return _fail("Core combat stats failed monotonic balance coverage at level %d" % level)
		previous_damage = float(stats.get("damage", 0.0))
		previous_health = float(stats.get("max_health", 0.0))

		var encoded: Dictionary = CODEC.encode(player_id, progression, magic, build, [], level)
		if encoded.is_empty() or CODEC.decode(encoded).is_empty():
			return _fail("Balance fixture failed save round trip at level %d" % level)

		var heartland: Dictionary = {"stable_id": "region:balance:heartland", "progression_band": "heartland", "biome": "green_highlands"}
		if not bool(GATES.evaluate_region(heartland, level, magic).get("allowed", false)):
			return _fail("Heartland progression gate rejected level %d" % level)
		if level >= 5:
			var frontier: Dictionary = {"stable_id": "region:balance:frontier", "progression_band": "frontier", "biome": "blackwood"}
			if not bool(GATES.evaluate_region(frontier, level, magic).get("allowed", false)):
				return _fail("Frontier progression gate rejected level %d" % level)
		if level >= 10:
			var wilds: Dictionary = {"stable_id": "region:balance:wilds", "progression_band": "wilds", "biome": "frostmere"}
			if not bool(GATES.evaluate_region(wilds, level, magic).get("allowed", false)):
				return _fail("Wilds progression gate rejected balanced level %d build" % level)
	return true

func _fail(message: String) -> bool:
	printerr("PROGRESSION_SAVE_MIGRATION_FAILED: %s" % message)
	quit(1)
	return false
