extends RefCounted
class_name EncounterArchetypeCatalog

const FORMAT_VERSION: int = 1

const ARCHETYPES: Dictionary = {
	"road_wardens": {"faction": "wardens", "roles": ["swordsman", "archer"], "min_group": 2, "max_group": 4, "threat": 0.30, "tags": ["road", "patrol"]},
	"relic_scavengers": {"faction": "scavengers", "roles": ["raider", "slinger"], "min_group": 2, "max_group": 5, "threat": 0.34, "tags": ["ruins", "loot"]},
	"moonbound_wolves": {"faction": "beasts", "roles": ["wolf"], "min_group": 2, "max_group": 5, "threat": 0.32, "tags": ["beast", "moon"]},
	"wandering_warden": {"faction": "wardens", "roles": ["warden"], "min_group": 1, "max_group": 2, "threat": 0.26, "tags": ["road", "wanderer"]},
	"blackwood_ambush": {"faction": "blackwood", "roles": ["stalker", "archer"], "min_group": 3, "max_group": 5, "threat": 0.46, "tags": ["forest", "ambush"]},
	"thorn_cult": {"faction": "thorn_cult", "roles": ["cultist", "hexer"], "min_group": 2, "max_group": 4, "threat": 0.50, "tags": ["cult", "magic"]},
	"blackwood_stalkers": {"faction": "blackwood", "roles": ["stalker"], "min_group": 2, "max_group": 4, "threat": 0.48, "tags": ["forest", "hunter"]},
	"restless_hunters": {"faction": "restless", "roles": ["hunter", "hound"], "min_group": 2, "max_group": 4, "threat": 0.44, "tags": ["forest", "undead"]},
	"highland_guardians": {"faction": "stone_guardians", "roles": ["guardian", "archer"], "min_group": 2, "max_group": 4, "threat": 0.48, "tags": ["highland", "guard"]},
	"storm_raiders": {"faction": "storm_raiders", "roles": ["raider", "spearman"], "min_group": 3, "max_group": 5, "threat": 0.52, "tags": ["storm", "raid"]},
	"stonebound": {"faction": "stonebound", "roles": ["stonebound"], "min_group": 1, "max_group": 3, "threat": 0.58, "tags": ["construct", "ancient"]},
	"restless_dead": {"faction": "restless", "roles": ["skeleton", "wraith"], "min_group": 3, "max_group": 5, "threat": 0.52, "tags": ["undead", "grave"]},
	"pale_wardens": {"faction": "pale_wardens", "roles": ["warden", "wraith"], "min_group": 2, "max_group": 4, "threat": 0.56, "tags": ["undead", "guard"]},
	"bog_lurkers": {"faction": "bog_beasts", "roles": ["lurker"], "min_group": 2, "max_group": 4, "threat": 0.54, "tags": ["bog", "beast"]},
	"fen_reavers": {"faction": "fen_reavers", "roles": ["reaver", "slinger"], "min_group": 3, "max_group": 5, "threat": 0.58, "tags": ["fen", "raid"]},
	"cinder_hounds": {"faction": "beasts", "roles": ["cinder_hound"], "min_group": 2, "max_group": 5, "threat": 0.60, "tags": ["fen", "fire", "beast"]},
	"bog_witches": {"faction": "bog_witches", "roles": ["witch", "thrall"], "min_group": 2, "max_group": 4, "threat": 0.64, "tags": ["fen", "magic"]},
	"frostbound": {"faction": "frostbound", "roles": ["frostbound", "archer"], "min_group": 2, "max_group": 4, "threat": 0.62, "tags": ["frost", "ancient"]},
	"white_wolves": {"faction": "beasts", "roles": ["white_wolf"], "min_group": 2, "max_group": 5, "threat": 0.56, "tags": ["frost", "beast"]},
	"lake_wraiths": {"faction": "restless", "roles": ["lake_wraith"], "min_group": 1, "max_group": 3, "threat": 0.66, "tags": ["frost", "wraith", "lake"]}
}

static func get_archetype(archetype_id: String) -> Dictionary:
	var value: Variant = ARCHETYPES.get(archetype_id, {})
	if not value is Dictionary:
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["id"] = archetype_id
	return result

static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in ARCHETYPES.keys():
		ids.append(str(key))
	ids.sort()
	return ids

static func validate_archetype(archetype: Dictionary) -> bool:
	if str(archetype.get("id", "")).is_empty() or str(archetype.get("faction", "")).is_empty():
		return false
	var roles: Variant = archetype.get("roles", [])
	var tags: Variant = archetype.get("tags", [])
	if not roles is Array or (roles as Array).is_empty() or not tags is Array or (tags as Array).is_empty():
		return false
	var min_group: int = int(archetype.get("min_group", 0))
	var max_group: int = int(archetype.get("max_group", 0))
	return min_group > 0 and max_group >= min_group and float(archetype.get("threat", 0.0)) > 0.0

static func build_region_plan(world_seed: int, stable_region_id: String, content_theme: Dictionary, content_profile: Dictionary) -> Dictionary:
	var palette_value: Variant = content_theme.get("encounter_palette", [])
	if not palette_value is Array:
		return {"format_version": FORMAT_VERSION, "entries": [], "total_threat": 0.0}
	var palette: Array = palette_value as Array
	if palette.is_empty():
		return {"format_version": FORMAT_VERSION, "entries": [], "total_threat": 0.0}
	var budget: int = maxi(1, int(content_profile.get("encounter_budget", 1)))
	var danger: float = clampf(float(content_profile.get("danger", 0.3)), 0.0, 1.0)
	var seed_value: int = int(("%d:%s:encounter_plan:v%d" % [world_seed, stable_region_id, FORMAT_VERSION]).hash() & 0x7fffffff)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shuffled: Array[String] = []
	for value in palette:
		var archetype_id: String = str(value)
		if ARCHETYPES.has(archetype_id):
			shuffled.append(archetype_id)
	for i in range(shuffled.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, i)
		var tmp: String = shuffled[i]
		shuffled[i] = shuffled[swap_index]
		shuffled[swap_index] = tmp
	if shuffled.is_empty():
		return {"format_version": FORMAT_VERSION, "entries": [], "total_threat": 0.0}
	var entries: Array[Dictionary] = []
	var total_threat: float = 0.0
	for slot_index in range(budget):
		var archetype_id: String = shuffled[slot_index % shuffled.size()]
		var archetype: Dictionary = get_archetype(archetype_id)
		var min_group: int = int(archetype.get("min_group", 1))
		var max_group: int = int(archetype.get("max_group", min_group))
		var group_size: int = rng.randi_range(min_group, max_group)
		var base_threat: float = float(archetype.get("threat", 0.25))
		var scaled_threat: float = base_threat * (0.75 + danger * 0.65) * float(group_size)
		var entry_id: String = "encounter_plan:%s:%d:%s" % [stable_region_id.trim_prefix("region:"), slot_index, archetype_id]
		entries.append({
			"stable_id": entry_id,
			"archetype_id": archetype_id,
			"faction": str(archetype.get("faction", "unknown")),
			"roles": (archetype.get("roles", []) as Array).duplicate(),
			"group_size": group_size,
			"threat": scaled_threat,
			"persistent_state_id": "state:%s" % entry_id
		})
		total_threat += scaled_threat
	return {
		"format_version": FORMAT_VERSION,
		"seed": seed_value,
		"region_id": stable_region_id,
		"entries": entries,
		"total_threat": total_threat
	}
