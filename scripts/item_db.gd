extends RefCounted
class_name ItemDB

const ITEMS := {
	"Rusty Sword": {
		"type": "weapon",
		"damage": 18,
		"description": "A worn iron sword. Reliable, if unimpressive."
	},
	"Moon Blade": {
		"type": "weapon",
		"damage": 30,
		"description": "A cold blue blade found among the old ruins."
	},
	"Crypt Fang": {
		"type": "weapon",
		"damage": 38,
		"description": "A narrow grave-steel blade recovered from Whispering Crypt."
	},
	"Warden Mail": {
		"type": "armor",
		"armor": 5,
		"description": "Heavy mail taken from a hollow warden."
	},
	"Ancient Coin": {
		"type": "material",
		"description": "Old currency from a forgotten kingdom."
	},
	"Moon Shard": {
		"type": "material",
		"description": "A pale shard that hums faintly in the dark."
	},
	"Old Key": {
		"type": "key",
		"description": "A corroded key bearing the crest of Whispering Crypt."
	}
}

static func get_item(item_name: String) -> Dictionary:
	return ITEMS.get(item_name, {"type": "material", "description": "Unknown item."})

static func get_type(item_name: String) -> String:
	return str(get_item(item_name).get("type", "material"))

static func get_damage(item_name: String) -> int:
	return int(get_item(item_name).get("damage", 0))

static func get_armor(item_name: String) -> int:
	return int(get_item(item_name).get("armor", 0))

static func is_equippable(item_name: String) -> bool:
	var item_type: String = get_type(item_name)
	return item_type == "weapon" or item_type == "armor"
