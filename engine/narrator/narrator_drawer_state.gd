class_name NarratorDrawerState extends RefCounted

# Pure state machine for the narrator drawer. No scene tree, no
# signals. Per docs/superpowers/specs/2026-05-09-drawer-migration-design.md.
#
# Hosts the history + pinned-log state that previously lived in
# nodes/hud/narrator_panel.gd. The Drawer-derived view reads from this
# and renders.

const MAX_VISIBLE_LINES: int = 3
const MAX_HISTORY: int = 50

var pinned_log: String = ""
var _is_open: bool = true
var _history: Array[String] = []


func is_open() -> bool:
	return _is_open


func open() -> void:
	_is_open = true


func close() -> void:
	_is_open = false


func toggle() -> void:
	_is_open = not _is_open


func post_log(message: String) -> void:
	_history.append(message)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()


func pin_log(message: String) -> void:
	pinned_log = message


func clear_pin() -> void:
	pinned_log = ""


func get_history() -> Array[String]:
	return _history.duplicate()


func get_visible_lines() -> Array[String]:
	var start: int = maxi(0, _history.size() - MAX_VISIBLE_LINES)
	var out: Array[String] = []
	for i in range(start, _history.size()):
		out.append(_history[i])
	return out
