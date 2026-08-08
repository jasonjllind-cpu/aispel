extends RefCounted
class_name RegionalProgressionGate

const FORMAT_VERSION: int = 1
const MAGIC := preload("res://scripts/progression/magic_school_progression.gd")

const BAND_RULES: Dictionary = {
	"heartland": {"min_level": 1, "recommended_level": 3, "required_school_rank": 0, "xp_multiplier": 1.0},
	"frontier": {"min_level": 5, "recommended_level": 8, "required_school_rank": 0, "xp_multiplier": 1.35},
	"wilds": {"min_level": 10, "recommended_level": 14, "required_school_rank": 1, "xp_multiplier": 1.75}
}

const BIOME_SCHOOLS: Dictionary = {
	"green_highlands": "moon",
	"blackwood": "thorn",
	"windscar_highlands": "storm",
	"veilmoor": "veil",
	"ashen_fen": "ember",
	"frostmere": "frost"
}

const CONTENT_BASE_XP: Dictionary = {
	"encounter": 28,
	"dungeon": 140,
	"poi": 34,
	"lore": 42,
	"world_event": 52,
	"settlement": 22
}

static func evaluate_region(node: Dictionary, player_level: int, magic_state: Dictionary) -> Dictionary:
	var region_id: String = str(node.get("stable_id", ""))
	var band: String = str(node.get("progression_band", "heartland"))
	if not BAND_RULES.has(band) or region_id.is_empty():
		return _denied(region_id, band, "invalid_region")
	var rule: Dictionary = BAND_RULES[band] as Dictionary
	var min_level: int = int(rule.get("min_level", 1))
	if player_level < min_level:
		return _gate_result(region_id, band, false, "level", min_level, "", 0)
	var required_rank: int = int(rule.get("required_school_rank", 0))
	var school_id: String = str(BIOME_SCHOOLS.get(str(node.get("biome", "")), ""))
	if required_rank > 0:
		if not MAGIC.validate_state(magic_state) or school_id.is_empty():
			return _gate_result(region_id, band, false, "school_state", min_level, school_id, required_rank)
		var schools: Dictionary = magic_state.get("schools", {}) as Dictionary
		var school_state: Dictionary = schools.get(school_id, {}) as Dictionary
		if int(school_state.get("rank", 0)) < required_rank:
			return _gate_result(region_id, band, false, "school_rank", min_level, school_id, required_rank)
	return _gate_result(region_id, band, true, "", min_level, school_id, required_rank)

static func evaluate_content(node: Dictionary, content_type: String, player_level: int, magic_state: Dictionary) -> Dictionary:
	var region_gate: Dictionary = evaluate_region(node, player_level, magic_state)
	if not bool(region_gate.get("allowed", false)):
		return region_gate
	if not CONTENT_BASE_XP.has(content_type):
		var invalid: Dictionary = region_gate.duplicate(true)
		invalid["allowed"] = false
		invalid["reason"] = "unknown_content_type"
		return invalid
	var extra_level: int = 0
	if content_type == "dungeon":
		extra_level = 2
	elif content_type == "world_event":
		extra_level = 1
	var required_level: int = int(region_gate.get("min_level", 1)) + extra_level
	if player_level < required_level:
		var blocked: Dictionary = region_gate.duplicate(true)
		blocked["allowed"] = false
		blocked["reason"] = "content_level"
		blocked["min_level"] = required_level
		return blocked
	var allowed: Dictionary = region_gate.duplicate(true)
	allowed["min_level"] = required_level
	allowed["content_type"] = content_type
	return allowed

static func build_reward_event(node: Dictionary, content_type: String, content_id: String, player_level: int, sequence: int) -> Dictionary:
	var region_id: String = str(node.get("stable_id", ""))
	var band: String = str(node.get("progression_band", "heartland"))
	if region_id.is_empty() or content_id.is_empty() or sequence < 0 or not BAND_RULES.has(band) or not CONTENT_BASE_XP.has(content_type):
		return {}
	var profile: Dictionary = node.get("content_profile", {}) as Dictionary
	var danger: float = clampf(float(profile.get("danger", 0.3)), 0.0, 1.0)
	var graph_depth: int = maxi(0, int(node.get("graph_depth", 0)))
	var multiplier: float = float((BAND_RULES[band] as Dictionary).get("xp_multiplier", 1.0))
	var base_xp: int = int(CONTENT_BASE_XP[content_type])
	var level_factor: float = 1.0 + float(maxi(0, player_level - 1)) * 0.025
	var danger_factor: float = 0.85 + danger * 0.55 + float(mini(graph_depth, 6)) * 0.03
	var xp: int = maxi(1, roundi(float(base_xp) * multiplier * level_factor * danger_factor))
	var school_id: String = str(BIOME_SCHOOLS.get(str(node.get("biome", "")), ""))
	var mastery_xp: int = 0
	if ["dungeon", "lore", "world_event"].has(content_type) and not school_id.is_empty():
		mastery_xp = maxi(8, roundi(float(xp) * (0.22 if content_type == "dungeon" else 0.16)))
	var normalized_content: String = content_id.replace(":", "_").replace("/", "_")
	var reward_id: String = "progression_reward:%s:%s:%s:%d" % [region_id.trim_prefix("region:"), content_type, normalized_content, sequence]
	return {
		"format_version": FORMAT_VERSION,
		"reward_id": reward_id,
		"region_id": region_id,
		"content_type": content_type,
		"content_id": content_id,
		"progression_band": band,
		"xp": xp,
		"school_id": school_id,
		"mastery_xp": mastery_xp,
		"sequence": sequence
	}

static func reward_summary_for_bundle(node: Dictionary, bundle: Dictionary, player_level: int) -> Dictionary:
	var counts: Dictionary = bundle.get("counts", {}) as Dictionary
	var band: String = str(node.get("progression_band", "heartland"))
	if not BAND_RULES.has(band):
		return {}
	var total_xp: int = 0
	for pair in [["encounters", "encounter"], ["pois", "poi"], ["world_events", "world_event"], ["lore", "lore"]]:
		total_xp += int(counts.get(str(pair[0]), 0)) * _preview_xp(node, str(pair[1]), player_level)
	if int(counts.get("dungeon", 0)) > 0:
		total_xp += _preview_xp(node, "dungeon", player_level)
	if int(counts.get("settlement", 0)) > 0:
		total_xp += _preview_xp(node, "settlement", player_level)
	return {
		"format_version": FORMAT_VERSION,
		"region_id": str(node.get("stable_id", "")),
		"progression_band": band,
		"estimated_total_xp": total_xp,
		"content_count": int(counts.get("encounters", 0)) + int(counts.get("pois", 0)) + int(counts.get("world_events", 0)) + int(counts.get("lore", 0)) + int(counts.get("dungeon", 0)) + int(counts.get("settlement", 0))
	}

static func _preview_xp(node: Dictionary, content_type: String, player_level: int) -> int:
	var preview: Dictionary = build_reward_event(node, content_type, "preview", player_level, 0)
	return int(preview.get("xp", 0))

static func _gate_result(region_id: String, band: String, allowed: bool, reason: String, min_level: int, school_id: String, required_rank: int) -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"region_id": region_id,
		"progression_band": band,
		"allowed": allowed,
		"reason": reason,
		"min_level": min_level,
		"recommended_level": int((BAND_RULES.get(band, {}) as Dictionary).get("recommended_level", min_level)),
		"required_school": school_id,
		"required_school_rank": required_rank
	}

static func _denied(region_id: String, band: String, reason: String) -> Dictionary:
	return _gate_result(region_id, band, false, reason, 1, "", 0)
