extends GutTest

const PlacementDrawerState := preload(
	"res://engine/placement/placement_drawer_state.gd"
)


func test_new_state_is_closed_with_no_selection() -> void:
	var state := PlacementDrawerState.new()
	assert_false(state.is_open())
	assert_eq(state.selected_type, &"")
	assert_false(state.remove_mode)


func test_open_sets_is_open_true() -> void:
	var state := PlacementDrawerState.new()
	state.open()
	assert_true(state.is_open())


func test_close_sets_is_open_false() -> void:
	var state := PlacementDrawerState.new()
	state.open()
	state.close()
	assert_false(state.is_open())


func test_select_sets_type_and_opens() -> void:
	# Implicit trigger: selecting a type opens the drawer in one motion.
	var state := PlacementDrawerState.new()
	state.select(&"server_1u")
	assert_eq(state.selected_type, &"server_1u")
	assert_true(state.is_open())


func test_select_clears_remove_mode() -> void:
	var state := PlacementDrawerState.new()
	state.set_remove_mode(true)
	state.select(&"server_1u")
	assert_false(state.remove_mode)


func test_selecting_already_selected_type_closes_and_clears() -> void:
	# Spec §"Open trigger — fork": "Pressing the key for the
	# already-selected type cancels (closes drawer + clears selection)."
	var state := PlacementDrawerState.new()
	state.select(&"server_1u")
	state.select(&"server_1u")
	assert_eq(state.selected_type, &"")
	assert_false(state.is_open())


func test_set_remove_mode_true_opens_and_clears_type() -> void:
	var state := PlacementDrawerState.new()
	state.select(&"server_1u")
	state.set_remove_mode(true)
	assert_true(state.remove_mode)
	assert_eq(state.selected_type, &"")
	assert_true(state.is_open())


func test_set_remove_mode_false_keeps_drawer_open() -> void:
	# Toggling remove mode off does not close the drawer — only ESC, X,
	# or re-pressing the active selection closes.
	var state := PlacementDrawerState.new()
	state.set_remove_mode(true)
	state.set_remove_mode(false)
	assert_false(state.remove_mode)
	assert_true(state.is_open())


func test_clear_selection_clears_type_and_remove_mode() -> void:
	var state := PlacementDrawerState.new()
	state.select(&"server_1u")
	state.set_remove_mode(true)
	state.clear_selection()
	assert_eq(state.selected_type, &"")
	assert_false(state.remove_mode)


func test_clear_selection_does_not_close() -> void:
	# clear_selection is called after a successful place to free the
	# cursor; the drawer stays visible so the player can place multiple.
	var state := PlacementDrawerState.new()
	state.select(&"server_1u")
	state.clear_selection()
	assert_true(state.is_open())


func test_close_clears_selection_and_remove_mode() -> void:
	var state := PlacementDrawerState.new()
	state.select(&"server_1u")
	state.set_remove_mode(true)
	state.close()
	assert_eq(state.selected_type, &"")
	assert_false(state.remove_mode)
	assert_false(state.is_open())
