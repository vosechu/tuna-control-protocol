extends Camera2D

const PAN_SPEED: float = 200.0
const ZOOM_LEVELS: Array[Vector2] = [
	Vector2(2.0, 2.0),    # Close-up: floor + bottom racks fill the screen
	Vector2(1.0, 1.0),    # Full view: all racks visible
	Vector2(0.5, 0.5),    # Overview: zoomed out
]

var _zoom_index: int = 0


func _ready() -> void:
	var total_width: float = Constants.RACK_COUNT * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX)
	# Center on the bottom of the racks + floor where animals are
	var floor_center_y: float = float(
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PX + Constants.FLOOR_HEIGHT_PX / 2
	)
	position = Vector2(total_width / 2.0, floor_center_y)
	# Start zoomed in so animals are visible
	zoom = ZOOM_LEVELS[0]


func _process(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("ui_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("ui_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("ui_up"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("ui_down"):
		input_dir.y += 1.0
	position += input_dir * PAN_SPEED * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_change_zoom(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_change_zoom(1)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_PAGEUP:
			_change_zoom(-1)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_PAGEDOWN:
			_change_zoom(1)


func _change_zoom(direction: int) -> void:
	_zoom_index = clampi(_zoom_index + direction, 0, ZOOM_LEVELS.size() - 1)
	zoom = ZOOM_LEVELS[_zoom_index]
