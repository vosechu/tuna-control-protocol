class_name LightingSystem extends CanvasModulate

const MIN_BRIGHTNESS: float = 0.15
const BROWNOUT_RATIO: int = 250
const SMOOTHING_SPEED: float = 2.0

var _target_brightness: float = 1.0
var _target_color: Color = Color.WHITE


func initialize(events: Object) -> void:
	events.hum_reserve_changed.connect(
		_on_hum_reserve_changed,
	)
	color = Color.WHITE


static func reserve_to_brightness(ratio: int) -> float:
	return (
		MIN_BRIGHTNESS
		+ float(ratio) / 1000.0 * (1.0 - MIN_BRIGHTNESS)
	)


static func reserve_to_color(ratio: int) -> Color:
	if ratio >= 500:
		return Color(1.0, 0.95, 0.85)
	if ratio >= BROWNOUT_RATIO:
		var t: float = (
			float(ratio - BROWNOUT_RATIO)
			/ float(500 - BROWNOUT_RATIO)
		)
		return Color(
			1.0, 0.6 + 0.35 * t, 0.3 + 0.55 * t,
		)
	var t: float = float(ratio) / float(BROWNOUT_RATIO)
	return Color(
		0.8 + 0.2 * t, 0.2 + 0.4 * t, 0.1 + 0.2 * t,
	)


static func is_brownout(ratio: int) -> bool:
	return ratio < BROWNOUT_RATIO


func _on_hum_reserve_changed(
		_old: int, new_reserve: int,
) -> void:
	_target_brightness = reserve_to_brightness(new_reserve)
	_target_color = reserve_to_color(new_reserve)


func _process(delta: float) -> void:
	var current_b: float = color.v
	var new_b: float = lerpf(
		current_b, _target_brightness,
		SMOOTHING_SPEED * delta,
	)
	color = _target_color * new_b
