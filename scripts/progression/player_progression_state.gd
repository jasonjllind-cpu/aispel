extends RefCounted
class_name PlayerProgressionState

const FORMAT_VERSION: int = 1
const MAX_LEVEL: int = 50
const BASE_XP: int = 100
const XP_GROWTH: float = 1.22

var player_id: String = "player:local"
var level: int = 1
var current_xp: int = 0
var lifetime_xp: int = 0
var unspent_attribute_points: int = 0
var unlocked_rewards: Array[String] = []

func configure(stable_player_id: String) -> void:
	player_id = stable_player_id if not stable_player_id.is_empty() else "player:local"

func xp_required_for_level(target_level: int) -> int:
	if target_level <= 1:
		return 0
	return maxi(1, roundi(float(BASE_XP) * pow(XP_GROWTH, float(target_level - 2))))

func total_xp_required_for_level(target_level: int) -> int:
	var capped_level: int = clampi(target_level, 1, MAX_LEVEL)
	var total: int = 0
	for next_level in range(2, capped_level + 1):
		total += xp_required_for_level(next_level)
	return total

func grant_xp(amount: int, source_id: String = "") -> Dictionary:
	var granted: int = maxi(0, amount)
	if granted <= 0 or level >= MAX_LEVEL:
		return _result(granted, [], source_id)
	current_xp += granted
	lifetime_xp += granted
	var level_ups: Array[Dictionary] = []
	while level < MAX_LEVEL:
		var required: int = xp_required_for_level(level + 1)
		if current_xp < required:
			break
		current_xp -= required
		level += 1
		unspent_attribute_points += _attribute_points_for_level(level)
		var rewards: Array[String] = _rewards_for_level(level)
		for reward_id in rewards:
			if not unlocked_rewards.has(reward_id):
				unlocked_rewards.append(reward_id)
		level_ups.append({"level": level, "attribute_points": _attribute_points_for_level(level), "rewards": rewards})
	if level >= MAX_LEVEL:
		current_xp = 0
	unlocked_rewards.sort()
	return _result(granted, level_ups, source_id)

func spend_attribute_points(amount: int) -> bool:
	var spend: int = maxi(0, amount)
	if spend <= 0 or spend > unspent_attribute_points:
		return false
	unspent_attribute_points -= spend
	return true

func progress_to_next_level() -> float:
	if level >= MAX_LEVEL:
		return 1.0
	return clampf(float(current_xp) / float(xp_required_for_level(level + 1)), 0.0, 1.0)

func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"player_id": player_id,
		"level": level,
		"current_xp": current_xp,
		"lifetime_xp": lifetime_xp,
		"unspent_attribute_points": unspent_attribute_points,
		"unlocked_rewards": unlocked_rewards.duplicate()
	}

func load_dict(data: Dictionary) -> bool:
	if int(data.get("format_version", -1)) != FORMAT_VERSION:
		return false
	var loaded_id: String = str(data.get("player_id", ""))
	var loaded_level: int = int(data.get("level", 0))
	var loaded_current_xp: int = int(data.get("current_xp", -1))
	var loaded_lifetime_xp: int = int(data.get("lifetime_xp", -1))
	var loaded_points: int = int(data.get("unspent_attribute_points", -1))
	var loaded_rewards: Variant = data.get("unlocked_rewards", [])
	if loaded_id.is_empty() or loaded_level < 1 or loaded_level > MAX_LEVEL or loaded_current_xp < 0 or loaded_lifetime_xp < 0 or loaded_points < 0 or not loaded_rewards is Array:
		return false
	if loaded_level < MAX_LEVEL and loaded_current_xp >= xp_required_for_level(loaded_level + 1):
		return false
	player_id = loaded_id
	level = loaded_level
	current_xp = 0 if level >= MAX_LEVEL else loaded_current_xp
	lifetime_xp = loaded_lifetime_xp
	unspent_attribute_points = loaded_points
	unlocked_rewards.clear()
	for reward_value in loaded_rewards as Array:
		var reward_id: String = str(reward_value)
		if not reward_id.is_empty() and not unlocked_rewards.has(reward_id):
			unlocked_rewards.append(reward_id)
	unlocked_rewards.sort()
	return true

func _attribute_points_for_level(target_level: int) -> int:
	return 2 if target_level % 5 == 0 else 1

func _rewards_for_level(target_level: int) -> Array[String]:
	var rewards: Array[String] = []
	if target_level == 2:
		rewards.append("reward:equipment:uncommon")
	if target_level == 3:
		rewards.append("reward:magic:first_spell_slot")
	if target_level == 5:
		rewards.append("reward:equipment:rare")
	if target_level == 8:
		rewards.append("reward:magic:second_spell_slot")
	if target_level == 10:
		rewards.append("reward:quest:frontier_chain")
	if target_level == 15:
		rewards.append("reward:equipment:epic")
	if target_level == 20:
		rewards.append("reward:quest:wilds_chain")
	if target_level == 30:
		rewards.append("reward:magic:mastery_slot")
	return rewards

func _result(granted: int, level_ups: Array[Dictionary], source_id: String) -> Dictionary:
	return {
		"player_id": player_id,
		"source_id": source_id,
		"granted_xp": granted,
		"level": level,
		"current_xp": current_xp,
		"progress": progress_to_next_level(),
		"level_ups": level_ups,
		"unspent_attribute_points": unspent_attribute_points,
		"unlocked_rewards": unlocked_rewards.duplicate()
	}
