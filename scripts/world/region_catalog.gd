extends RefCounted
class_name RegionCatalog

const REGIONS: Dictionary = {
	"starting_valley": {
		"id": "starting_valley",
		"display_name": "Starting Valley",
		"biome": "green_highlands",
		"center": Vector3(0, 0, 0),
		"radius": 100.0,
		"external": true,
		"poi_count": 2,
		"entry": Vector2(0, 52),
		"exit": Vector2(0, -82),
		"landmark": "The Ruined Keep",
		"slots": [
			{"id": "player_spawn", "center": Vector2(0, 24), "radius": 14.0, "feather": 8.0, "height": 0.015},
			{"id": "abandoned_camp", "center": Vector2(-16, 4), "radius": 10.0, "feather": 6.0, "height": 0.015},
			{"id": "moon_shrine", "center": Vector2(-34, -28), "radius": 12.0, "feather": 7.0, "height": 0.015},
			{"id": "ruined_keep", "center": Vector2(28, -58), "radius": 24.0, "feather": 10.0, "height": 0.015},
			{"id": "lonely_watchtower", "center": Vector2(-58, -72), "radius": 14.0, "feather": 8.0, "height": 0.015},
			{"id": "whispering_crypt", "center": Vector2(72, -34), "radius": 17.0, "feather": 9.0, "height": 0.015},
			{"id": "starfall_grove", "center": Vector2(66, 46), "radius": 13.0, "feather": 8.0, "height": 0.015}
		]
	},
	"blackwood": {
		"id": "blackwood",
		"display_name": "Blackwood",
		"biome": "blackwood",
		"center": Vector3(-165, 0, -12),
		"radius": 62.0,
		"poi_count": 3,
		"entry": Vector2(50, 0),
		"exit": Vector2(0, -50),
		"landmark": "The Fallen Chapel",
		"slots": [
			{"id": "fallen_chapel", "center": Vector2(-12, -17), "radius": 14.0, "feather": 7.0, "height": 0.035}
		]
	},
	"windscar_highlands": {
		"id": "windscar_highlands",
		"display_name": "Windscar Highlands",
		"biome": "windscar_highlands",
		"center": Vector3(165, 0, -20),
		"radius": 62.0,
		"poi_count": 3,
		"entry": Vector2(-50, 0),
		"exit": Vector2(0, -50),
		"landmark": "The Windscar Beacon",
		"slots": [
			{"id": "windscar_beacon", "center": Vector2(14, -15), "radius": 13.0, "feather": 8.0, "height": 0.035}
		]
	},
	"veilmoor": {
		"id": "veilmoor",
		"display_name": "Veilmoor",
		"biome": "veilmoor",
		"center": Vector3(8, 0, -175),
		"radius": 62.0,
		"poi_count": 3,
		"entry": Vector2(0, 50),
		"exit": Vector2(-45, 0),
		"landmark": "The Pale Grave Ring",
		"slots": [
			{"id": "pale_grave_ring", "center": Vector2(0, -11), "radius": 15.0, "feather": 8.0, "height": 0.035}
		]
	}
}

static func get_region(region_id: String) -> Dictionary:
	var value: Variant = REGIONS.get(region_id, REGIONS["starting_valley"])
	return (value as Dictionary).duplicate(true)

static func has_region(region_id: String) -> bool:
	return REGIONS.has(region_id)

static func get_region_ids() -> Array[String]:
	var result: Array[String] = []
	for key in REGIONS.keys():
		result.append(str(key))
	result.sort()
	return result

static func get_slots(region_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var region: Dictionary = get_region(region_id)
	var slots_value: Variant = region.get("slots", [])
	if slots_value is Array:
		for value in slots_value:
			if value is Dictionary:
				result.append((value as Dictionary).duplicate(true))
	return result

static func get_center(region_id: String) -> Vector3:
	return get_region(region_id).get("center", Vector3.ZERO)

static func get_biome_id(region_id: String) -> String:
	return str(get_region(region_id).get("biome", "green_highlands"))
