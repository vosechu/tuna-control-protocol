extends GutTest

var _db: GameStateDB
var _settings: Settings
var _hud: DebugHud


func before_each() -> void:
	_db = GameStateDB.new()
	_settings = Settings.new()
	_hud = DebugHud.new()
	_hud.initialize(_db, _settings, null)


func after_each() -> void:
	if _hud != null:
		_hud.free()
		_hud = null


func test_toggle_one_sets_component_when_absent() -> void:
	# AI-DEV: Proves _toggle_one adds debug_force_satisfied with active=1 when
	# the component is absent. This is the "turn debug ON" direction — without
	# it Shift+F1 would never force contentment on a cat that lacked the component.
	var id: int = _db.create_entity()
	_hud._toggle_one(id)
	assert_true(_db.has_component(id, &"debug_force_satisfied"))
	assert_eq(_db.get_field(id, &"debug_force_satisfied", &"active"), 1,
		"Toggle on an absent override must set active=1")


func test_toggle_one_removes_component_when_present() -> void:
	# AI-DEV: Proves _toggle_one removes debug_force_satisfied when it's
	# already active. This is the "turn debug OFF" direction — needed so
	# Shift+F1 is a true toggle and cats don't latch to permanent contentment.
	var id: int = _db.create_entity()
	_db.set_component(id, &"debug_force_satisfied", {&"active": 1})
	_hud._toggle_one(id)
	assert_false(_db.has_component(id, &"debug_force_satisfied"),
		"Toggle on a present override must remove the component")


func test_toggle_all_toggles_only_entities_with_desires() -> void:
	# AI-DEV: _toggle_all_contentment_bearers must only affect entities carrying
	# the desires component (contentment candidates). Non-desire entities like
	# servers or tuna cans must remain untouched even when toggled en masse.
	var with_desires: int = _db.create_entity()
	_db.set_component(with_desires, &"desires", {&"warmth": 500})
	var without: int = _db.create_entity()
	_hud._toggle_all_contentment_bearers()
	assert_true(_db.has_component(with_desires, &"debug_force_satisfied"),
		"Entity with desires must receive the override")
	assert_false(_db.has_component(without, &"debug_force_satisfied"),
		"Entity without desires must NOT receive the override")
