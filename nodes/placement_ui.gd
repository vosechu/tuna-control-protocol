extends Control

signal object_selected(object_type: StringName)
signal remove_toggled(active: bool)
signal placement_cancelled

const _FONT_SIZE: int = 5
const _BTN_MIN_SIZE: Vector2 = Vector2(40, 8)

var _selected_type: StringName = &""
var _remove_mode: bool = false
var _buttons: Dictionary = {}  # StringName -> Button


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(
		float(Constants.VIEWPORT_WIDTH) - 50.0,
		2.0,
	)
	vbox.add_theme_constant_override("separation", 1)
	add_child(vbox)

	var label := Label.new()
	label.text = "Place:"
	label.add_theme_font_size_override("font_size", _FONT_SIZE)
	vbox.add_child(label)

	_add_button(vbox, &"server_1u", "Server [1]")
	_add_button(vbox, &"cardboard_box", "Box [2]")
	_add_button(vbox, &"clothes_pile", "Pile [3]")
	_add_button(vbox, &"hum_device", "HUM [4]")
	_add_button(vbox, &"tuna_dispenser", "TUNA [5]")
	_add_button(vbox, &"tuna_button", "Button [6]")
	_add_button(vbox, &"arm", "ARM [7]")

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(spacer)

	var remove_btn := Button.new()
	remove_btn.text = "Remove [R]"
	remove_btn.toggle_mode = true
	remove_btn.add_theme_font_size_override("font_size", _FONT_SIZE)
	remove_btn.custom_minimum_size = _BTN_MIN_SIZE
	remove_btn.pressed.connect(_on_remove_pressed)
	vbox.add_child(remove_btn)
	_buttons[&"remove"] = remove_btn

	var cancel_label := Label.new()
	cancel_label.text = "Esc cancel"
	cancel_label.add_theme_font_size_override("font_size", 4)
	vbox.add_child(cancel_label)


func _add_button(
	parent: VBoxContainer,
	type: StringName,
	text: String,
) -> void:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", _FONT_SIZE)
	btn.custom_minimum_size = _BTN_MIN_SIZE
	btn.pressed.connect(_on_type_pressed.bind(type))
	parent.add_child(btn)
	_buttons[type] = btn


func _on_type_pressed(type: StringName) -> void:
	_remove_mode = false
	if _buttons.has(&"remove"):
		_buttons[&"remove"].button_pressed = false
	_selected_type = type
	object_selected.emit(type)


func _on_remove_pressed() -> void:
	_remove_mode = _buttons[&"remove"].button_pressed
	if _remove_mode:
		_selected_type = &""
	remove_toggled.emit(_remove_mode)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_on_type_pressed(&"server_1u")
			KEY_2:
				_on_type_pressed(&"cardboard_box")
			KEY_3:
				_on_type_pressed(&"clothes_pile")
			KEY_4:
				_on_type_pressed(&"hum_device")
			KEY_5:
				_on_type_pressed(&"tuna_dispenser")
			KEY_6:
				_on_type_pressed(&"tuna_button")
			KEY_7:
				_on_type_pressed(&"arm")
			KEY_R:
				var btn: Button = _buttons[&"remove"]
				btn.button_pressed = not btn.button_pressed
				_on_remove_pressed()
			KEY_ESCAPE:
				_selected_type = &""
				_remove_mode = false
				if _buttons.has(&"remove"):
					_buttons[&"remove"].button_pressed = false
				placement_cancelled.emit()


func get_selected_type() -> StringName:
	return _selected_type


func is_remove_mode() -> bool:
	return _remove_mode


func clear_selection() -> void:
	_selected_type = &""
	_remove_mode = false
	if _buttons.has(&"remove"):
		_buttons[&"remove"].button_pressed = false
