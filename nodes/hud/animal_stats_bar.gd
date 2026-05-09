extends HBoxContainer

const DESIRE_COLORS: Dictionary = {
	&"warmth":    Color(0.85, 0.35, 0.20),  # warm orange — heat
	&"comfort":   Color(0.45, 0.65, 0.85),  # soft blue — softness
	&"curiosity": Color(0.60, 0.80, 0.30),  # yellow-green — exploration
	&"hunger":    Color(0.90, 0.55, 0.20),  # amber — appetite
	&"social":    Color(0.95, 0.50, 0.65),  # pink — companionship
	&"quiet":     Color(0.30, 0.45, 0.75),  # deep blue — auditory rest
	&"peace":     Color(0.65, 0.50, 0.85),  # lavender — visual rest
	&"safety":    Color(0.40, 0.75, 0.45),  # forest green — security
}
const _BAR_BG := Color(0.15, 0.15, 0.2)
const BAR_WIDTH: int = 14
const BAR_HEIGHT: int = 2

var _db: GameStateDB
var _animal_ids: Array[int] = []
var _panels: Dictionary = {}  # entity_id -> PanelContainer
var _camera: Camera2D


func initialize(db: GameStateDB, camera: Camera2D) -> void:
	_db = db
	_camera = camera
	_build_panels()


func _build_panels() -> void:
	# sprite_config filter excludes objects that now carry species (e.g.
	# scenario-spawned hum_device) — only sprite-bearing entities get a panel.
	_animal_ids = _db.get_entities_with(&"sprite_config")
	for entity_id: int in _animal_ids:
		var panel := _create_panel(entity_id)
		add_child(panel)
		_panels[entity_id] = panel


func _create_panel(entity_id: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.7)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	style.content_margin_left = 1
	style.content_margin_right = 1
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	var species: Dictionary = _db.get_component(
		entity_id, &"species",
	)
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = String(species.get(&"name", &"???"))
	name_label.add_theme_font_size_override("font_size", 6)
	var name_color := Color(0.9, 0.8, 0.6)
	if _db.has_component(entity_id, &"hud_color"):
		var c: Dictionary = _db.get_component(entity_id, &"hud_color")
		name_color = Color(c[&"r"], c[&"g"], c[&"b"])
	name_label.add_theme_color_override("font_color", name_color)
	vbox.add_child(name_label)

	var bars := VBoxContainer.new()
	bars.name = "Bars"
	bars.add_theme_constant_override("separation", 0)
	vbox.add_child(bars)

	if _db.has_component(entity_id, &"desires"):
		var desires: Dictionary = _db.get_component(
			entity_id, &"desires",
		)
		for dtype: StringName in desires:
			var color: Color = DESIRE_COLORS.get(
				dtype, Color(0.5, 0.5, 0.5),
			)
			_add_bar(bars, String(dtype) + "Bar", color)

	var activity_label := Label.new()
	activity_label.name = "ActivityLabel"
	activity_label.add_theme_font_size_override("font_size", 5)
	activity_label.add_theme_color_override(
		"font_color", Color(0.75, 0.75, 0.8),
	)
	activity_label.text = ""
	vbox.add_child(activity_label)

	panel.gui_input.connect(
		func(event: InputEvent) -> void:
			_on_panel_clicked(event, entity_id),
	)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return panel


func _add_bar(
	parent: VBoxContainer,
	bar_name: String,
	color: Color,
) -> void:
	var bar := ColorRect.new()
	bar.name = bar_name
	bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar.color = _BAR_BG
	parent.add_child(bar)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = color
	fill.size = Vector2(0, BAR_HEIGHT)
	fill.position = Vector2.ZERO
	bar.add_child(fill)


func _on_panel_clicked(
	event: InputEvent, entity_id: int,
) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _db.has_entity(entity_id):
		return
	# Per spec: portrait click fires inspect AND centers the camera.
	# Co-located here so the drawer never reaches into camera state.
	Events.entity_inspect_opened.emit(entity_id)
	var pos: Dictionary = _db.get_component(
		entity_id, &"position",
	)
	_camera.position = Vector2(
		float(pos[&"x"]) + float(Constants.RACK_WIDTH_PX / 2),
		float(pos[&"y"]),
	)


func _process(_delta: float) -> void:
	if _db == null:
		return
	for entity_id: int in _animal_ids:
		if not _panels.has(entity_id):
			continue
		if not _db.has_entity(entity_id):
			continue
		_update_panel(_panels[entity_id], entity_id)


func _update_panel(
	panel: PanelContainer, entity_id: int,
) -> void:
	var vbox: VBoxContainer = panel.get_child(0)
	if _db.has_component(entity_id, &"desires"):
		var desires: Dictionary = _db.get_component(
			entity_id, &"desires",
		)
		# vbox children: [0]=NameLabel, [1]=Bars, [2]=ActivityLabel
		var bars: VBoxContainer = vbox.get_child(1)
		var bar_idx: int = 0
		for dtype: StringName in desires:
			if bar_idx >= bars.get_child_count():
				break
			_update_bar(bars.get_child(bar_idx), desires[dtype])
			bar_idx += 1
	if _db.has_component(entity_id, &"ai_state"):
		var ai: Dictionary = _db.get_component(entity_id, &"ai_state")
		var activity_label: Label = vbox.get_child(2)
		activity_label.text = String(ai[&"state"]).to_lower()
		# Settled entities tint warmer to flag "deliberately resting" —
		# distinct from idle ambient states.
		if _db.has_component(entity_id, &"settled_in"):
			activity_label.add_theme_color_override(
				"font_color", Color(0.95, 0.85, 0.55),
			)
		elif ai.get(&"meta_state", &"AMBIENT") == &"GOAL_DIRECTED":
			activity_label.add_theme_color_override(
				"font_color", Color(0.85, 0.7, 0.95),
			)
		else:
			activity_label.add_theme_color_override(
				"font_color", Color(0.75, 0.75, 0.8),
			)


func _update_bar(bar: ColorRect, desire_value: int) -> void:
	var fill: ColorRect = bar.get_child(0)
	# Desire: 0=deprived, 1000=satisfied. Full bar = happy.
	var ratio: float = float(desire_value) / 1000.0
	fill.size = Vector2(BAR_WIDTH * ratio, BAR_HEIGHT)
