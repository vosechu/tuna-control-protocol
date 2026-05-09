class_name NarratorDrawer extends Drawer

# Bottom-anchored narrator drawer. Replaces the always-on narrator
# panel. Per docs/superpowers/specs/2026-05-09-drawer-migration-design.md.
#
# Default state: open. Toggled by L (handled in game_client.gd).

const _NARRATOR_DRAWER_STATE_SCRIPT := preload(
	"res://engine/narrator/narrator_drawer_state.gd"
)
const _PANEL_WIDTH: int = 140
const _PANEL_HEIGHT: int = 16

var _state: NarratorDrawerState
var _label: RichTextLabel
var _narrator: Narrator


func _ready() -> void:
	_state = _NARRATOR_DRAWER_STATE_SCRIPT.new()
	custom_minimum_size = Vector2(_PANEL_WIDTH, _PANEL_HEIGHT)
	anchor_edge = Drawer.AnchorEdge.BOTTOM
	open_position = Vector2(
		float(Constants.VIEWPORT_WIDTH - _PANEL_WIDTH) / 2.0,
		float(Constants.VIEWPORT_HEIGHT - _PANEL_HEIGHT - 2),
	)
	_build_ui()
	# Drawer._ready() reads custom_minimum_size to compute the off-edge
	# position, so size + open_position must be set before super._ready().
	super._ready()


func initialize(events: Object, narrator: Narrator) -> void:
	_narrator = narrator
	events.hum_brownout_entered.connect(_on_brownout_entered)
	events.hum_brownout_recovered.connect(_on_brownout_recovered)
	# Default state per spec is open — Drawer._ready() left us closed
	# and hidden, so reflect the initial state by opening (slide animates
	# at boot).
	open()


func _build_ui() -> void:
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
	_label.add_theme_font_size_override("normal_font_size", 3)
	_label.add_theme_font_size_override("bold_font_size", 3)
	_label.add_theme_color_override(
		"default_color", Color(0.3, 0.9, 0.3),
	)
	add_child(_label)


func toggle() -> void:
	if _state == null:
		return
	_state.toggle()
	if _state.is_open():
		open()
	else:
		close()


func post_log(message: String) -> void:
	if _state == null:
		return
	_state.post_log(message)
	_refresh_display()


func pin_log(message: String) -> void:
	if _state == null:
		return
	_state.pin_log(message)
	_refresh_display()


func clear_pin() -> void:
	if _state == null:
		return
	_state.clear_pin()
	_refresh_display()


func _refresh_display() -> void:
	if _label == null or _state == null:
		return
	var lines: Array[String] = []
	if _state.pinned_log != "":
		lines.append("[b]%s[/b]" % _state.pinned_log)
	for line: String in _state.get_visible_lines():
		lines.append(line)
	_label.text = "\n".join(lines)


func _on_brownout_entered(_hum_id: int) -> void:
	var log_line: String = _narrator.get_log_for_event(
		&"first_brownout", {},
	)
	post_log(log_line)


func _on_brownout_recovered(_hum_id: int) -> void:
	var log_line: String = _narrator.get_log_for_event(
		&"recovery", {},
	)
	post_log(log_line)
