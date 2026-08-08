extends Node
class_name MerchantSystem

const MERCHANT_CATALOG := preload("res://scripts/npc/merchant_catalog.gd")
const STALL_SCRIPT := preload("res://scripts/npc/merchant_stall.gd")
const TEX_STONE := preload("res://assets/textures/stone.svg")
const TEX_METAL := preload("res://assets/textures/metal.svg")

var world: Node3D
var faction_system: Node
var active_player: Node
var active_merchant_id: String = ""
var panel: ColorRect
var title_label: Label
var stock_label: Label
var status_label: Label

func _ready() -> void:
	add_to_group("merchant_system")
	call_deferred("_install")

func _install() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	world = get_parent() as Node3D
	_resolve_faction_system()
	if world == null:
		return
	_spawn_orrik_stall()
	if DisplayServer.get_name() != "headless":
		_build_ui()

func _input(event: InputEvent) -> void:
	if panel == null or not panel.visible or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		close_merchant()
		get_viewport().set_input_as_handled()
		return
	var offer_index: int = -1
	match key.keycode:
		KEY_1:
			offer_index = 0
		KEY_2:
			offer_index = 1
		KEY_3:
			offer_index = 2
	if offer_index < 0:
		return
	if key.shift_pressed:
		_sell_offer(offer_index)
	else:
		_buy_offer(offer_index)
	get_viewport().set_input_as_handled()

func open_merchant(merchant_id: String, player: Node) -> void:
	var merchant: Dictionary = MERCHANT_CATALOG.get_merchant(merchant_id)
	if merchant.is_empty() or player == null:
		return
	active_merchant_id = merchant_id
	active_player = player
	if panel != null:
		panel.visible = true
		status_label.text = ""
		_refresh_panel()

func close_merchant() -> void:
	if panel != null:
		panel.visible = false
	active_player = null
	active_merchant_id = ""

func _buy_offer(offer_index: int) -> void:
	if active_player == null:
		return
	var merchant: Dictionary = MERCHANT_CATALOG.get_merchant(active_merchant_id)
	var offer: Dictionary = MERCHANT_CATALOG.get_offer(active_merchant_id, offer_index)
	if offer.is_empty():
		return
	var currency: String = str(merchant.get("currency", "Ancient Coin"))
	var price: int = _adjusted_buy_price(int(offer.get("buy_price", 1)), str(merchant.get("faction_id", "")))
	if _item_count(active_player, currency) < price:
		_set_status("Not enough %s." % currency)
		return
	_remove_item(active_player, currency, price)
	var item_name: String = str(offer.get("item", ""))
	if active_player.has_method("receive_loot"):
		active_player.call("receive_loot", item_name, 1)
	_set_status("Bought %s for %d %s." % [item_name, price, currency])
	_refresh_panel()

func _sell_offer(offer_index: int) -> void:
	if active_player == null:
		return
	var merchant: Dictionary = MERCHANT_CATALOG.get_merchant(active_merchant_id)
	var offer: Dictionary = MERCHANT_CATALOG.get_offer(active_merchant_id, offer_index)
	if offer.is_empty():
		return
	var item_name: String = str(offer.get("item", ""))
	if _item_count(active_player, item_name) <= 0:
		_set_status("You do not have %s." % item_name)
		return
	var faction_id: String = str(merchant.get("faction_id", ""))
	var price: int = _adjusted_sell_price(int(offer.get("sell_price", 1)), faction_id)
	var currency: String = str(merchant.get("currency", "Ancient Coin"))
	_remove_item(active_player, item_name, 1)
	if active_player.has_method("receive_loot"):
		active_player.call("receive_loot", currency, price)
	_set_status("Sold %s for %d %s." % [item_name, price, currency])
	_refresh_panel()

func _adjusted_buy_price(base_price: int, faction_id: String) -> int:
	return max(1, int(round(float(base_price) * _price_multiplier(faction_id))))

func _adjusted_sell_price(base_price: int, faction_id: String) -> int:
	var multiplier: float = max(0.1, _price_multiplier(faction_id))
	return max(1, int(round(float(base_price) / multiplier)))

func _price_multiplier(faction_id: String) -> float:
	_resolve_faction_system()
	if is_instance_valid(faction_system) and faction_system.has_method("get_price_multiplier"):
		return float(faction_system.call("get_price_multiplier", faction_id))
	return 1.0

