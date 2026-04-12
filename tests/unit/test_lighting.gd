extends GutTest


func test_full_reserve_returns_full_brightness():
	var brightness: float = LightingSystem.reserve_to_brightness(
		1000,
	)
	assert_almost_eq(brightness, 1.0, 0.01,
		"Full reserve should return brightness 1.0")


func test_zero_reserve_returns_minimum_brightness():
	var brightness: float = LightingSystem.reserve_to_brightness(
		0,
	)
	assert_almost_eq(brightness, 0.15, 0.01,
		"Zero reserve should return min brightness 0.15")


func test_quarter_reserve_returns_red_tint():
	var color: Color = LightingSystem.reserve_to_color(250)
	assert_gt(color.r, color.g,
		"At 25%% reserve, red channel should dominate")


func test_full_reserve_returns_warm_white():
	var color: Color = LightingSystem.reserve_to_color(1000)
	assert_almost_eq(color.r, 1.0, 0.1,
		"Full reserve should be warm white")
	assert_almost_eq(color.g, 0.95, 0.1,
		"Full reserve should be warm white")
	assert_almost_eq(color.b, 0.85, 0.1,
		"Full reserve should have slight warm tint")


func test_brownout_threshold_at_250():
	assert_true(LightingSystem.is_brownout(249),
		"Below 250 ratio should be brownout")
	assert_false(LightingSystem.is_brownout(250),
		"At 250 ratio should not be brownout")
