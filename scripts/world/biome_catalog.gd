extends RefCounted
class_name BiomeCatalog

const BIOMES: Dictionary = {
	"green_highlands": {
		"display_name": "Green Highlands",
		"ground_color": Color("4f7545"),
		"road_color": Color("827760"),
		"tree_trunk": Color("5b3826"),
		"tree_leaf": Color("285238"),
		"accent": Color("c9d69a"),
		"rock_color": Color("706d72"),
		"tree_density": 0.42,
		"rock_density": 0.22,
		"elevation": 1.2,
		"encounter_profile": "warden_patrol"
	},
	"blackwood": {
		"display_name": "Blackwood",
		"ground_color": Color("263d2d"),
		"road_color": Color("554f49"),
		"tree_trunk": Color("432a24"),
		"tree_leaf": Color("14281e"),
		"accent": Color("7e9a75"),
		"rock_color": Color("494950"),
		"tree_density": 0.78,
		"rock_density": 0.16,
		"elevation": 0.4,
		"encounter_profile": "blackwood_ambush"
	},
	"veilmoor": {
		"display_name": "Veilmoor",
		"ground_color": Color("49465a"),
		"road_color": Color("68616c"),
		"tree_trunk": Color("3b3038"),
		"tree_leaf": Color("2d3342"),
		"accent": Color("8c8be2"),
		"rock_color": Color("5e5b6d"),
		"tree_density": 0.30,
		"rock_density": 0.34,
		"elevation": 0.7,
		"encounter_profile": "restless_dead"
	},
	"windscar_highlands": {
		"display_name": "Windscar Highlands",
		"ground_color": Color("64764b"),
		"road_color": Color("91846d"),
		"tree_trunk": Color("65402c"),
		"tree_leaf": Color("425e3a"),
		"accent": Color("c4b98c"),
		"rock_color": Color("77767d"),
		"tree_density": 0.20,
		"rock_density": 0.55,
		"elevation": 2.4,
		"encounter_profile": "highland_guardians"
	}
}

static func get_biome(biome_id: String) -> Dictionary:
	var value: Variant = BIOMES.get(biome_id, BIOMES["green_highlands"])
	return (value as Dictionary).duplicate(true)

static func has_biome(biome_id: String) -> bool:
	return BIOMES.has(biome_id)
