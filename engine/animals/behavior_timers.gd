class_name BehaviorTimers extends RefCounted

# Per-entity ticks elapsed in current ai_state. Int ticks (not float seconds);
# AiStateSystem increments by 1 per tick.
var state_timers: Dictionary = {}

# Per-entity override min_duration_ticks for the current state, set on
# SNIFFING entry by the curiosity arrival path.
var min_durations_override: Dictionary = {}

# Per-entity CuriosityTracker. Lifetime managed by the entity's lifecycle.
var curiosity_trackers: Dictionary = {}
