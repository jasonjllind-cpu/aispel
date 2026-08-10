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
		"poi_count": 4,
		"entry": Vector2(0, 52),
		"exit": Vector2(0, -82),
		"landmark": "Generated frontier",
		"slots": [
			# Only the immediate player footprint is fixed. Every former
			# prototype landmark is generated from the active world seed.
			{"id": "player_spawn", "center": Vector2(0, 24), "radius": 6.0, "feather": 14.0, "height_mode": "terrain"}
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
