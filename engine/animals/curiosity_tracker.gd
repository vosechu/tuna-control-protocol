class_name CuriosityTracker extends RefCounted

# Cells are "known" for this many ticks after a visit (~10 seconds at 10 Hz).
const NOVELTY_COOLDOWN_TICKS: int = 100

# cell_index -> tick of last visit
var _visit_times: Dictionary = {}


# Returns 0 when the cell is novel (first visit or cooldown expired),
# -1 when the cell was visited recently (still within the cooldown window).
func visit_cell(cell_index: int, current_tick: int) -> int:
	if _visit_times.has(cell_index):
		var ticks_since_visit: int = current_tick - _visit_times[cell_index]
		if ticks_since_visit < NOVELTY_COOLDOWN_TICKS:
			# Cell is still "known" — no curiosity reward.
			return -1

	# Novel cell (or cooldown has expired): record visit and satisfy curiosity.
	_visit_times[cell_index] = current_tick
	return 0
