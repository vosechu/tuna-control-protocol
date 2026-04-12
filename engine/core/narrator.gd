class_name Narrator extends RefCounted

const BROWNOUT_CAUSES: Array[String] = [
	"SNACK", "FIRMWARE UPDATE", "SCHEDULED MAINTENANCE",
	"UNKNOWN", "COSMIC RAY", "THERMAL RECALIBRATION",
]

var _tick: int = 0
var _first_pet_seen: bool = false


func set_tick(tick: int) -> void:
	_tick = tick


func format_status(message: String) -> String:
	@warning_ignore("integer_division")
	var minutes: int = _tick / 600
	@warning_ignore("integer_division")
	var seconds: int = (_tick / 10) % 60
	return "[%02d:%02d] %s" % [minutes, seconds, message]


func format_first_person(message: String) -> String:
	return message


func pick_brownout_cause() -> String:
	return BROWNOUT_CAUSES[randi() % BROWNOUT_CAUSES.size()]


func format_brownout_cause() -> String:
	return "CAUSE: %s" % pick_brownout_cause()


func get_log_for_event(
		event_type: StringName, data: Dictionary,
) -> String:
	var msg: String = _build_message(event_type, data)
	if msg != "":
		return msg
	return format_status(
		"Event logged: %s" % event_type,
	)


func _build_message(
		event_type: StringName, data: Dictionary,
) -> String:
	var n: StringName = data.get(&"name", &"UNKNOWN")
	match event_type:
		&"first_cat_settles":
			return format_status(
				"UNIT-%s has entered chassis." % n
				+ " Audible output: 25-30Hz sustained"
				+ " hum. Classifying as healthy disk"
				+ " activity.",
			)
		&"hum_charging":
			return format_status(
				"Acoustic baseline strengthening."
				+ " Power conditioning nominal.",
			)
		&"first_brownout":
			return format_status(
				"ADVISORY: Acoustic baseline thinning."
				+ " Reserve capacitors discharging."
				+ " Investigating.",
			)
		&"deep_brownout":
			return format_first_person(
				"I am moving slowly. I do not know"
				+ " why the devices stopped humming."
				+ " Please hum.",
			)
		&"cat_departed":
			return format_status(
				"UNIT-%s has departed chassis." % n
				+ " Reason: unknown. Possible snack.",
			)
	return _build_message_2(event_type, data)


func _build_message_2(
		event_type: StringName, data: Dictionary,
) -> String:
	var n: StringName = data.get(&"name", &"UNKNOWN")
	match event_type:
		&"batch_departure":
			var count: int = data.get(&"count", 2)
			return format_status(
				"Multiple devices (%d)" % count
				+ " entering standby simultaneously."
				+ " Scheduling group diagnostic.",
			)
		&"cat_returned":
			return format_status(
				"UNIT-%s has returned." % n
				+ " Resuming monitoring.",
			)
		&"recovery":
			return format_status(
				"Acoustic baseline restored."
				+ " Logging this event as ROUTINE"
				+ " BROWNOUT, %s."
				% format_brownout_cause(),
			)
		&"tuna_dispense":
			return format_status(
				"Deploying negotiation asset."
				+ " The devices have pressed"
				+ " the button.",
			)
		&"arm_opens_can":
			return format_status(
				"Seal altered. Contents:"
				+ " reconfigured. Chemical plume"
				+ " detected.",
			)
		&"first_pet":
			_first_pet_seen = true
			return format_status(
				"UNIT reporting anomalous external"
				+ " stimulus. Satisfaction"
				+ " metrics... improving? Logging"
				+ " as MANUAL CALIBRATION.",
			)
	return ""
