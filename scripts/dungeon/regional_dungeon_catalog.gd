extends RefCounted
class_name RegionalDungeonCatalog

const FORMAT_VERSION: int = 1

const THEMES: Dictionary = {
	"moon_vault": {"biomes": ["green_highlands"], "entrance_family": "sealed_stair", "room_family": "moon_catacomb", "min_depth": 1, "weight": 1.0, "tags": ["moon", "crypt"]},
	"root_crypt": {"biomes": ["blackwood"], "entrance_family": "root_cave_gate", "room_family": "rooted_catacomb", "min_depth": 2, "weight": 1.0, "tags": ["forest", "crypt"]},
	"cliff_tomb": {"biomes": ["windscar_highlands"], "entrance_family": "cliff_door", "room_family": "highland_tomb", "min_depth": 2, "weight": 1.0, "tags": ["highland", "tomb"]},
	"drowned_crypt": {"biomes": ["veilmoor"], "entrance_family": "sunken_arch", "room_family": "flooded_crypt", "min_depth": 2, "weight": 1.0, "tags": ["moor", "undead"]},
	"cinder_vault": {"biomes": ["ashen_fen"], "entrance_family": "charred_stair", "room_family": "cinder_vault", "min_depth": 2, "weight": 1.0, "tags": ["ash", "vault"]},
	"ice_barrow": {"biomes": ["frostmere"], "entrance_family": "ice_seal", "room_family": "frozen_barrow", "min_depth": 2, "weight": 1.0, "tags": ["frost", "barrow"]}
}

static func get_theme(theme_id: String) -> Dictionary:
	var value: Variant = THEMES.get(theme_id, {})
	if not value is Dictionary:
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["id"] = theme_id
	return result

static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in THEMES.keys():
		ids.append(str(key))
	ids.sort()
	return ids

static func validate_theme(theme: Dictionary) -> bool:
	return not str(theme.get("id", "")).is_empty() \
		and theme.get("biomes", []) is Array and not (theme.get("biomes", []) as Array).is_empty() \
		and not str(theme.get("entrance_family", "")).is_empty() \
		and not str(theme.get("room_family", "")).is_empty() \
		and int(theme.get("min_depth", -1)) >= 0 \
		and float(theme.get("weight", 0.0)) > 0.0

static func build_region_plan(world_seed: int, node: Dictionary) -> Dictionary:
	var stable_region_id: String = str(node.get("stable_id", ""))
	var biome_id: String = str(node.get("biome", "green_highlands"))
	var graph_depth: int = maxi(0, int(node.get("graph_depth", 0)))
	var candidates: Array[String] = []
	var total_weight: float = 0.0
	for theme_id in get_ids():
		var theme: Dictionary = get_theme(theme_id)
		if not (theme.get("biomes", []) as Array).has(biome_id) or graph_depth < int(theme.get("min_depth", 0)):
			continue
		candidates.append(theme_id)
		total_weight += float(theme.get("weight", 1.0))
	if candidates.is_empty() or stable_region_id.is_empty():
		return _empty_plan(stable_region_id)
	var profile: Dictionary = node.get("content_profile", {}) as Dictionary
	var secret_chance: float = clampf(float(profile.get("secret_chance", 0.18)), 0.0, 0.85)
	var spawn_chance: float = clampf(0.10 + secret_chance * 0.65 + float(mini(graph_depth, 6)) * 0.025, 0.12, 0.62)
	var seed_value: int = int(("%d:%s:dungeon_route:v%d" % [world_seed, stable_region_id, FORMAT_VERSION]).hash() & 0x7fffffff)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if rng.randf() > spawn_chance:
		return {"format_version": FORMAT_VERSION, "seed": seed_value, "region_id": stable_region_id, "enabled": false, "spawn_chance": spawn_chance, "stable_id": "", "persistent_state_id": "", "theme_id": "", "entrance_family": "", "room_family": ""}
	var roll: float = rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	var selected_id: String = candidates.back()
	for theme_id in candidates:
		cursor += float(get_theme(theme_id).get("weight", 1.0))
		if roll <= cursor:
			selected_id = theme_id
			break
	var selected: Dictionary = get_theme(selected_id)
	var dungeon_id: String = "dungeon:%s:%s" % [stable_region_id.trim_prefix("region:"), selected_id]
	return {
		"format_version": FORMAT_VERSION,
		"seed": seed_value,
		"region_id": stable_region_id,
		"enabled": true,
		"spawn_chance": spawn_chance,
		"stable_id": dungeon_id,
		"persistent_state_id": "state:%s" % dungeon_id,
		"theme_id": selected_id,
		"entrance_family": str(selected.get("entrance_family", "")),
		"room_family": str(selected.get("room_family", "")),
		"graph_depth": graph_depth,
		"tags": (selected.get("tags", []) as Array).duplicate()
	}

static func _empty_plan(stable_region_id: String) -> Dictionary:
	return {"format_version": FORMAT_VERSION, "seed": 0, "region_id": stable_region_id, "enabled": false, "spawn_chance": 0.0, "stable_id": "", "persistent_state_id": "", "theme_id": "", "entrance_family": "", "room_family": ""}
