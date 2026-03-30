class_name AnimalStateMachine extends RefCounted

# States in which the animal is pursuing a specific goal.
const GOAL_DIRECTED_STATES: Array[StringName] = [&"SEEKING", &"MOVING_TO", &"SETTLING"]

# States in which the animal behaves without a specific goal.
const AMBIENT_STATES: Array[StringName] = [
	&"IDLE", &"GROOMING", &"LOAFING", &"SLEEPING", &"SNIFFING", &"SPEED_BUMP",
]

# Minimum seconds an animal must spend in a state before it can leave.
# Prevents flicker when multiple advertisements compete.
const _MIN_DURATION_BY_STATE: Dictionary = {
	&"IDLE": 3.0,
	&"GROOMING": 10.0,
	&"LOAFING": 15.0,
	&"SLEEPING": 30.0,
	&"SNIFFING": 10.0,
	&"SPEED_BUMP": 15.0,
}

var state: StringName = &"IDLE"
var meta_state: StringName = &"AMBIENT"
var commitment_score: int = 0
var state_timer: float = 0.0
var min_duration: float = 3.0  # starts at IDLE default


# Try to transition to new_state with the given desire score.
# Returns true if the transition happened, false if blocked by hysteresis or min_duration.
func try_transition(new_state: StringName, score: int) -> bool:
	if state_timer < min_duration:
		return false
	if score < commitment_score + Constants.SWITCH_THRESHOLD:
		return false
	_enter_state(new_state, score)
	return true


# Force an immediate transition to STARTLED, bypassing all guards.
# Called on sudden events: pounces, loud noises, infrastructure removal underfoot.
func enter_startled() -> void:
	_enter_state(&"STARTLED", commitment_score)
	meta_state = &"SPECIAL"
	# Hold startled pose for a random 0.5-1.5 seconds before settling.
	min_duration = randf_range(0.5, 1.5)


# Advance the state machine by one frame (called from _physics_process).
# delta is engine time in seconds; at 10 Hz this is always 0.1.
func tick(delta: float) -> void:
	state_timer += delta
	# Decay 10 commitment units per second; minimum decay is 1 per tick so
	# commitment always trends toward zero even at low framerates.
	var decay: int = maxi(1, roundi(10.0 * delta))
	commitment_score = maxi(0, commitment_score - decay)


# ── Private ───────────────────────────────────────────────────────────────────

func _enter_state(new_state: StringName, score: int) -> void:
	state = new_state
	commitment_score = score
	state_timer = 0.0

	if new_state in GOAL_DIRECTED_STATES:
		meta_state = &"GOAL_DIRECTED"
		min_duration = 0.0
	elif new_state == &"STARTLED":
		# meta_state set by enter_startled after this call; min_duration set there too.
		meta_state = &"SPECIAL"
		min_duration = 1.0  # placeholder, overwritten by enter_startled
	else:
		meta_state = &"AMBIENT"
		min_duration = _MIN_DURATION_BY_STATE.get(new_state, 3.0)
