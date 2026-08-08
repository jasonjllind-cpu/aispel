extends RefCounted
class_name EquipmentProgressionCatalog

const FORMAT_VERSION: int = 1

const RARITIES: Dictionary = {
	"common": {"rank": 0, "stat_multiplier": 1.00, "affix_count": 0, "min_level": 1},
	"uncommon": {"rank": 1, "stat_multiplier": 1.12, "affix_count": 1, "min_level": 2},
	"rare": {"rank": 2, "stat_multiplier": 1.28, "affix_count": 2, "min_level": 5},
	"epic": {"rank": 3, "stat_multiplier": 1.52, "affix_count": 3, "min_level": 15}
}

const BASE_ITEMS: Dictionary = {
	"equipment:iron_sword": {"slot": "weapon", "required_level": 1, "base_stats": {"damage": 18.0}, "affix_pool": ["keen", "vital", "swift"]},
	"equipment:moon_blade": {"slot": "weapon", "required_level": 5, "base_stats": {"damage": 30.0, "magic_power": 4.0}, "affix_pool": ["keen", "lunar", "vital", "swift"]},
	"equipment:crypt_fang": {"slot": "weapon", "required_level": 10, "base_stats": {"damage": 38.0, "critical_chance": 0.03}, "affix_pool": ["keen", "graveborn", "vital"]},
	"equipment:warden_mail": {"slot": "armor", "required_level": 4, "base_stats": {"armor": 5.0, "max_health": 12.0}, "affix_pool": ["guarded", "vital", "resolute"]},
	"equipment:frostmere_mail": {"slot": "armor", "required_level": 12, "base_stats": {"armor": 9.0, "max_health": 18.0}, "affix_pool": ["guarded", "frostbound", "vital", "resolute"]}
}

const AFFIXES: Dictionary = {
	"keen": {"stats": {"damage": 0.08}},
	"vital": {"stats": {"max_health": 10.0}},
	"swift": {"stats": {"stamina": 8.0}},
	"lunar": {"stats": {"magic_power": 7.0}},
	"graveborn": {"stats": {"critical_chance": 0.05}},
	"guarded": {"stats": {"armor": 2.0}},
	"resolute": {"stats": {"max_health": 16.0}},
	"frostbound": {"stats": {"frost_resistance": 0.10}}
}

static func get_item(item_id: String) -> Dictionary:
	var value: Variant = BASE_ITEMS.get(item_id, {})
	if not value is Dictionary:
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["id"] = item_id
	return result

static func get_item_ids() -> Array[String]:
	var ids: Array[String] = []
	for item_id in BASE_ITEMS.keys():
		ids.append(str(item_id))
	ids.sort()
	return ids

static func rarity_for_level(player_level: int, roll01: float) -> String:
	var level: int = maxi(1, player_level)
	var roll: float = clampf(roll01, 0.0, 0.999999)
	if level >= 15 and roll >= 0.94:
		return "epic"
	if level >= 5 and roll >= 0.76:
		return "rare"
	if level >= 2 and roll >= 0.48:
		return "uncommon"
	return "common"

static func roll_item(item_id: String, player_level: int, world_seed: int, source_id: String, roll_index: int = 0) -> Dictionary:
	var base: Dictionary = get_item(item_id)
	if base.is_empty() or player_level < int(base.get("required_level", 1)) or source_id.is_empty() or roll_index < 0:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_seed(world_seed, item_id, source_id, roll_index)
	var rarity_id: String = rarity_for_level(player_level, rng.randf())
	var rarity: Dictionary = RARITIES.get(rarity_id, RARITIES["common"]) as Dictionary
	var level_scale: float = 1.0 + 0.045 * float(maxi(0, player_level - 1))
	var multiplier: float = level_scale * float(rarity.get("stat_multiplier", 1.0))
	var stats: Dictionary = {}
	for stat_name in (base.get("base_stats", {}) as Dictionary).keys():
		var base_value: float = float((base.get("base_stats", {}) as Dictionary)[stat_name])
		stats[str(stat_name)] = _round_stat(base_value * multiplier)

	var pool: Array = (base.get("affix_pool", []) as Array).duplicate()
	var affixes: Array[String] = []
	var wanted: int = mini(int(rarity.get("affix_count", 0)), pool.size())
	for _i in range(wanted):
		var pick: int = rng.randi_range(0, pool.size() - 1)
		var affix_id: String = str(pool[pick])
		pool.remove_at(pick)
		affixes.append(affix_id)
		_apply_affix(stats, affix_id)
	affixes.sort()

	var instance_id: String = "item:%s:%s:%d" % [source_id.replace(":", "_"), item_id.trim_prefix("equipment:"), roll_index]
	return {
		"format_version": FORMAT_VERSION,
		"instance_id": instance_id,
		"base_item_id": item_id,
		"slot": str(base.get("slot", "")),
		"item_level": player_level,
		"rarity": rarity_id,
		"rarity_rank": int(rarity.get("rank", 0)),
		"affixes": affixes,
		"stats": stats
	}

static func validate_instance(item: Dictionary) -> bool:
	if int(item.get("format_version", -1)) != FORMAT_VERSION:
		return false
	if not str(item.get("instance_id", "")).begins_with("item:"):
		return false
	if get_item(str(item.get("base_item_id", ""))).is_empty():
		return false
	if not RARITIES.has(str(item.get("rarity", ""))):
		return false
	return int(item.get("item_level", 0)) > 0 and item.get("stats", {}) is Dictionary and item.get("affixes", []) is Array

static func _apply_affix(stats: Dictionary, affix_id: String) -> void:
	var affix: Dictionary = AFFIXES.get(affix_id, {}) as Dictionary
	for stat_name in (affix.get("stats", {}) as Dictionary).keys():
		var name: String = str(stat_name)
		var value: float = float((affix.get("stats", {}) as Dictionary)[stat_name])
		if name == "damage" and absf(value) < 1.0:
			stats[name] = _round_stat(float(stats.get(name, 0.0)) * (1.0 + value))
		else:
			stats[name] = _round_stat(float(stats.get(name, 0.0)) + value)

static func _stable_seed(world_seed: int, item_id: String, source_id: String, roll_index: int) -> int:
	var text: String = "%d|%s|%s|%d" % [world_seed, item_id, source_id, roll_index]
	var value: int = 2166136261
	for i in range(text.length()):
		value = int((value ^ text.unicode_at(i)) * 16777619) & 0x7fffffff
	return maxi(1, value)

static func _round_stat(value: float) -> float:
	return roundf(value * 1000.0) / 1000.0
