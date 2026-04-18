class_name HumBar extends Control

const BAR_WIDTH: int = 40
const BAR_HEIGHT: int = 3

var _reserve_label: Label
var _bar_fill: ColorRect
var _bar_bg: ColorRect
var _glyph_label: Label
var _per_hum: Dictionary = {}  # hum_id: int -> {reserve: int, capacity: int}


func initialize(events: Object, db: GameStateDB) -> void:
	# Seed per-hum snapshot from current DB state
	for hum_id: int in db.get_entities_with(&"hum"):
		var comp: Dictionary = db.get_component(hum_id, &"hum")
		_per_hum[hum_id] = {
			&"reserve": comp[&"reserve"],
			&"capacity": comp[&"capacity"],
		}
	events.hum_reserve_changed.connect(
		_on_hum_reserve_changed,
	)
	_build_ui()
	_update_display(_aggregate_ratio())


func _build_ui() -> void:
	_bar_bg = ColorRect.new()
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.color = Color(0.15, 0.15, 0.2, 0.8)
	add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_fill.color = Color(0.3, 0.8, 0.4)
	add_child(_bar_fill)

	_reserve_label = Label.new()
	_reserve_label.position = Vector2(BAR_WIDTH + 2, -2)
	_reserve_label.add_theme_font_size_override(
		"font_size", 5,
	)
	add_child(_reserve_label)

	_glyph_label = Label.new()
	_glyph_label.position = Vector2(-6, -2)
	_glyph_label.add_theme_font_size_override(
		"font_size", 5,
	)
	add_child(_glyph_label)


func _on_hum_reserve_changed(
		hum_id: int, _old: int, new_val: int,
) -> void:
	if _per_hum.has(hum_id):
		_per_hum[hum_id][&"reserve"] = new_val
	else:
		_per_hum[hum_id] = {
			&"reserve": new_val,
			&"capacity": HumSystem.DEFAULT_CAPACITY,
		}
	_update_display(_aggregate_ratio())


func _aggregate_ratio() -> int:
	if _per_hum.is_empty():
		return 1000
	var total_reserve: int = 0
	var total_capacity: int = 0
	for entry: Dictionary in _per_hum.values():
		total_reserve += entry[&"reserve"]
		total_capacity += entry[&"capacity"]
	if total_capacity <= 0:
		return 0
	return total_reserve * 1000 / total_capacity


func _update_display(ratio: int) -> void:
	var fill_pct: float = float(ratio) / 1000.0
	_bar_fill.size.x = BAR_WIDTH * fill_pct

	if ratio >= 500:
		_bar_fill.color = Color(0.3, 0.8, 0.4)
	elif ratio >= 250:
		_bar_fill.color = Color(0.9, 0.7, 0.2)
	else:
		_bar_fill.color = Color(0.9, 0.2, 0.1)

	var pct: int = ratio / 10
	_reserve_label.text = "HUM: %d%%" % pct

	if ratio >= 500:
		_glyph_label.text = "O"
	elif ratio >= 250:
		_glyph_label.text = "^"
	else:
		_glyph_label.text = "!"
