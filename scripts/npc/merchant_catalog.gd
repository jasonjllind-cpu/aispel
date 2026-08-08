extends RefCounted
class_name MerchantCatalog

const MERCHANTS: Dictionary = {
	"orrik_relics": {
		"id": "orrik_relics",
		"display_name": "Orrik's Relics",
		"faction_id": "roadfolk",
		"currency": "Ancient Coin",
		"offers": [
			{"id": "moon_shard", "item": "Moon Shard", "buy_price": 3, "sell_price": 2},
			{"id": "warden_mail", "item": "Warden Mail", "buy_price": 8, "sell_price": 4},
			{"id": "rusty_sword", "item": "Rusty Sword", "buy_price": 5, "sell_price": 2}
		]
	}
}

static func get_merchant(merchant_id: String) -> Dictionary:
	var value: Variant = MERCHANTS.get(merchant_id, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

static func get_offer(merchant_id: String, offer_index: int) -> Dictionary:
	var merchant: Dictionary = get_merchant(merchant_id)
	var offers_value: Variant = merchant.get("offers", [])
	if not offers_value is Array:
		return {}
	var offers: Array = offers_value as Array
	if offer_index < 0 or offer_index >= offers.size() or not offers[offer_index] is Dictionary:
		return {}
	return (offers[offer_index] as Dictionary).duplicate(true)
