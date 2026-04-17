class_name Settings extends RefCounted

# Phase 0 game settings. Defaults only — no JSON/save/CLI loading in Phase 0.
# Instantiated by GameServer; consumers read fields directly.

var debug_enabled: bool = false
var starter_scenario_id: StringName = &"tcp_base:starter"


func from_dict(src: Dictionary) -> void:
	if src.has("debug_enabled"):
		debug_enabled = bool(src["debug_enabled"])
	if src.has("starter_scenario_id"):
		starter_scenario_id = StringName(src["starter_scenario_id"])
