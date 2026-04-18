class_name DebugHud extends Node

# Phase 0 debug override UI. Captures the `debug_force_satisfied` input
# action (Shift+F1) and toggles the `debug_force_satisfied` component on
# the inspected entity, or on all contentment-bearing entities when no
# inspect provider is wired (Phase 0 path — no inspect panel exists yet).

var _db: GameStateDB
var _settings: Settings
var _inspect_provider: Object  # may be null in Phase 0


func initialize(db: GameStateDB, settings: Settings, inspect_provider: Object) -> void:
	_db = db
	_settings = settings
	_inspect_provider = inspect_provider


func _ready() -> void:
	# AI-DEV: Release-build assertion. Editor/debug builds can enable the
	# override freely; release builds must keep debug_enabled=false so Shift+F1
	# is inert for players. This enforces the safety rail at runtime.
	if OS.has_feature("editor") or OS.has_feature("debug"):
		return
	assert(not _settings.debug_enabled,
		"debug_enabled must be off in release builds")


func _unhandled_input(event: InputEvent) -> void:
	if not _settings.debug_enabled:
		return
	if event.is_action_pressed("debug_force_satisfied"):
		_toggle_force_satisfied_on_inspected()


func _toggle_force_satisfied_on_inspected() -> void:
	var target_id: int = _get_target_id()
	if target_id == Constants.INVALID_ID:
		_toggle_all_contentment_bearers()
		return
	_toggle_one(target_id)


func _get_target_id() -> int:
	if _inspect_provider != null and _inspect_provider.has_method(&"get_inspected_id"):
		return _inspect_provider.get_inspected_id()
	return Constants.INVALID_ID


func _toggle_one(entity_id: int) -> void:
	if _db.has_component(entity_id, &"debug_force_satisfied") and \
			_db.get_field(entity_id, &"debug_force_satisfied", &"active") == 1:
		_db.remove_component(entity_id, &"debug_force_satisfied")
	else:
		_db.set_component(entity_id, &"debug_force_satisfied", {&"active": 1})


func _toggle_all_contentment_bearers() -> void:
	for id: int in _db.get_entities_with(&"desires"):
		_toggle_one(id)
