extends Node
class_name NetworkMenu

const DEFAULT_PORT: int = 27144

var network_session: Node
var panel: ColorRect
var address_edit: LineEdit
var port_edit: LineEdit
var status_label: Label
var peers_label: Label
var previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var elapsed: float = 0.0

func _ready() -> void:
	add_to_group("network_menu")
	call_deferred("_install")

func _install() -> void:
	await get_tree().process_frame
	var parent := get_parent()
	if parent != null:
		network_session = parent.get_node_or_null("NetworkSession")
	if network_session == null:
		return
	if network_session.get("connected") != true and str(network_session.get("session_mode")) == "singleplayer":
		network_session.call("start_singleplayer")
	if DisplayServer.get_name() != "headless":
		_build_ui()
	_refresh_status()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.4:
		return
	elapsed = 0.0
	_refresh_status()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_N:
		toggle_menu()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and panel != null and panel.visible:
		close_menu()
		get_viewport().set_input_as_handled()

func toggle_menu() -> void:
	if panel == null:
		return
	if panel.visible:
		close_menu()
	else:
		open_menu()

func open_menu() -> void:
	if panel == null:
		return
	previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.visible = true
	_refresh_status()

func close_menu() -> void:
	if panel == null:
		return
	panel.visible = false
	Input.mouse_mode = previous_mouse_mode if previous_mouse_mode != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED

func start_singleplayer() -> Dictionary:
	if network_session == null:
		return {"ok": false, "error": "session_missing"}
	var result: Dictionary = network_session.call("start_singleplayer")
	_set_status_from_result(result, "Singleplayer active")
	return result

func host_game() -> Dictionary:
	if network_session == null:
		return {"ok": false, "error": "session_missing"}
	var port: int = _selected_port()
	var result: Dictionary = network_session.call("host_game", port, 4)
	if result.get("ok", false):
		status_label.text = "Hosting on port %d\nLAN address: %s" % [port, _local_address_hint()]
	else:
		_set_status_from_result(result, "Could not host")
	return result

func join_game() -> Dictionary:
	if network_session == null:
		return {"ok": false, "error": "session_missing"}
	var address: String = "127.0.0.1" if address_edit == null else address_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var result: Dictionary = network_session.call("join_game", address, _selected_port())
	if result.get("ok", false):
		status_label.text = "Connecting to %s:%d..." % [address, _selected_port()]
	else:
		_set_status_from_result(result, "Could not join")
	return result

func _selected_port() -> int:
	if port_edit == null:
		return DEFAULT_PORT
	var text: String = port_edit.text.strip_edges()
	return clampi(int(text) if text.is_valid_int() else DEFAULT_PORT, 1, 65535)

func _refresh_status() -> void:
	if network_session == null:
		return
	if peers_label != null:
		var peers_value: Variant = network_session.get("peer_players")
		var peer_count: int = (peers_value as Dictionary).size() if peers_value is Dictionary else 0
		peers_label.text = "Players: %d / %d" % [max(1, peer_count), int(network_session.get("max_players"))]
	if status_label == null:
		return
	var mode: String = str(network_session.get("session_mode"))
	var connected: bool = network_session.get("connected") == true
	if mode == "singleplayer":
		status_label.text = "Singleplayer — local authoritative world"
	elif mode == "host":
		status_label.text = "Hosting on port %d\nLAN address: %s" % [int(network_session.get("listen_port")), _local_address_hint()]
	elif mode == "client" and connected:
		status_label.text = "Connected to host"
	elif mode == "client":
		status_label.text = "Connecting to host..."

func _set_status_from_result(result: Dictionary, success_text: String) -> void:
	if status_label == null:
		return
	if result.get("ok", false):
		status_label.text = success_text
	else:
		status_label.text = "%s (%s)" % [success_text, str(result.get("error", "unknown"))]

func _local_address_hint() -> String:
	for address in IP.get_local_addresses():
		var value := str(address)
		if value.contains(":") or value.begins_with("127.") or value.begins_with("169.254."):
			continue
		return value
	return "127.0.0.1"

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 150

	var hint := Label.new()
	hint.position = Vector2(540, 8)
	hint.size = Vector2(90, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.text = "N • CO-OP"
	hint.add_theme_font_size_override("font_size", 9)
	layer.add_child(hint)

	panel = ColorRect.new()
	panel.position = Vector2(110, 55)
	panel.size = Vector2(420, 255)
	panel.color = Color(0.025, 0.020, 0.055, 0.97)
	panel.visible = false
	layer.add_child(panel)

	var title := Label.new()
	title.position = Vector2(16, 12)
	title.size = Vector2(388, 24)
	title.text = "CO-OP — 1–4 PLAYERS"
	title.add_theme_font_size_override("font_size", 15)
	panel.add_child(title)

	var address_label := Label.new()
	address_label.position = Vector2(16, 48)
	address_label.size = Vector2(80, 18)
	address_label.text = "Host IP"
	panel.add_child(address_label)
	address_edit = LineEdit.new()
	address_edit.position = Vector2(96, 44)
	address_edit.size = Vector2(190, 28)
	address_edit.text = "127.0.0.1"
	panel.add_child(address_edit)

	var port_label := Label.new()
	port_label.position = Vector2(298, 48)
	port_label.size = Vector2(38, 18)
	port_label.text = "Port"
	panel.add_child(port_label)
	port_edit = LineEdit.new()
	port_edit.position = Vector2(338, 44)
	port_edit.size = Vector2(66, 28)
	port_edit.text = str(DEFAULT_PORT)
	panel.add_child(port_edit)

	var single_button := Button.new()
	single_button.position = Vector2(16, 86)
	single_button.size = Vector2(120, 32)
	single_button.text = "Singleplayer"
	single_button.pressed.connect(start_singleplayer)
	panel.add_child(single_button)

	var host_button := Button.new()
	host_button.position = Vector2(150, 86)
	host_button.size = Vector2(120, 32)
	host_button.text = "Host Game"
	host_button.pressed.connect(host_game)
	panel.add_child(host_button)

	var join_button := Button.new()
	join_button.position = Vector2(284, 86)
	join_button.size = Vector2(120, 32)
	join_button.text = "Join Game"
	join_button.pressed.connect(join_game)
	panel.add_child(join_button)

	status_label = Label.new()
	status_label.position = Vector2(16, 134)
	status_label.size = Vector2(388, 50)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 10)
	panel.add_child(status_label)

	peers_label = Label.new()
	peers_label.position = Vector2(16, 190)
	peers_label.size = Vector2(180, 20)
	peers_label.add_theme_font_size_override("font_size", 10)
	panel.add_child(peers_label)

	var close_button := Button.new()
	close_button.position = Vector2(284, 207)
	close_button.size = Vector2(120, 30)
	close_button.text = "Close"
	close_button.pressed.connect(close_menu)
	panel.add_child(close_button)

	var footer := Label.new()
	footer.position = Vector2(16, 220)
	footer.size = Vector2(250, 20)
	footer.text = "Host shares the world seed and authoritative state."
	footer.add_theme_font_size_override("font_size", 8)
	panel.add_child(footer)

	get_parent().add_child(layer)
