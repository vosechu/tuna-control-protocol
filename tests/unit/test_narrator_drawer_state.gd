extends GutTest

const NarratorDrawerState := preload(
	"res://engine/narrator/narrator_drawer_state.gd"
)


func test_new_state_defaults_to_open() -> void:
	# Spec §"Narrator → bottom-edge drawer": "Default state: open —
	# narrator events are critical feedback; opt-out should be deliberate."
	var state := NarratorDrawerState.new()
	assert_true(state.is_open())


func test_close_sets_is_open_false() -> void:
	var state := NarratorDrawerState.new()
	state.close()
	assert_false(state.is_open())


func test_toggle_flips_state() -> void:
	var state := NarratorDrawerState.new()
	state.toggle()
	assert_false(state.is_open())
	state.toggle()
	assert_true(state.is_open())


func test_post_log_appends_to_history() -> void:
	var state := NarratorDrawerState.new()
	state.post_log("hello")
	state.post_log("world")
	var visible: Array[String] = state.get_visible_lines()
	assert_eq(visible.size(), 2)
	assert_eq(visible[0], "hello")
	assert_eq(visible[1], "world")


func test_post_log_caps_history_at_max() -> void:
	var state := NarratorDrawerState.new()
	for i in NarratorDrawerState.MAX_HISTORY + 5:
		state.post_log("line %d" % i)
	var history: Array[String] = state.get_history()
	assert_eq(history.size(), NarratorDrawerState.MAX_HISTORY)
	assert_eq(history[0], "line 5")  # oldest 5 dropped
	assert_eq(
		history[history.size() - 1],
		"line %d" % (NarratorDrawerState.MAX_HISTORY + 4),
	)


func test_get_visible_lines_returns_last_n() -> void:
	var state := NarratorDrawerState.new()
	for i in 10:
		state.post_log("line %d" % i)
	var visible: Array[String] = state.get_visible_lines()
	assert_eq(visible.size(), NarratorDrawerState.MAX_VISIBLE_LINES)
	assert_eq(visible[0], "line 7")
	assert_eq(visible[2], "line 9")


func test_pin_log_sets_pinned_message() -> void:
	var state := NarratorDrawerState.new()
	state.pin_log("ADVISORY")
	assert_eq(state.pinned_log, "ADVISORY")


func test_clear_pin_resets_pinned_message() -> void:
	var state := NarratorDrawerState.new()
	state.pin_log("ADVISORY")
	state.clear_pin()
	assert_eq(state.pinned_log, "")


func test_pinned_message_persists_across_toggle() -> void:
	# Spec §"Narrator → bottom-edge drawer": "Pinned-line behavior
	# unchanged; pinned text persists across open/close."
	var state := NarratorDrawerState.new()
	state.pin_log("HOLD")
	state.toggle()  # close
	state.toggle()  # reopen
	assert_eq(state.pinned_log, "HOLD")


func test_history_persists_across_toggle() -> void:
	var state := NarratorDrawerState.new()
	state.post_log("first")
	state.toggle()
	state.toggle()
	var visible: Array[String] = state.get_visible_lines()
	assert_eq(visible.size(), 1)
	assert_eq(visible[0], "first")
