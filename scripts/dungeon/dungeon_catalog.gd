extends RefCounted
class_name DungeonCatalog

const DUNGEONS: Dictionary = {
	"moon_catacombs": {
		"id": "moon_catacombs",
		"display_name": "Moon Catacombs",
		"region_id": "starting_valley",
		"world_entry": Vector3(62.0, 0.02, -43.0),
		"world_return": Vector3(60.0, 1.0, -39.0),
		"interior_origin": Vector3(0.0, -48.0, 1100.0),
		"room_count": 7,
		"room_size": 12.0,
		"grid_step": 18.0,
		"boss_id": "hollow_king",
		"boss_name": "The Hollow King",
		"reward_item": "Moon Shard",
		"reward_amount": 5,
		"accent": Color("8f9dff"),
		"stone": Color("4e4d60")
	}
}

static func get_dungeon(dungeon_id: String) -> Dictionary:
	var value: Variant = DUNGEONS.get(dungeon_id, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

static func get_dungeon_ids() -> Array[String]:
	var result: Array[String] = []
	for key in DUNGEONS.keys():
		result.append(str(key))
	result.sort()
	return result
