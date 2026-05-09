class_name InspectDrawer extends Drawer

# Per docs/superpowers/specs/2026-05-09-inspect-drawer-design.md.
# Reads InspectDrawerState per-frame; renders header + bars + action +
# personality. HUD-only consumer; never writes to GameStateDB.

const _DESIRE_KEYS: Array[StringName] = [
	&"warmth", &"comfort", &"curiosity", &"hunger",
	&"social", &"quiet", &"peace", &"safety",
]
const _DESIRE_LABELS: Dictionary = {
	&"warmth": "Warmth", &"comfort": "Comfort",
	&"curiosity": "Curiosity", &"hunger": "Hunger",
	&"social": "Social", &"quiet": "Quiet",
	&"peace": "Peace", &"safety": "Safety",
}
const _DESIRE_COLORS: Dictionary = {
	&"warmth":    Color(0.85, 0.35, 0.20),
	&"comfort":   Color(0.45, 0.65, 0.85),
	&"curiosity": Color(0.60, 0.80, 0.30),
	&"hunger":    Color(0.90, 0.55, 0.20),
	&"social":    Color(0.95, 0.50, 0.65),
	&"quiet":     Color(0.30, 0.45, 0.75),
	&"peace":     Color(0.65, 0.50, 0.85),
	&"safety":    Color(0.40, 0.75, 0.45),
}
const _BAR_WIDTH: int = 36
const _BAR_HEIGHT: int = 3
const _FONT_SIZE: int = 3

var _db: GameStateDB
var _state: InspectDrawerState

var _header_label: Label
var _status_label: Label
var _bars_container: VBoxContainer
var _bar_fills: Dictionary = {}
var _bar_values: Dictionary = {}
var _action_label: Label
var _personality_label: Label


func _ready() -> void:
	_state = InspectDrawerState.new()
	custom_minimum_size = Vector2(56, 72)
	anchor_edge = Drawer.AnchorEdge.LEFT
	open_position = Vector2(2, 54)
	_build_ui()
	Events.entity_inspect_opened.connect(_on_entity_inspect_opened)
	# Drawer._ready() reads custom_minimum_size to compute the off-edge
	# position, so size + open_position must be set before super._ready().
	super._ready()


func initialize(db: GameStateDB) -> void:
	_db = db


func _build_ui() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.10, 0.15, 0.92)
	bg.border_color = Color(0.25, 0.30, 0.40)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.position = Vector2(2, 2)
	add_child(vbox)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 1)
	_header_label = _make_label(_FONT_SIZE, Color(0.9, 0.85, 0.7))
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_header_label)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", _FONT_SIZE)
	close_btn.custom_minimum_size = Vector2(6, 5)
	close_btn.pressed.connect(_close_drawer)
	header_row.add_child(close_btn)
	vbox.add_child(header_row)

	_status_label = _make_label(_FONT_SIZE, Color(0.7, 0.85, 0.7))
	vbox.add_child(_status_label)

	_bars_container = VBoxContainer.new()
	_bars_container.add_theme_constant_override("separation", 0)
	vbox.add_child(_bars_container)

	for key: StringName in _DESIRE_KEYS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		var lbl := _make_label(_FONT_SIZE, Color(0.7, 0.7, 0.75))
		lbl.text = String(_DESIRE_LABELS[key])
		lbl.custom_minimum_size = Vector2(14, _BAR_HEIGHT)
		row.add_child(lbl)
		var bg_rect := ColorRect.new()
		bg_rect.color = Color(0.15, 0.15, 0.20)
		bg_rect.custom_minimum_size = Vector2(_BAR_WIDTH, _BAR_HEIGHT)
		var fill := ColorRect.new()
		fill.color = _DESIRE_COLORS[key]
		fill.size = Vector2(0, _BAR_HEIGHT)
		fill.position = Vector2.ZERO
		bg_rect.add_child(fill)
		row.add_child(bg_rect)
		var val := _make_label(_FONT_SIZE, Color(0.85, 0.85, 0.9))
		row.add_child(val)
		_bar_fills[key] = fill
		_bar_values[key] = val
		_bars_container.add_child(row)

	_action_label = _make_label(_FONT_SIZE, Color(0.85, 0.7, 0.95))
	vbox.add_child(_action_label)

	_personality_label = _make_label(_FONT_SIZE, Color(0.6, 0.7, 0.75))
	_personality_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_personality_label.custom_minimum_size = Vector2(52, 0)
	vbox.add_child(_personality_label)


