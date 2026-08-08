extends RefCounted
class_name NPCCatalog

const NPCS: Dictionary = {
	"elowen_wayfinder": {
		"id": "elowen_wayfinder",
		"display_name": "Elowen",
		"role": "Wayfinder of the Moon Shrine",
		"region_id": "starting_valley",
		"position": Vector3(-27.5, 0.015, -24.0),
		"body_color": Color("5c5873"),
		"accent_color": Color("9ea9ff"),
		"dialogue": [
			"The old roads are waking again. I can feel it beneath the stones.",
			"Blackwood lies west of the valley. Something there has begun answering the moon shrine."
		],
		"quest": {
			"id": "whispers_in_blackwood",
			"title": "Whispers in Blackwood",
			"objective_text": "Reach Blackwood and return to Elowen.",
			"objective_type": "discover_region",
			"objective_id": "blackwood",
			"offer_text": "Follow the western road into Blackwood. Return when you have felt what waits beneath its trees.",
			"active_text": "The western road is old, but it still remembers the way. Find Blackwood, then come back to me.",
			"complete_text": "So you heard it too. Take these moon shards. We will need their light before this is over.",
			"reward_item": "Moon Shard",
			"reward_amount": 2
		}
	},
	"orrik_relic_trader": {
		"id": "orrik_relic_trader",
		"display_name": "Orrik",
		"role": "Relic Trader",
		"region_id": "starting_valley",
		"position": Vector3(-12.5, 0.015, 7.0),
		"body_color": Color("6b5947"),
		"accent_color": Color("d6b16d"),
		"dialogue": [
			"Most folk see broken stone. I see things that survived long enough to become valuable.",
			"Bring back relics from the roads and ruins. Soon enough, I will have something worth trading for them."
		],
		"merchant_id": "orrik_relics"
	},
	"mara_blackwood": {
		"id": "mara_blackwood",
		"display_name": "Mara",
		"role": "Blackwood Scout",
		"region_id": "blackwood",
		"position": Vector3(1.0, 0.035, -17.0),
		"body_color": Color("35473a"),
		"accent_color": Color("7db46a"),
		"dialogue": [
			"Keep your voice low. The forest notices certainty faster than fear.",
			"The Fallen Chapel is not abandoned. It is only waiting."
		]
	},
	"hadrin_windscar": {
		"id": "hadrin_windscar",
		"display_name": "Hadrin",
		"role": "Beacon Keeper",
		"region_id": "windscar_highlands",
		"position": Vector3(25.0, 0.035, -15.0),
		"body_color": Color("726957"),
		"accent_color": Color("d7ca8d"),
		"dialogue": [
			"The beacon has not burned with true flame in generations.",
			"Yet every night its shadow points somewhere different."
		]
	},
	"sister_vael": {
		"id": "sister_vael",
		"display_name": "Sister Vael",
		"role": "Veilmoor Mourner",
		"region_id": "veilmoor",
		"position": Vector3(0.0, 0.035, -2.0),
		"body_color": Color("555169"),
		"accent_color": Color("9995e8"),
		"dialogue": [
			"Do not count the graves. The number changes when no one is looking.",
			"If the Pale Ring begins to sing, leave before it learns your name."
		]
	}
}

static func get_npc(npc_id: String) -> Dictionary:
	var value: Variant = NPCS.get(npc_id, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

static func get_npc_ids() -> Array[String]:
	var result: Array[String] = []
	for key in NPCS.keys():
		result.append(str(key))
	result.sort()
	return result

static func get_region_npcs(region_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for npc_id in get_npc_ids():
		var definition: Dictionary = get_npc(npc_id)
		if str(definition.get("region_id", "")) == region_id:
			result.append(definition)
	return result
