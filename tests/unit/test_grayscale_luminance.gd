extends GutTest

const _DESAT_SHADER_PATH := "res://mods/tcp_base/shaders/peek_bay_desaturate.gdshader"
const _MIN_LUMA_RATIO: float = 3.0


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func test_active_vs_peek_bay_distinguishable():
	var active: Color = Color.WHITE
	var sample: Color = Color(0.35, 0.35, 0.35)
	var desaturation: float = 0.65
	var brightness: float = 0.80
	var luma: float = _luma(sample)
	var desat: Color = sample.lerp(
		Color(luma, luma, luma), desaturation
	)
	var peek_sim: Color = desat * brightness
	peek_sim.a = 1.0
	var ratio: float = (
		(_luma(active) + 0.05) / (_luma(peek_sim) + 0.05)
	)
	assert_gt(ratio, _MIN_LUMA_RATIO,
		"Active/peek contrast ratio %.2f < WCAG 3:1" % ratio)


func test_plant_vs_chassis_distinguishable():
	var chassis: Color = Color(0.11, 0.12, 0.17)
	var plant_moss: Color = Color(0.39, 0.55, 0.35)
	var plant_flower: Color = Color(0.95, 0.62, 0.30)
	var chassis_luma: float = _luma(chassis)
	var moss_luma: float = _luma(plant_moss)
	var flower_luma: float = _luma(plant_flower)
	assert_gt(moss_luma - chassis_luma, 0.15,
		"Moss luma %.2f too close to chassis %.2f" % [
			moss_luma, chassis_luma,
		])
	assert_gt(flower_luma - chassis_luma, 0.15,
		"Flower luma %.2f too close to chassis %.2f" % [
			flower_luma, chassis_luma,
		])


func test_desaturation_shader_exists():
	assert_true(
		FileAccess.file_exists(_DESAT_SHADER_PATH),
		"Shader must exist at " + _DESAT_SHADER_PATH,
	)
