extends SceneTree

const EquipmentCatalog = preload("res://scripts/equipment/equipment_progression_catalog.gd")

func _initialize() -> void:
	var ids: Array[String] = EquipmentCatalog.get_item_ids()
	_assert(ids.size() >= 5, "equipment catalog coverage too small")
	_assert(ids == EquipmentCatalog.get_item_ids(), "equipment ids are not deterministic")
	_assert(EquipmentCatalog.get_item("equipment:moon_blade").get("slot", "") == "weapon", "weapon definition missing")

	var first: Dictionary = EquipmentCatalog.roll_item("equipment:moon_blade", 16, 583921, "loot:blackwood:ruin:4", 2)
	var second: Dictionary = EquipmentCatalog.roll_item("equipment:moon_blade", 16, 583921, "loot:blackwood:ruin:4", 2)
	_assert(not first.is_empty(), "valid equipment roll failed")
	_assert(first == second, "same deterministic inputs produced different item rolls")
	_assert(EquipmentCatalog.validate_instance(first), "generated equipment instance is invalid")
	_assert(str(first.get("instance_id", "")) == "item:loot_blackwood_ruin_4:moon_blade:2", "stable instance id changed")
	_assert((first.get("stats", {}) as Dictionary).has("damage"), "scaled weapon damage missing")

	var different: Dictionary = EquipmentCatalog.roll_item("equipment:moon_blade", 16, 583921, "loot:blackwood:ruin:4", 3)
	_assert(str(different.get("instance_id", "")) != str(first.get("instance_id", "")), "roll index did not produce distinct stable id")
	_assert(EquipmentCatalog.roll_item("equipment:crypt_fang", 4, 583921, "loot:test", 0).is_empty(), "required level gate ignored")
	_assert(EquipmentCatalog.roll_item("equipment:not_real", 20, 583921, "loot:test", 0).is_empty(), "unknown equipment accepted")
	_assert(EquipmentCatalog.rarity_for_level(1, 0.99) == "common", "rarity level gate ignored")
	_assert(EquipmentCatalog.rarity_for_level(20, 0.99) == "epic", "epic rarity band unavailable")

	print("EQUIPMENT_PROGRESSION_OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
