extends GutTest

const InspectDrawerState := preload("res://engine/inspect/inspect_drawer_state.gd")


func test_new_state_is_closed() -> void:
	var state := InspectDrawerState.new()
	assert_eq(state.inspected_id, Constants.INVALID_ID)
	assert_false(state.is_open())


func test_open_with_valid_id_sets_open() -> void:
	var state := InspectDrawerState.new()
	state.open(42)
	assert_eq(state.inspected_id, 42)
	assert_true(state.is_open())


func test_open_while_open_retargets() -> void:
	var state := InspectDrawerState.new()
	state.open(42)
	state.open(43)
	assert_eq(state.inspected_id, 43)
	assert_true(state.is_open())


func test_open_with_invalid_id_is_noop() -> void:
	var state := InspectDrawerState.new()
	state.open(Constants.INVALID_ID)
	assert_eq(state.inspected_id, Constants.INVALID_ID)
	assert_false(state.is_open())


func test_close_resets() -> void:
	var state := InspectDrawerState.new()
	state.open(42)
	state.close()
	assert_eq(state.inspected_id, Constants.INVALID_ID)
	assert_false(state.is_open())