func _make_label(font_size: int, font_color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", font_color)
	return lbl


func _on_entity_inspect_opened(entity_id: int) -> void:
	if _state.is_open() and _state.inspected_id == entity_id:
		_close_drawer()
		return
	_state.open(entity_id)
	open()


# Single source of truth for closing — used by the X button, click-outside,
# ESC, controller B, and the toggle path.
func _close_drawer() -> void:
	if _state == null:
		return
	_state.close()
	close()


func _process(_delta: float) -> void:
	if _db == null or _state == null:
		return
	if not _state.is_open():
		return
	_state.process(_db)
	if not _state.is_open():
		close()
		return
	_render_view()


func _render_view() -> void:
	if _state.content_type == InspectDrawerState.ContentType.ANIMAL:
		_render_animal()
	elif _state.content_type == InspectDrawerState.ContentType.SERVER:
		_render_server()


func _render_animal() -> void:
	var id: int = _state.inspected_id
	if _db.has_component(id, &"species"):
		var species: Dictionary = _db.get_component(id, &"species")
		_header_label.text = String(species.get(&"name", &"???"))
	else:
		_header_label.text = "???"
	if _db.has_component(id, &"hud_color"):
		var c: Dictionary = _db.get_component(id, &"hud_color")
		_header_label.add_theme_color_override(
			"font_color", Color(c[&"r"], c[&"g"], c[&"b"]),
		)
	_status_label.text = String(_state.derive_status_keyword(_db))
	_bars_container.visible = true
	if _db.has_component(id, &"desires"):
		var desires: Dictionary = _db.get_component(id, &"desires")
		for key: StringName in _DESIRE_KEYS:
			var v: int = int(desires.get(key, 0))
			var ratio: float = clamp(float(v) / 1000.0, 0.0, 1.0)
			(_bar_fills[key] as ColorRect).size = Vector2(
				_BAR_WIDTH * ratio, _BAR_HEIGHT,
			)
			(_bar_values[key] as Label).text = "%d" % v
	if _db.has_component(id, &"ai_state"):
		var ai: Dictionary = _db.get_component(id, &"ai_state")
		_action_label.text = String(ai.get(&"state", &"")).to_lower()
	else:
		_action_label.text = ""
	if _db.has_component(id, &"personality"):
		var p: Dictionary = _db.get_component(id, &"personality")
		var parts: Array[String] = []
		for key: StringName in _DESIRE_KEYS:
			var pkey: StringName = StringName(String(key) + "_weight")
			parts.append("%s %d" % [_DESIRE_LABELS[key], int(p.get(pkey, 0)) / 100])
		_personality_label.text = "  ".join(parts)
	else:
		_personality_label.text = ""


func _render_server() -> void:
	var id: int = _state.inspected_id
	var pos_x: int = 0
	var pos_y: int = 0
	if _db.has_component(id, &"position"):
		var pos: Dictionary = _db.get_component(id, &"position")
		pos_x = int(pos[&"x"])
		pos_y = int(pos[&"y"])
	var bay: int = Constants.world_to_bay(Vector2i(pos_x, pos_y))
	var query: SlotQuery = Constants.bay_local_to_slot(
		bay, Vector2i(pos_x, pos_y),
	)
	if query.zone == &"slot":
		_header_label.text = "Server %d/%d" % [query.get_rack(), query.get_slot()]
	else:
		_header_label.text = "Server"
	_status_label.text = String(_state.derive_status_keyword(_db))
	_bars_container.visible = false
	var heat_strength: int = 0
	var heat_radius: int = 0
	if _db.has_component(id, &"advertisements"):
		var ads: Dictionary = _db.get_component(id, &"advertisements")
		for ad: Dictionary in ads.get(&"list", []):
			if ad.get(&"channel", &"") == &"warmth":
				heat_strength = int(ad.get(&"strength", 0))
				heat_radius = int(ad.get(&"effect_radius_px", 0))
				break
	var nearby_count: int = 0
	var nearby_raw: Array[int] = _db.query_radius(
		pos_x, pos_y, Constants.BAY_WIDTH_PX,
	)
	for eid: int in nearby_raw:
		if _db.has_component(eid, &"desires"):
			nearby_count += 1
	_action_label.text = "Heat %d  r%dpx  near %d" % [
		heat_strength, heat_radius, nearby_count,
	]
	_personality_label.text = "~ Fan: 1200 RPM"
