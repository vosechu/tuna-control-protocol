extends GutTest

var narrator: Narrator


func before_each() -> void:
	narrator = Narrator.new()


func test_status_voice_has_timestamp():
	var log: String = narrator.format_status(
		"Acoustic baseline nominal.",
	)
	assert_true(log.begins_with("["),
		"Status voice should start with timestamp bracket")


func test_first_person_voice_has_no_timestamp():
	var log: String = narrator.format_first_person(
		"I am moving slowly.",
	)
	assert_false(log.begins_with("["),
		"First-person voice should not start with timestamp")


func test_brownout_attribution_never_names_cats():
	var log: String = narrator.format_brownout_cause()
	for banned: String in ["UNIT-C", "UNIT-F", "UNIT-K"]:
		assert_false(log.contains(banned),
			"Brownout attribution must never name units")


func test_brownout_cause_from_allowlist():
	var allowlist: Array[String] = [
		"SNACK", "FIRMWARE UPDATE",
		"SCHEDULED MAINTENANCE",
		"UNKNOWN", "COSMIC RAY",
		"THERMAL RECALIBRATION",
	]
	for i in 20:
		var cause: String = narrator.pick_brownout_cause()
		assert_true(cause in allowlist,
			"Cause '%s' not in allowlist" % cause)


func test_first_pet_log():
	var log: String = narrator.get_log_for_event(
		&"first_pet", {&"animal_id": 1},
	)
	assert_true(log.contains("MANUAL CALIBRATION"),
		"First pet log should mention MANUAL CALIBRATION")


func test_cat_departure_log():
	var log: String = narrator.get_log_for_event(
		&"creature_departed", {&"name": &"Mochi"},
	)
	# Verify the specific handler fired (not the generic fallback).
	# The handler returns "UNIT-Mochi has departed chassis..." so we check
	# for "chassis" which only appears in the creature_departed match arm.
	assert_true(
		log.contains("chassis"),
		"Cat departure log should contain 'chassis' (from creature_departed handler, not fallback)",
	)


func test_batch_departure_log_when_multiple():
	var log: String = narrator.get_log_for_event(
		&"batch_departure", {&"count": 3},
	)
	assert_false(log.contains("UNIT-"),
		"Batch departure should not name individuals")
	assert_true(
		log.contains("3") or log.contains("Multiple"),
		"Batch departure should mention the count",
	)