func _resolve_faction_system() -> void:
	if is_instance_valid(faction_system):
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var systems: Array[Node] = tree.get_nodes_in_group("faction_system")
	if not systems.is_empty():
		faction_system = systems[0]

func _item_count(player: Node, item_name: String) -> int:
	var inventory_value: Variant = player.get("inventory")
	if inventory_value is Dictionary:
		return int((inventory_value as Dictionary).get(item_name, 0))
	return 0

func _remove_item(player: Node, item_name: String, amount: int) -> bool:
	if amount <= 0:
		return true
	var inventory_value: Variant = player.get("inventory")
	if not inventory_value is Dictionary:
		return false
	var inventory: Dictionary = (inventory_value as Dictionary).duplicate(true)
	var current: int = int(inventory.get(item_name, 0))
	if current < amount:
		return false
	var remaining: int = current - amount
	if remaining <= 0:
		inventory.erase(item_name)
	else:
		inventory[item_name] = remaining
	player.set("inventory", inventory)
	if player.has_method("_refresh_hud"):
		player.call("_refresh_hud")
	return true

func _spawn_orrik_stall() -> void:
	if world == null or world.has_node("OrrikRelicStall"):
		return
	var merchant: Dictionary = MERCHANT_CATALOG.get_merchant("orrik_relics")
	var stall := StaticBody3D.new()
	stall.set_script(STALL_SCRIPT)
	stall.name = "OrrikRelicStall"
	stall.position = Vector3(-8.7, 0.25, 7.5)
	stall.set("merchant_id", "orrik_relics")
	stall.set("display_name", str(merchant.get("display_name", "Orrik's Relics")))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 0.7, 1.4)
	collision.shape = shape
	collision.position.y = 0.35
	stall.add_child(collision)
	if DisplayServer.get_name() != "headless":
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.4, 0.7, 1.4)
		mesh_instance.mesh = mesh
		mesh_instance.position.y = 0.35
		mesh_instance.material_override = _material(Color("5b4533"), TEX_STONE)
		stall.add_child(mesh_instance)
		for x in [-0.65, 0.0, 0.65]:
			var relic := MeshInstance3D.new()
			var relic_mesh := BoxMesh.new()
			relic_mesh.size = Vector3(0.28, 0.28, 0.28)
			relic.mesh = relic_mesh
			relic.position = Vector3(x, 0.88, 0)
			relic.material_override = _material(Color("a99b79"), TEX_METAL)
			stall.add_child(relic)
	world.add_child(stall)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 134
	panel = ColorRect.new()
	panel.position = Vector2(115, 72)
	panel.size = Vector2(410, 220)
	panel.color = Color(0.030, 0.022, 0.050, 0.96)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)

	title_label = Label.new()
	title_label.position = Vector2(14, 10)
	title_label.size = Vector2(382, 24)
	title_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(title_label)

	stock_label = Label.new()
	stock_label.position = Vector2(14, 42)
	stock_label.size = Vector2(382, 130)
	stock_label.add_theme_font_size_override("font_size", 11)
	panel.add_child(stock_label)

	status_label = Label.new()
	status_label.position = Vector2(14, 176)
	status_label.size = Vector2(382, 34)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 9)
	panel.add_child(status_label)
	world.add_child(layer)

func _refresh_panel() -> void:
	if panel == null or active_player == null:
		return
	var merchant: Dictionary = MERCHANT_CATALOG.get_merchant(active_merchant_id)
	var faction_id: String = str(merchant.get("faction_id", ""))
	var currency: String = str(merchant.get("currency", "Ancient Coin"))
	title_label.text = "%s  •  %d %s" % [str(merchant.get("display_name", "Merchant")), _item_count(active_player, currency), currency]
	var lines: Array[String] = []
	var offers: Array = merchant.get("offers", [])
	for i in range(offers.size()):
		if not offers[i] is Dictionary:
			continue
		var offer: Dictionary = offers[i] as Dictionary
		var buy_price: int = _adjusted_buy_price(int(offer.get("buy_price", 1)), faction_id)
		var sell_price: int = _adjusted_sell_price(int(offer.get("sell_price", 1)), faction_id)
		lines.append("[%d] %-18s Buy %d / Shift+%d Sell %d" % [i + 1, str(offer.get("item", "Unknown")), buy_price, i + 1, sell_price])
	lines.append("")
	lines.append("Esc — close")
	stock_label.text = "\n".join(lines)

func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text

func _material(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if texture != null:
		material.albedo_texture = texture
	return material