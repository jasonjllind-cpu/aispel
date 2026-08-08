extends RefCounted
class_name RegionalLootCatalog

const FORMAT_VERSION: int = 1
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic"]

const ITEMS: Dictionary = {
	"ancient_coin": {"display_name": "Ancient Coin", "rarity": "common", "required_tier": 1, "base_value": 12, "min_amount": 1, "max_amount": 3, "tags": ["currency", "relic"]},
	"moon_shard": {"display_name": "Moon Shard", "rarity": "uncommon", "required_tier": 1, "base_value": 28, "min_amount": 1, "max_amount": 2, "tags": ["moon", "magic"]},
	"traveler_cache": {"display_name": "Traveler Cache", "rarity": "common", "required_tier": 1, "base_value": 18, "min_amount": 1, "max_amount": 2, "tags": ["supplies", "road"]},
	"herb_bundle": {"display_name": "Herb Bundle", "rarity": "common", "required_tier": 1, "base_value": 14, "min_amount": 1, "max_amount": 3, "tags": ["herb", "survival"]},
	"old_relic": {"display_name": "Old Relic", "rarity": "uncommon", "required_tier": 1, "base_value": 34, "min_amount": 1, "max_amount": 1, "tags": ["relic", "lore"]},
	"blackwood_relic": {"display_name": "Blackwood Relic", "rarity": "rare", "required_tier": 2, "base_value": 62, "min_amount": 1, "max_amount": 1, "tags": ["blackwood", "relic"]},
	"grave_token": {"display_name": "Grave Token", "rarity": "uncommon", "required_tier": 1, "base_value": 30, "min_amount": 1, "max_amount": 2, "tags": ["grave", "ritual"]},
	"witch_charm": {"display_name": "Witch Charm", "rarity": "rare", "required_tier": 2, "base_value": 68, "min_amount": 1, "max_amount": 1, "tags": ["witch", "magic"]},
	"beacon_fragment": {"display_name": "Beacon Fragment", "rarity": "uncommon", "required_tier": 1, "base_value": 38, "min_amount": 1, "max_amount": 2, "tags": ["beacon", "highland"]},
	"storm_glass": {"display_name": "Storm Glass", "rarity": "rare", "required_tier": 2, "base_value": 72, "min_amount": 1, "max_amount": 1, "tags": ["storm", "magic"]},
	"giant_token": {"display_name": "Giant Token", "rarity": "rare", "required_tier": 2, "base_value": 74, "min_amount": 1, "max_amount": 1, "tags": ["giant", "ancient"]},
	"funeral_coin": {"display_name": "Funeral Coin", "rarity": "uncommon", "required_tier": 1, "base_value": 32, "min_amount": 1, "max_amount": 2, "tags": ["funeral", "currency"]},
	"bell_fragment": {"display_name": "Bell Fragment", "rarity": "rare", "required_tier": 2, "base_value": 66, "min_amount": 1, "max_amount": 1, "tags": ["bell", "lore"]},
	"ember_glass": {"display_name": "Ember Glass", "rarity": "rare", "required_tier": 2, "base_value": 78, "min_amount": 1, "max_amount": 1, "tags": ["ash", "fire"]},
	"burnt_relic": {"display_name": "Burnt Relic", "rarity": "uncommon", "required_tier": 1, "base_value": 40, "min_amount": 1, "max_amount": 2, "tags": ["ash", "relic"]},
	"witch_ember": {"display_name": "Witch Ember", "rarity": "epic", "required_tier": 3, "base_value": 125, "min_amount": 1, "max_amount": 1, "tags": ["witch", "fire", "magic"]},
	"frost_glass": {"display_name": "Frost Glass", "rarity": "rare", "required_tier": 2, "base_value": 80, "min_amount": 1, "max_amount": 1, "tags": ["frost", "magic"]},
	"pilgrim_token": {"display_name": "Pilgrim Token", "rarity": "uncommon", "required_tier": 1, "base_value": 36, "min_amount": 1, "max_amount": 2, "tags": ["pilgrimage", "relic"]},
	"drowned_relic": {"display_name": "Drowned Relic", "rarity": "rare", "required_tier": 2, "base_value": 76, "min_amount": 1, "max_amount": 1, "tags": ["lake", "relic"]}
}

static func get_item(item_id: String) -> Dictionary:
	var value: Variant = ITEMS.get(item_id, {})
	if not value is Dictionary:
		return {}
	var item: Dictionary = (value as Dictionary).duplicate(true)
	item["id"] = item_id
	return item

static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in ITEMS.keys():
		ids.append(str(key))
	ids.sort()
	return ids

