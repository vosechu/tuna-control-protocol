extends GutTest

# Phase 0 smoke test — GameServer boot populates the starter scenario.
# Verifies the Phase 0 HUM cable hookup: after _ready() runs, the DB holds
# at least one HUM receiver, one TUNA dispenser, and one ARM spawned from
# the tcp_base:starter scenario via WorldInitSystem.

const GAME_SERVER_SCRIPT: GDScript = preload(
	"res://nodes/game_server.gd"
)


func test_new_game_populates_starter_scenario() -> void:
	# AI-DEV: This test guards the Phase 0 boot contract. If it fails,
	# WorldInitSystem is not being invoked on new game, or the scenario
	# → component projection pipeline regressed.
	var server: Node = Node.new()
	server.set_script(GAME_SERVER_SCRIPT)
	add_child_autofree(server)
	await get_tree().process_frame
	var db: GameStateDB = server.db
	var hums: Array[int] = db.get_entities_with(&"hum_receiver")
	var tunas: Array[int] = db.get_entities_with(&"tuna_dispenser")
	var arms: Array[int] = db.get_entities_with(&"arm")
	assert_eq(hums.size(), 1,
		"Starter scenario should spawn exactly 1 HUM receiver")
	assert_eq(tunas.size(), 1,
		"Starter scenario should spawn exactly 1 TUNA dispenser")
	assert_eq(arms.size(), 1,
		"Starter scenario should spawn exactly 1 ARM")
