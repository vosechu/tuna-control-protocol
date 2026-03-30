extends GutTest

var _asm: AnimalStateMachine


func before_each() -> void:
	_asm = AnimalStateMachine.new()


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_starts_in_idle_with_ambient_meta_state():
	assert_eq(_asm.state, &"IDLE",
		"Initial state must be IDLE")
	assert_eq(_asm.meta_state, &"AMBIENT",
		"Initial meta_state must be AMBIENT")
	assert_eq(_asm.commitment_score, 0,
		"Initial commitment_score must be 0")


func test_cannot_transition_before_min_duration():
	# IDLE has min_duration 3.0. With no ticks elapsed, state_timer = 0.
	var transitioned: bool = _asm.try_transition(&"GROOMING", 999)
	assert_false(transitioned,
		"Should not transition when state_timer < min_duration")
	assert_eq(_asm.state, &"IDLE",
		"State must remain IDLE after blocked transition")


func test_transitions_when_score_exceeds_commitment_plus_threshold():
	# Advance past min_duration for IDLE (3.0 sec)
	_asm.tick(3.1)
	var transitioned: bool = _asm.try_transition(&"GROOMING", Constants.SWITCH_THRESHOLD + 1)
	assert_true(transitioned,
		"Should transition when score > commitment_score + SWITCH_THRESHOLD")
	assert_eq(_asm.state, &"GROOMING",
		"State must update to GROOMING after successful transition")


func test_hysteresis_blocks_weak_transitions():
	# First transition to GROOMING with a high score.
	_asm.tick(3.1)
	_asm.try_transition(&"GROOMING", 500)
	# Try transitioning away with a score that does not exceed commitment + threshold.
	_asm.tick(15.1)  # Past GROOMING min_duration (10.0)
	var low_score: int = _asm.commitment_score + Constants.SWITCH_THRESHOLD - 1
	var transitioned: bool = _asm.try_transition(&"LOAFING", low_score)
	assert_false(transitioned,
		"Score below commitment + SWITCH_THRESHOLD must be blocked by hysteresis")
	assert_eq(_asm.state, &"GROOMING",
		"State must remain GROOMING when hysteresis blocks transition")


func test_commitment_decays_per_tick_at_10hz():
	# Seed commitment by a successful transition.
	_asm.tick(3.1)
	_asm.try_transition(&"GROOMING", 500)
	var score_after_transition: int = _asm.commitment_score
	assert_eq(score_after_transition, 500,
		"commitment_score must equal the score passed to try_transition")
	# At 10Hz delta = 0.1. Decay = maxi(1, roundi(10.0 * 0.1)) = 1.
	_asm.tick(0.1)
	assert_eq(_asm.commitment_score, 499,
		"commitment_score must decay by 1 per 10Hz tick")


func test_commitment_floors_at_zero():
	# With commitment at 0, ticking should not go negative.
	assert_eq(_asm.commitment_score, 0,
		"Initial commitment_score is 0")
	_asm.tick(0.1)
	assert_eq(_asm.commitment_score, 0,
		"commitment_score must not go below 0")


func test_startled_overrides_min_duration():
	# Still within IDLE min_duration — normal transition would be blocked.
	assert_lt(_asm.state_timer, _asm.min_duration,
		"Precondition: state_timer < min_duration before startle")
	_asm.enter_startled()
	assert_eq(_asm.state, &"STARTLED",
		"enter_startled must set state to STARTLED immediately")
	assert_eq(_asm.meta_state, &"SPECIAL",
		"enter_startled must set meta_state to SPECIAL")


func test_startled_min_duration_within_expected_range():
	_asm.enter_startled()
	assert_gte(_asm.min_duration, 0.5,
		"STARTLED min_duration must be at least 0.5 sec")
	assert_lte(_asm.min_duration, 1.5,
		"STARTLED min_duration must be at most 1.5 sec")


func test_goal_directed_states_have_correct_meta_state():
	for goal_state in AnimalStateMachine.GOAL_DIRECTED_STATES:
		var asm: AnimalStateMachine = AnimalStateMachine.new()
		# IDLE min_duration is 3.0 — tick past it.
		asm.tick(3.1)
		# Goal-directed states need score > 0 + SWITCH_THRESHOLD = 150.
		asm.try_transition(goal_state, 300)
		assert_eq(asm.meta_state, &"GOAL_DIRECTED",
			"State %s must produce GOAL_DIRECTED meta_state" % goal_state)


func test_ambient_states_have_correct_meta_state():
	for ambient_state in AnimalStateMachine.AMBIENT_STATES:
		var asm: AnimalStateMachine = AnimalStateMachine.new()
		asm.tick(3.1)
		asm.try_transition(ambient_state, 300)
		assert_eq(asm.meta_state, &"AMBIENT",
			"State %s must produce AMBIENT meta_state" % ambient_state)


func test_state_timer_resets_on_transition():
	_asm.tick(3.1)
	_asm.try_transition(&"GROOMING", 300)
	assert_almost_eq(_asm.state_timer, 0.0, 0.001,
		"state_timer must reset to 0.0 after transition")


func test_min_duration_varies_by_ambient_state():
	# Transition to SLEEPING (30.0 sec) vs IDLE (3.0 sec).
	var asm_sleeping: AnimalStateMachine = AnimalStateMachine.new()
	asm_sleeping.tick(3.1)
	asm_sleeping.try_transition(&"SLEEPING", 300)
	var sleeping_min: float = asm_sleeping.min_duration

	var asm_idle: AnimalStateMachine = AnimalStateMachine.new()
	# IDLE is the starting state — check its min_duration directly.
	var idle_min: float = asm_idle.min_duration

	assert_gt(sleeping_min, idle_min,
		"SLEEPING must have a longer min_duration than IDLE (%.1f > %.1f)" % [sleeping_min, idle_min])
	assert_almost_eq(sleeping_min, 30.0, 0.001,
		"SLEEPING min_duration must be 30.0")
	assert_almost_eq(idle_min, 3.0, 0.001,
		"IDLE min_duration must be 3.0")


func test_goal_directed_states_have_zero_min_duration():
	_asm.tick(3.1)
	_asm.try_transition(&"SEEKING", 300)
	assert_almost_eq(_asm.min_duration, 0.0, 0.001,
		"Goal-directed states must have min_duration 0.0")