static func validate_item(item: Dictionary) -> bool:
	var rarity: String = str(item.get("rarity", ""))
	return not str(item.get("id", "")).is_empty() \
		and not str(item.get("display_name", "")).is_empty() \
		and RARITY_ORDER.has(rarity) \
		and int(item.get("required_tier", 0)) > 0 \
		and int(item.get("base_value", 0)) > 0 \
		and int(item.get("min_amount", 0)) > 0 \
		and int(item.get("max_amount", 0)) >= int(item.get("min_amount", 0)) \
		and item.get("tags", []) is Array \
		and not (item.get("tags", []) as Array).is_empty()

static func build_region_plan(world_seed: int, stable_region_id: String, content_theme: Dictionary, content_profile: Dictionary) -> Dictionary:
	var palette_value: Variant = content_theme.get("loot_palette", [])
	if not palette_value is Array:
		return _empty_plan(stable_region_id)
	var palette: Array = palette_value as Array
	var loot_tier: int = maxi(1, int(content_profile.get("loot_tier", 1)))
	var poi_budget: int = maxi(1, int(content_profile.get("poi_budget", 1)))
	var reward_count: int = clampi(1 + ceili(float(poi_budget) / 2.0) + floori(float(loot_tier - 1) / 2.0), 2, 7)
	var eligible: Array[String] = []
	for item_value in palette:
		var item_id: String = str(item_value)
		var item: Dictionary = get_item(item_id)
		if validate_item(item) and int(item.get("required_tier", 1)) <= loot_tier:
			eligible.append(item_id)
	if eligible.is_empty():
		for item_value in palette:
			var item_id: String = str(item_value)
			if validate_item(get_item(item_id)):
				eligible.append(item_id)
	if eligible.is_empty():
		return _empty_plan(stable_region_id)

	var seed_value: int = int(("%d:%s:loot_plan:v%d" % [world_seed, stable_region_id, FORMAT_VERSION]).hash() & 0x7fffffff)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var entries: Array[Dictionary] = []
	var rarity_counts: Dictionary = {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
	var total_value: int = 0
	for slot_index in range(reward_count):
		var item_id: String = _weighted_pick(rng, eligible, loot_tier)
		var item: Dictionary = get_item(item_id)
		var amount: int = rng.randi_range(int(item.get("min_amount", 1)), int(item.get("max_amount", 1)))
		if loot_tier >= 3 and str(item.get("rarity", "common")) == "common":
			amount += 1
		var tier_multiplier: float = 1.0 + float(loot_tier - 1) * 0.18
		var value: int = maxi(1, roundi(float(int(item.get("base_value", 1)) * amount) * tier_multiplier))
		var stable_id: String = "loot_plan:%s:%d:%s" % [stable_region_id.trim_prefix("region:"), slot_index, item_id]
		var rarity: String = str(item.get("rarity", "common"))
		entries.append({
			"stable_id": stable_id,
			"persistent_state_id": "state:%s" % stable_id,
			"item_id": item_id,
			"display_name": str(item.get("display_name", item_id)),
			"rarity": rarity,
			"amount": amount,
			"value": value,
			"loot_tier": loot_tier,
			"tags": (item.get("tags", []) as Array).duplicate()
		})
		rarity_counts[rarity] = int(rarity_counts.get(rarity, 0)) + 1
		total_value += value
	return {
		"format_version": FORMAT_VERSION,
		"seed": seed_value,
		"region_id": stable_region_id,
		"loot_tier": loot_tier,
		"entries": entries,
		"rarity_counts": rarity_counts,
		"total_value": total_value
	}

static func _weighted_pick(rng: RandomNumberGenerator, eligible: Array[String], loot_tier: int) -> String:
	var total_weight: float = 0.0
	var weights: Array[float] = []
	for item_id in eligible:
		var item: Dictionary = get_item(item_id)
		var rarity: String = str(item.get("rarity", "common"))
		var weight: float = _rarity_weight(rarity, loot_tier)
		weights.append(weight)
		total_weight += weight
	var roll: float = rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for index in range(eligible.size()):
		cursor += weights[index]
		if roll <= cursor:
			return eligible[index]
	return eligible.back()

static func _rarity_weight(rarity: String, loot_tier: int) -> float:
	match rarity:
		"epic":
			return 0.4 + float(maxi(0, loot_tier - 2)) * 1.0
		"rare":
			return 1.3 + float(maxi(0, loot_tier - 1)) * 0.65
		"uncommon":
			return 2.5 + float(loot_tier - 1) * 0.20
		_:
			return maxf(1.4, 4.0 - float(loot_tier - 1) * 0.55)

static func _empty_plan(stable_region_id: String) -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"seed": 0,
		"region_id": stable_region_id,
		"loot_tier": 1,
		"entries": [],
		"rarity_counts": {"common": 0, "uncommon": 0, "rare": 0, "epic": 0},
		"total_value": 0
	}
