extends SceneTree

const WORLD_STATE_SCRIPT := preload("res://scripts/core/world_state.gd")
const FACTION_CATALOG := preload("res://scripts/npc/faction_catalog.gd")
const FACTION_SYSTEM_SCRIPT := preload("res://scripts/npc/faction_system.gd")
const MERCHANT_CATALOG := preload("res://scripts/npc/merchant_catalog.gd")
const MERCHANT_SYSTEM_SCRIPT := preload("res://scripts/npc/merchant_system.gd")
const MERCHANT_STALL_SCRIPT := preload("res://scripts/npc/merchant_stall.gd")

func _init() -> void:
	var failed := false
	failed = not _test_faction_catalog() or failed
	failed = not _test_reputation_persistence_and_prices() or failed
	failed = not _test_merchant_catalog_and_stable_id() or failed
	if failed:
		printerr("LIVING_WORLD_FOUNDATION_FAILED")
		quit(1)
		return
	print("LIVING_WORLD_FOUNDATION_OK factions=%d offers=%d" % [FACTION_CATALOG.FACTIONS.size(), _offer_count()])
	quit(0)

func _test_faction_catalog() -> bool:
	if FACTION_CATALOG.FACTIONS.size() < 5:
		printerr("Faction catalog unexpectedly small")
		return false
	if FACTION_CATALOG.attitude_for(20) != "Friendly":
		printerr("Friendly faction threshold mismatch")
		return false
	if FACTION_CATALOG.attitude_for(-45) != "Hostile":
		printerr("Hostile faction threshold mismatch")
		return false
	if not is_equal_approx(FACTION_CATALOG.price_multiplier(45), 0.80):
		printerr("Trusted price multiplier mismatch")
		return false
	if not is_equal_approx(FACTION_CATALOG.price_multiplier(-45), 1.30):
		printerr("Hostile price multiplier mismatch")
		return false
	return true

func _test_reputation_persistence_and_prices() -> bool:
	var world_state := Node.new()
	world_state.set_script(WORLD_STATE_SCRIPT)
	world_state.name = "TestWorldState"
	get_root().add_child(world_state)

	var factions := Node.new()
	factions.set_script(FACTION_SYSTEM_SCRIPT)
	get_root().add_child(factions)
	factions.set("world_state", world_state)
	factions.add_to_group("faction_system")

	if int(factions.call("change_reputation", "roadfolk", 20, "test")) != 20:
		printerr("Faction reputation did not change")
		return false
	if int(factions.call("get_reputation", "roadfolk")) != 20:
		printerr("Faction reputation was not persisted")
		return false
	if str(factions.call("get_attitude", "roadfolk")) != "Friendly":
		printerr("Faction attitude did not react to reputation")
		return false

	var merchant := Node.new()
	merchant.set_script(MERCHANT_SYSTEM_SCRIPT)
	get_root().add_child(merchant)
	if int(merchant.call("_adjusted_buy_price", 10, "roadfolk")) != 9:
		printerr("Friendly merchant buy price mismatch")
		return false
	if int(merchant.call("_adjusted_sell_price", 10, "roadfolk")) != 11:
		printerr("Friendly merchant sell price mismatch")
		return false

	factions.call("change_reputation", "roadfolk", 30, "test_trusted")
	if int(merchant.call("_adjusted_buy_price", 10, "roadfolk")) != 8:
		printerr("Trusted merchant buy price mismatch")
		return false

	merchant.queue_free()
	factions.queue_free()
	world_state.queue_free()
	return true

func _test_merchant_catalog_and_stable_id() -> bool:
	var merchant: Dictionary = MERCHANT_CATALOG.get_merchant("orrik_relics")
	if merchant.is_empty():
		printerr("Orrik merchant definition missing")
		return false
	if str(merchant.get("currency", "")) != "Ancient Coin":
		printerr("Orrik merchant currency mismatch")
		return false
	var offers_value: Variant = merchant.get("offers", [])
	if not offers_value is Array or (offers_value as Array).size() < 3:
		printerr("Orrik merchant offers missing")
		return false
	for offer_value in offers_value as Array:
		if not offer_value is Dictionary:
			printerr("Merchant offer is not a dictionary")
			return false
		var offer: Dictionary = offer_value as Dictionary
		if str(offer.get("item", "")).is_empty() or int(offer.get("buy_price", 0)) <= 0 or int(offer.get("sell_price", 0)) <= 0:
			printerr("Merchant offer data invalid")
			return false

	var stall := StaticBody3D.new()
	stall.set_script(MERCHANT_STALL_SCRIPT)
	stall.set("merchant_id", "orrik_relics")
	if str(stall.get_meta("stable_id", "")) != "merchant:orrik_relics":
		printerr("Merchant stable ID mismatch")
		return false
	stall.queue_free()
	return true

func _offer_count() -> int:
	var merchant: Dictionary = MERCHANT_CATALOG.get_merchant("orrik_relics")
	var offers: Variant = merchant.get("offers", [])
	return (offers as Array).size() if offers is Array else 0
