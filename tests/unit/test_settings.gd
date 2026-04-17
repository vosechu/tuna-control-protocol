extends GutTest

var _s: Settings


func before_each() -> void:
	_s = Settings.new()


func test_defaults() -> void:
	# AI-DEV: Guards the Phase 0 default contract — debug is off, and
	# the starter scenario id matches the shipped tcp_base:starter recipe.
	# If either default shifts, GameServer boot behavior and DebugHud
	# visibility change silently.
	assert_false(_s.debug_enabled, "debug_enabled defaults to false")
	assert_eq(_s.starter_scenario_id, &"tcp_base:starter",
		"starter_scenario_id default")


func test_from_dict_overrides_defaults() -> void:
	# AI-DEV: Proves from_dict actually writes both fields. If this
	# regresses, settings files (future Phase 1+) would be silently ignored.
	_s.from_dict({"debug_enabled": true, "starter_scenario_id": "mod:alt"})
	assert_true(_s.debug_enabled)
	assert_eq(_s.starter_scenario_id, &"mod:alt")


func test_from_dict_preserves_unset_fields() -> void:
	# AI-DEV: from_dict must be a partial-update — unspecified keys keep
	# their previous values, not reset to defaults. Otherwise layered
	# settings (e.g. CLI over file) would clobber fields they don't touch.
	_s.from_dict({"debug_enabled": true})
	assert_true(_s.debug_enabled)
	assert_eq(_s.starter_scenario_id, &"tcp_base:starter",
		"Unspecified fields keep their previous values")


func test_from_dict_empty_is_noop() -> void:
	# AI-DEV: Empty-dict path must not mutate anything. A "no settings
	# present" boot must leave defaults intact.
	_s.from_dict({})
	assert_false(_s.debug_enabled)
	assert_eq(_s.starter_scenario_id, &"tcp_base:starter")
