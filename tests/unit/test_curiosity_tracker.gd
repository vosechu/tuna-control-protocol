extends GutTest

var _tracker: CuriosityTracker


func before_each() -> void:
	_tracker = CuriosityTracker.new()


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_visiting_new_cell_returns_satisfied():
	# A cell never seen before should be novel — fully satisfy curiosity.
	var result: int = _tracker.visit_cell(42, 0)
	assert_eq(result, 0,
		"Visiting a new cell must return 0 (curiosity satisfied)")


func test_revisiting_within_cooldown_returns_no_change():
	# Visiting the same cell again before the cooldown expires should not reward.
	_tracker.visit_cell(42, 0)
	var result: int = _tracker.visit_cell(42, CuriosityTracker.NOVELTY_COOLDOWN_TICKS - 1)
	assert_eq(result, -1,
		"Revisiting within cooldown must return -1 (no satisfaction change)")


func test_cell_becomes_novel_again_after_cooldown_expires():
	# After NOVELTY_COOLDOWN_TICKS have passed the cell is unknown again.
	_tracker.visit_cell(42, 0)
	var result: int = _tracker.visit_cell(42, CuriosityTracker.NOVELTY_COOLDOWN_TICKS + 1)
	assert_eq(result, 0,
		"Cell must become novel again after cooldown expires")


func test_multiple_cells_tracked_independently():
	# Different cells have independent novelty clocks.
	var result_a: int = _tracker.visit_cell(1, 0)
	var result_b: int = _tracker.visit_cell(2, 0)
	assert_eq(result_a, 0,
		"Cell 1 must be novel on first visit")
	assert_eq(result_b, 0,
		"Cell 2 must be novel on first visit regardless of cell 1")

	# Re-visit cell 1 immediately — still in cooldown.
	var result_a2: int = _tracker.visit_cell(1, 1)
	# Re-visit cell 2 after its cooldown — novel again.
	var result_b2: int = _tracker.visit_cell(2, CuriosityTracker.NOVELTY_COOLDOWN_TICKS + 1)
	assert_eq(result_a2, -1,
		"Cell 1 must still be known within cooldown")
	assert_eq(result_b2, 0,
		"Cell 2 must be novel again after its own cooldown expires")


func test_visit_at_exact_cooldown_boundary_returns_satisfied():
	# Visiting at exactly first_visit + NOVELTY_COOLDOWN_TICKS should be novel.
	_tracker.visit_cell(99, 100)
	var result: int = _tracker.visit_cell(99, 100 + CuriosityTracker.NOVELTY_COOLDOWN_TICKS)
	assert_eq(result, 0,
		"Visiting at exactly the cooldown boundary must return 0 (novel again)")
