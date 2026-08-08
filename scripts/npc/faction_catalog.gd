extends RefCounted
class_name FactionCatalog

const FACTIONS: Dictionary = {
	"moon_wardens": {
		"id": "moon_wardens",
		"display_name": "Moon Wardens",
		"description": "Keepers of shrines, old roads and moon-lit oaths."
	},
	"roadfolk": {
		"id": "roadfolk",
		"display_name": "Roadfolk",
		"description": "Traders, scavengers and travellers who keep the forgotten roads useful."
	},
	"blackwood_watchers": {
		"id": "blackwood_watchers",
		"display_name": "Blackwood Watchers",
		"description": "Scouts who survive by respecting what the forest refuses to explain."
	},
	"windscar_keep": {
		"id": "windscar_keep",
		"display_name": "Windscar Keepers",
		"description": "Guardians of the highland beacons and broken mountain paths."
	},
	"veil_mourners": {
		"id": "veil_mourners",
		"display_name": "Veil Mourners",
		"description": "Caretakers of graves and memories that should not be disturbed."
	}
}

static func get_faction(faction_id: String) -> Dictionary:
	var value: Variant = FACTIONS.get(faction_id, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

static func attitude_for(reputation: int) -> String:
	if reputation >= 40:
		return "Trusted"
	if reputation >= 15:
		return "Friendly"
	if reputation <= -40:
		return "Hostile"
	if reputation <= -15:
		return "Wary"
	return "Neutral"

static func price_multiplier(reputation: int) -> float:
	if reputation >= 40:
		return 0.80
	if reputation >= 15:
		return 0.90
	if reputation <= -40:
		return 1.30
	if reputation <= -15:
		return 1.15
	return 1.0
