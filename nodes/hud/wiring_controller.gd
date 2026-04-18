class_name WiringController extends Node

# Client-side state machine for cable placement. Owns no game state;
# translates input into WiringSystem intents and tracks the local drag
# state so CableLayer/DanglingTip know what to render. Intents flow
# through a small client adapter (game_client.send_wiring_intent) so
# network code can slot in without touching this file.

signal wiring_mode_changed(active: bool)

enum State { INACTIVE, WIRING, HOLDING_CABLE }

const PEER_ID_SOLO: int = 1

var _state: int = State.INACTIVE
var _pickup_from: int = Constants.INVALID_ID
var _source_hum: int = Constants.INVALID_ID
var _cursor_world_pos: Vector2 = Vector2.ZERO
var _client: Object


func initialize(client: Object) -> void:
	_client = client


func get_state() -> int:
	return _state


func get_cursor_world_pos() -> Vector2:
	return _cursor_world_pos


func get_pickup_from() -> int:
	return _pickup_from


func get_source_hum() -> int:
	return _source_hum


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("wiring_mode_toggle"):
		_toggle_mode()
		return
	if _state == State.INACTIVE:
		return
	if event is InputEventMouseMotion:
		if _client != null and _client.has_method(&"screen_to_world"):
			_cursor_world_pos = _client.screen_to_world(event.position)
		return
	if event.is_action_pressed("cable_cancel"):
		_handle_cancel()
		return
	if _state == State.HOLDING_CABLE and event.is_action_pressed("cable_delete"):
		_send_intent(&"CABLE_DELETE_INTENT", {&"actuator_id": _pickup_from})
		_clear_drag()
		return
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_handle_click_at(_cursor_world_pos)


func _toggle_mode() -> void:
	if _state == State.INACTIVE:
		_state = State.WIRING
		wiring_mode_changed.emit(true)
	else:
		_handle_cancel()
		_state = State.INACTIVE
		wiring_mode_changed.emit(false)


func _handle_click_at(world_pos: Vector2) -> void:
	if _client == null:
		return
	var clicked_id: int = _client.entity_under_point(world_pos)
	if clicked_id == Constants.INVALID_ID:
		return
	if _state == State.WIRING:
		if _client.is_hum(clicked_id):
			_send_intent(&"CABLE_START_INTENT", {&"hum_id": clicked_id})
			_source_hum = clicked_id
			_state = State.HOLDING_CABLE
		elif _client.has_existing_cable(clicked_id):
			_send_intent(&"CABLE_PICKUP_INTENT", {&"actuator_id": clicked_id})
			_pickup_from = clicked_id
			_state = State.HOLDING_CABLE
	elif _state == State.HOLDING_CABLE:
		if _client.is_hum_powered_device(clicked_id):
			_send_intent(&"CABLE_CONNECT_INTENT", {
				&"target_id": clicked_id,
				&"source_hum_id": _source_hum,
				&"from_actuator_id": _pickup_from,
			})
			_clear_drag()


func _handle_cancel() -> void:
	if _state == State.HOLDING_CABLE and _pickup_from != Constants.INVALID_ID:
		_send_intent(&"CABLE_CANCEL_INTENT", {&"actuator_id": _pickup_from})
	_clear_drag()


func _clear_drag() -> void:
	if _state == State.HOLDING_CABLE:
		_state = State.WIRING
	_pickup_from = Constants.INVALID_ID
	_source_hum = Constants.INVALID_ID


func _send_intent(intent: StringName, payload: Dictionary) -> void:
	if _client != null and _client.has_method(&"send_wiring_intent"):
		_client.send_wiring_intent(PEER_ID_SOLO, intent, payload)


func reconcile_server_pickups(server_entries: Array) -> void:
	# Server push after a resync / rejoin. If the server no longer holds
	# our pickup lock we silently drop the local drag rather than sending
	# a cancel that can't land.
	if _state != State.HOLDING_CABLE or _pickup_from == Constants.INVALID_ID:
		return
	for entry: Dictionary in server_entries:
		if int(entry.get(&"original_actuator_id", Constants.INVALID_ID)) == _pickup_from:
			return
	_clear_drag()
