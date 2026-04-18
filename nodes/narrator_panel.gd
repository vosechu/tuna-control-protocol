class_name NarratorPanel extends PanelContainer

const MAX_VISIBLE_LINES: int = 3
const MAX_HISTORY: int = 50

var _label: RichTextLabel
var _history: Array[String] = []
var _pinned_log: String = ""
var _narrator: Narrator


func initialize(
		events: Object, narrator: Narrator,
) -> void:
	_narrator = narrator
	_build_ui()
	events.hum_brownout_entered.connect(
		_on_brownout_entered,
	)
	events.hum_brownout_recovered.connect(
		_on_brownout_recovered,
	)


func _build_ui() -> void:
	custom_minimum_size = Vector2(280, 48)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.05, 0.9)
	style.border_color = Color(0.2, 0.3, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", style)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.add_theme_font_size_override(
		"normal_font_size", 8,
	)
	_label.add_theme_color_override(
		"default_color", Color(0.3, 0.9, 0.3),
	)
	add_child(_label)


func post_log(message: String) -> void:
	_history.append(message)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_refresh_display()


func pin_log(message: String) -> void:
	_pinned_log = message
	_refresh_display()


func clear_pin() -> void:
	_pinned_log = ""
	_refresh_display()


func _refresh_display() -> void:
	var lines: Array[String] = []
	if _pinned_log != "":
		lines.append("[b]%s[/b]" % _pinned_log)
	var start: int = maxi(
		0, _history.size() - MAX_VISIBLE_LINES,
	)
	for i in range(start, _history.size()):
		lines.append(_history[i])
	_label.text = "\n".join(lines)


func _on_brownout_entered(_hum_id: int) -> void:
	var log: String = _narrator.get_log_for_event(
		&"first_brownout", {},
	)
	post_log(log)


func _on_brownout_recovered(_hum_id: int) -> void:
	var log: String = _narrator.get_log_for_event(
		&"recovery", {},
	)
	post_log(log)
