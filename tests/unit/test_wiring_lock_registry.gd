extends GutTest

var _r: WiringLockRegistry


func before_each() -> void:
	_r = WiringLockRegistry.new()


func test_acquire_actuator_success() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var ok: bool = _r.acquire_actuator(42, 1, 100, 7, 42)
	assert_true(ok, "First acquire should succeed")
	assert_true(_r.is_locked_actuator(42))


func test_acquire_actuator_denies_second() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	_r.acquire_actuator(42, 1, 100, 7, 42)
	var ok: bool = _r.acquire_actuator(42, 2, 101, 7, 42)
	assert_false(ok, "Second peer must be denied while first holds lock")


func test_release_actuator_unlocks() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	_r.acquire_actuator(42, 1, 100, 7, 42)
	_r.release_actuator(42)
	assert_false(_r.is_locked_actuator(42))


func test_hum_end_keyed_by_cable() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	_r.acquire_hum_end(7, 42, 1, 100, 7, 42)
	var ok: bool = _r.acquire_hum_end(7, 99, 2, 101, 7, 99)
	assert_true(ok, "Different cable on same HUM may be held by different peer")


func test_expire_removes_stale_locks() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	_r.acquire_actuator(42, 1, 100, 7, 42)
	_r.tick_expire(400, 200)
	assert_false(_r.is_locked_actuator(42))


func test_entries_for_peer_filters() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	_r.acquire_actuator(42, 1, 100, 7, 42)
	_r.acquire_actuator(43, 1, 101, 8, 43)
	_r.acquire_actuator(44, 2, 102, 9, 44)
	assert_eq(_r.entries_for_peer(1).size(), 2)
	assert_eq(_r.entries_for_peer(2).size(), 1)


func test_synthetic_rows_cover_all_locks() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	_r.acquire_actuator(42, 1, 100, 7, 42)
	_r.acquire_actuator(43, 1, 101, 8, 43)
	var rows: Array = _r.synthetic_hum_cable_rows()
	assert_eq(rows.size(), 2)
	var hums: Array = []
	for row: Dictionary in rows:
		hums.append(row[&"hum_id"])
	assert_true(hums.has(7))
	assert_true(hums.has(8))


func test_get_actuator_entry_returns_original_hum() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	_r.acquire_actuator(42, 1, 100, 7, 42)
	var entry: Dictionary = _r.get_actuator_entry(42)
	assert_eq(entry[&"original_hum_id"], 7)
	assert_eq(entry[&"owner_peer_id"], 1)


func test_get_actuator_entry_missing_returns_empty() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	assert_true(_r.get_actuator_entry(42).is_empty())
