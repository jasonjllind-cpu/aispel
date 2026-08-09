extends Node

var world_state: Node
var layer: CanvasLayer
var panel: ColorRect
var seed_edit: LineEdit
var apply_button: Button
var random_button: Button
var previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world_state = get_node_or_null("/root/WorldState")
	_build_ui()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("world_seed_menu"):
		_toggle_menu()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		var is_f2: bool = key_event.keycode == KEY_F2 or key_event.physical_keycode == KEY_F2
		if key_event.pressed and not key_event.echo and is_f2:
			_toggle_menu()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_cancel") and panel != null and panel.visible:
		_close_menu()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 200
	add_child(layer)

	panel = ColorRect.new()
	panel.position = Vector2(155, 92)
	panel.size = Vector2(330, 174)
	panel.color = Color(0.026, 0.020, 0.060, 0.96)
	panel.visible = false
	layer.add_child(panel)

	var title := Label.new()
	title.position = Vector2(18, 14)
	title.size = Vector2(294, 24)
	title.text = "WORLD GENERATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	panel.add_child(title)

	var help := Label.new()
	help.position = Vector2(18, 43)
	help.size = Vector2(294, 36)
	help.text = "Same seed = same generated world\nF2 or G opens/closes this menu"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 10)
	panel.add_child(help)

	seed_edit = LineEdit.new()
	seed_edit.position = Vector2(32, 88)
	seed_edit.size = Vector2(266, 30)
	seed_edit.placeholder_text = "World seed"
	seed_edit.max_length = 10
	seed_edit.text = str(_current_seed())
	seed_edit.text_submitted.connect(_on_seed_submitted)
	panel.add_child(seed_edit)

	apply_button = Button.new()
	apply_button.position = Vector2(32, 128)
	apply_button.size = Vector2(126, 30)
	apply_button.text = "Generate"
	apply_button.pressed.connect(_apply_seed)
	panel.add_child(apply_button)

	random_button = Button.new()
	random_button.position = Vector2(172, 128)
	random_button.size = Vector2(126, 30)
	random_button.text = "Random seed"
	random_button.pressed.connect(_randomize_seed)
	panel.add_child(random_button)

func _toggle_menu() -> void:
	if panel == null:
		return
	if panel.visible:
		_close_menu()
	else:
		_open_menu()

func _open_menu() -> void:
	previous_mouse_mode = Input.mouse_mode
	panel.visible = true
	seed_edit.text = str(_current_seed())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	seed_edit.grab_focus()
	seed_edit.select_all()

func _close_menu() -> void:
	panel.visible = false
	seed_edit.release_focus()
	Input.mouse_mode = previous_mouse_mode

func _on_seed_submitted(_value: String) -> void:
	_apply_seed()

func _randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var current_seed: int = _current_seed()
	var seed_value: int = current_seed
	while seed_value == current_seed:
		seed_value = rng.randi_range(100000, 2147483000)
	seed_edit.text = str(seed_value)
	seed_edit.grab_focus()
	seed_edit.select_all()

func _apply_seed() -> void:
	var text_value: String = seed_edit.text.strip_edges()
	if not text_value.is_valid_int():
		seed_edit.text = str(_current_seed())
		return
	var seed_value: int = int(text_value)
	if seed_value == 0:
		seed_value = 8242601
	if world_state != null and world_state.has_method("new_world"):
		world_state.call("new_world", seed_value)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()

func _current_seed() -> int:
	if world_state != null:
		return int(world_state.get("world_seed"))
	return 8242601
