extends GutTest


func test_scenarios_dir_discovered() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code
	# (ModLoader._load_scenarios_dir or mods/tcp_base/scenarios/starter.jsonc).
	var loader := ModLoader.new()
	var result := loader.load_all("res://mods/")
	var scenarios: ScenarioRegistry = result["scenarios"]
	assert_true(
		scenarios.has_scenario(&"tcp_base:starter"),
		"Expected tcp_base:starter scenario to be discovered",
	)
