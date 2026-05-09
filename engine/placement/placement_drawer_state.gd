class_name PlacementDrawerState extends RefCounted

# Pure state machine for the placement drawer. No scene tree, no
# signals. Per docs/superpowers/specs/2026-05-09-drawer-migration-design.md.
#
# Implicit trigger: select(type) opens the drawer + sets the selected
# type in one motion. Selecting the same type again closes the drawer
# and clears the selection.

var selected_type: StringName = &""
var remove_mode: bool = false
var _is_open: bool = false


func is_open() -> bool:
	return _is_open


func open() -> void:
	_is_open = true


func close() -> void:
	_is_open = false
	selected_type = &""
	remove_mode = false


func select(type: StringName) -> void:
	if _is_open and selected_type == type:
		close()
		return
	remove_mode = false
	selected_type = type
	_is_open = true


func set_remove_mode(active: bool) -> void:
	remove_mode = active
	if active:
		selected_type = &""
		_is_open = true


func clear_selection() -> void:
	selected_type = &""
	remove_mode = false
