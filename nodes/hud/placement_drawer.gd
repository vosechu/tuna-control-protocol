class_name PlacementDrawer extends Drawer

# Right-anchored placement drawer. Replaces the always-on placement
# column. Per docs/superpowers/specs/2026-05-09-drawer-migration-design.md.
#
# Implicit trigger: keys 1-7 open the drawer AND select the type in
# one motion. Pressing the same key on the active selection closes
# the drawer (state.select() handles the toggle).

signal object_selected(object_type: StringName)
signal remove_toggled(active: bool)
signal placement_cancelled

const _PLACEMENT_DRAWER_STATE_SCRIPT := preload(
	"res://engine/placement/placement_drawer_state.gd"
)
const _FONT_SIZE: int = 3
const _BTN_MIN_SIZE: Vector2 = Vector2(14, 4)
const _PANEL_WIDTH: int = 16
const _PANEL_HEIGHT: int = 50
const _KEY_TO_TYPE: Dictionary = {
	KEY_1: &"server_1u",
	KEY_2: &"cardboard_box",
	KEY_3: &"clothes_pile",
	KEY_4: &"hum_device",
	KEY_5: &"tuna_dispenser",
	KEY_6: &"tuna_button",
	KEY_7: &"arm",
}

var _state: PlacementDrawerState
var _buttons: Dictionary = {}  # StringName -> Button


func _ready() -> void:
	_state = _PLACEMENT_DRAWER_STATE_SCRIPT.new()
	custom_minimum_size = Vector2(_PANEL_WIDTH, _PANEL_HEIGHT)
	anchor_edge = Drawer.AnchorEdge.RIGHT
	open_position = Vector2(
		float(Constants.VIEWPORT_WIDTH - _PANEL_WIDTH),
		2.0,
	)
	_build_ui()
	# Drawer._ready() reads custom_minimum_size to compute the off-edge
	# position, so size + open_position must be set before super._ready().
	super._ready()


func _build_ui() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.10, 0.15, 0.92)
	bg.border_color = Color(0.25, 0.30, 0.40)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 1)
	var label := Label.new()
	label.text = "Place:"
	label.add_theme_font_size_override("font_size", _FONT_SIZE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(label)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", _FONT_SIZE)
	close_btn.custom_minimum_size = Vector2(6, 5)
	close_btn.pressed.connect(_close_drawer)
	header_row.add_child(close_btn)
	vbox.add_child(header_row)

	_add_button(vbox, &"server_1u", "Server [1]")
	_add_button(vbox, &"cardboard_box", "Box [2]")
	_add_button(vbox, &"clothes_pile", "Pile [3]")
	_add_button(vbox, &"hum_device", "HUM [4]")
	_add_button(vbox, &"tuna_dispenser", "TUNA [5]")
	_add_button(vbox, &"tuna_button", "Button [6]")
	_add_button(vbox, &"arm", "ARM [7]")

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
	cancel_label.add_theme_font_size_override("font_size", _FONT_SIZE)
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
	var was_selected: bool = (
		_state.is_open() and _state.selected_type == type
	)
	_state.select(type)
	_sync_remove_button()
	if was_selected:
		# select() closed the drawer because the same type was re-pressed.
		_close_drawer()
		return
	if not is_open():
		open()
	object_selected.emit(type)


func _on_remove_pressed() -> void:
	var active: bool = _buttons[&"remove"].button_pressed
	_state.set_remove_mode(active)
	if active and not is_open():
		open()
	remove_toggled.emit(active)


func _sync_remove_button() -> void:
	if _buttons.has(&"remove"):
		_buttons[&"remove"].button_pressed = _state.remove_mode


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key: int = (event as InputEventKey).keycode
	if _KEY_TO_TYPE.has(key):
		_on_type_pressed(_KEY_TO_TYPE[key])
		get_viewport().set_input_as_handled()
		return
	if key == KEY_R:
		var btn: Button = _buttons[&"remove"]
		btn.button_pressed = not btn.button_pressed
		_on_remove_pressed()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_ESCAPE and _state.is_open():
		_close_drawer()
		placement_cancelled.emit()
		get_viewport().set_input_as_handled()


# Single source of truth for closing — used by the X button, ESC,
# and the toggle path (re-pressing the active type).
func _close_drawer() -> void:
	if _state == null:
		return
	_state.close()
	_sync_remove_button()
	close()


# External surface (called by game_client.gd):

func get_selected_type() -> StringName:
	return _state.selected_type if _state != null else &""


func is_remove_mode() -> bool:
	return _state.remove_mode if _state != null else false


func clear_selection() -> void:
	if _state == null:
		return
	_state.clear_selection()
	_sync_remove_button()
