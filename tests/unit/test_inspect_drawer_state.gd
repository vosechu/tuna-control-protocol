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


func test_process_after_destroy_closes_state() -> void:
	var db := GameStateDB.new()
	var entity_id: int = db.create_entity()
	db.set_component(entity_id, &"desires", {&"warmth": 500})
	var state := InspectDrawerState.new()
	state.open(entity_id)
	state.process(db)
	assert_true(state.is_open())
	db.destroy_entity(entity_id)
	state.process(db)
	assert_false(state.is_open())
	assert_eq(state.inspected_id, Constants.INVALID_ID)


func test_process_while_closed_is_noop() -> void:
	var db := GameStateDB.new()
	var state := InspectDrawerState.new()
	state.process(db)
	assert_false(state.is_open())
	assert_eq(state.content_type, InspectDrawerState.ContentType.CLOSED)


func test_process_animal_sets_content_animal() -> void:
	var db := GameStateDB.new()
	var animal_id: int = db.create_entity()
	db.set_component(animal_id, &"desires", {&"warmth": 500})
	var state := InspectDrawerState.new()
	state.open(animal_id)
	state.process(db)
	assert_eq(state.content_type, InspectDrawerState.ContentType.ANIMAL)


func test_process_server_sets_content_server() -> void:
	var db := GameStateDB.new()
	var server_id: int = db.create_entity()
	db.set_component(server_id, &"object_type", {&"type": &"server_1u"})
	var state := InspectDrawerState.new()
	state.open(server_id)
	state.process(db)
	assert_eq(state.content_type, InspectDrawerState.ContentType.SERVER)


func test_process_neither_capability_closes() -> void:
	var db := GameStateDB.new()
	var orphan_id: int = db.create_entity()
	var state := InspectDrawerState.new()
	state.open(orphan_id)
	state.process(db)
	assert_false(state.is_open())
	assert_eq(state.content_type, InspectDrawerState.ContentType.CLOSED)
