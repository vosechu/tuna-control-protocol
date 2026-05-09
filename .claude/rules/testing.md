---
paths:
  - "tests/**"
  - "script/checks/gut_tests"
  - "script/checks/verify_tests"
  - "script/tdd_verify"
---

# TCP Testing Rules

> **Use `/load-game-qa`** when about to write tests or design test coverage and you want Kibble's edge-case-thinking and failure-mode rubric in front of you first.
> **Spawn the `game-qa` agent** when you have a feature or design to stress-test for "what happens when…" cases, coverage gaps, and shipping readiness.

---

## 0. QA Philosophy

Testing principles specific to a cozy emergent game.

1. **No lose condition doesn't mean no bugs.** A stuck animal, a stuck UI, a stuck progression path — these are failures even if the game doesn't say "game over." The absence of a fail state raises the bar on what counts as broken, not lowers it.
2. **Emergence must be testable.** You can't predict emergent behavior, but you can: (a) verify the inputs to emergence are correct (desires are being calculated, proximity is being detected); (b) verify the outputs are sane (no negative happiness, no infinite loops); (c) record and replay interesting scenarios as regression tests. Use the **anecdote test** (Kate Compton): after a 10-minute play session, can the tester tell a specific story about a specific animal? "Cats sat on warm things" = emergence isn't working. "Mittens kept going back to rack 3 because that's where she met the ferret" = working.
3. **Fun at scale is a QA concern.** "Thousands of kittens" requires a load-test prototype early — not for performance but to verify the *design* works at scale. Does the player still feel in control with 500 animals? Can they find a specific cat? Is the optimizer still challenging or has it become noise?
4. **First-time experience is sacred.** Tutorial/onboarding flows are tested with fresh saves on fresh installs, AND tested with the player doing things "wrong" (places box too high, ignores highlights, opens drawers in the wrong order). The new player has no design doc to fall back on.
5. **Every feature needs a multiplayer pass.** Wandering cats crossing boundaries, heat spilling between racks, sync timing, concurrent placement, disconnect mid-action. "We'll figure out multiplayer later" violates the day-one architecture rule. Every single-player feature needs at minimum a thought experiment about multiplayer implications.
6. **Emotional correctness matters.** A technically correct behavior can be emotionally wrong. "The cat made a sad face when I moved its box and the player didn't understand why" is a design failure, not a feature. In a cozy game, an unexplained sad cat is worse than a minor visual glitch.

---

## Core Belief
If it is not tested, it will break on the day of the demo. Pure core logic is testable without nodes. If you cannot test it without a scene tree, refactor it.

## Framework
GUT (Godot Unit Test). Tests live in `tests/` mirroring `src/` structure. Test files: `test_<thing>.gd`.

## Test Suites
- **Unit** (`tests/unit/`): Pure logic, no scene tree, no I/O.
- **Scene** (`tests/scene/`): Load `.tscn` files, instantiate, verify node structure and types. No game logic, no DB, no ticks. Catches parse errors, missing nodes, wrong types.
- **Integration** (`tests/integration/`): Node-to-core wiring, signal flow.
- **Scenario** (`tests/scenario/`): Multi-tick simulation stories.
- **Snapshot** (`tests/snapshot/`): Determinism — same seed = same output.
- **Soak** (`tests/soak/`): Run N ticks, assert invariants hold (no stuck animals, no negative values).
- **Performance** (`tests/perf/`): Budget enforcement with `measure_time()`.

## Suite Rules
- Unit tests: max 50ms each. No `await`, no `yield`, no filesystem.
- Scene tests: max 200ms each. Load and instantiate `.tscn`, verify structure. No game logic.
- Integration tests: max 500ms. May instantiate scenes via `add_child()`.
- Snapshot tests: serialize full state, compare against golden file.
- Soak tests: run 10,000+ ticks, assert invariants.
- Perf tests: measure time, assert under budget, log actual as telemetry.

## Expected Errors in Tests
GUT fails tests that trigger `push_error()` unless the error is consumed by an assertion. When testing code paths that intentionally call `push_error()` (validation failures, bad input), use `assert_push_error("substring")` after the call. This tells GUT the error was expected and prevents the test from failing on "unexpected errors."

```gdscript
func test_missing_field_returns_null():
    var result := MyParser.parse({"incomplete": true})
    assert_null(result)
    assert_push_error("missing required field")
```

Each `push_error` call must be matched by exactly one `assert_push_error`. Multiple errors need multiple assertions, in order.

Godot's built-in `assert()` halts the debug runner and cannot be trapped by GUT — there is no `assert_fail` helper. Code using `assert()` for programmer-error guards (bounds checks, invalid inputs per `.claude/rules/design-philosophy.md`) is not directly unit-testable. Document the uncovered guard as an intentional coverage gap in the test file's AI-DEV header rather than attempting to wrap it.

## CI Pipeline
1. `gdlint` — style enforcement
2. Unit + Scene + Integration — fail-fast
3. Snapshot — determinism gate
4. Soak — invariant gate
5. Perf — budget gate (warn only in PR, block in release)

## Coverage Targets
- Scenario tests: minimum 30 covering every desire type and species interaction. Written as: setup state → run N ticks → assert behavior.
- Simulation tests: headless, property-based across 20+ random seeds. Spawn 100-1000 animals, run 1000-10000 ticks, assert invariants.
- Snapshot tests: golden files are version-controlled. Regenerate with review on intentional changes.

---

## Test Exemplars

Each exemplar follows: **setup → action → assertion** with descriptive failure messages.

### Unit: Utility Scorer

```gdscript
extends GutTest

func test_food_desire_outscores_warmth_when_hungry():
    var scorer := UtilityScorer.new()
    # Hunger at 900/1000, warmth need at 400/1000
    var cat := AnimalState.new("tcp_base:cat", {hunger = 900, warmth_need = 400})
    var food := ResourceNode.new("food", Vector2i(10000, 5000))
    var warmth := ResourceNode.new("warmth", Vector2i(10000, 4800))
    var scores := scorer.evaluate(cat, [food, warmth])
    assert_gt(scores[food], scores[warmth],
        "Hungry cat (900) should prefer food over moderate warmth (400)")
```

### Unit: Spatial Hash

```gdscript
func test_spatial_hash_radius_query():
    var grid := SpatialHash.new(6400)  # cell_size in position units
    var expected: Array[int] = []
    for i in 100:
        var pos := Vector2i(randi_range(-50000, 50000), randi_range(-50000, 50000))
        grid.insert(i, pos)
        if pos.distance_to(Vector2i.ZERO) <= 12000:
            expected.append(i)
    var results := grid.query_radius(Vector2i.ZERO, 12000)
    assert_eq(results.size(), expected.size(),
        "Expected %d entities in radius, got %d" % [expected.size(), results.size()])
```

### Unit: Teaching Chain Degradation

```gdscript
func test_teaching_degrades_and_caps():
    var teaching := TeachingSystem.new()
    var master := AnimalState.new("tcp_base:cat", {})
    teaching.grant_skill(master, "knead_dough", 1000, 0)  # level 1000/1000, gen 0

    var gen1 := AnimalState.new("tcp_base:cat", {})
    teaching.teach(master, gen1, "knead_dough")
    assert_eq(gen1.get_skill("knead_dough").level, 700)   # 1000 * 0.7
    assert_eq(gen1.get_skill("knead_dough").generation, 1)

    var gen2 := AnimalState.new("tcp_base:cat", {})
    teaching.teach(gen1, gen2, "knead_dough")
    assert_eq(gen2.get_skill("knead_dough").level, 490)   # 700 * 0.7

    var gen3 := AnimalState.new("tcp_base:cat", {})
    teaching.teach(gen2, gen3, "knead_dough")
    assert_eq(gen3.get_skill("knead_dough").level, 343)   # 490 * 0.7

    # Gen 4 blocked by circuit breaker
    var gen4 := AnimalState.new("tcp_base:cat", {})
    var ok := teaching.teach(gen3, gen4, "knead_dough")
    assert_false(ok, "Teaching must fail beyond generation 3")
```

### Property-Based: Invariants Hold Across Seeds

```gdscript
func test_invariants_hold(p = use_parameters(_make_seeds(20))):
    seed(p[0])
    var sim := SimulationCore.new()
    sim.spawn_random_animals(randi_range(5, 50))
    for tick in 1000:
        sim.tick()
    for animal in sim.get_all_animals():
        assert_gte(animal.happiness, 0,
            "Animal %s happiness went negative" % animal.id)
        for d in animal.get_desires():
            assert_lte(d.weight, UNIT,
                "Desire %s exceeds max on %s" % [d.name, animal.id])
            assert_gte(d.weight, 0)

func _make_seeds(count: int) -> Array:
    var seeds: Array = []
    for i in count:
        seeds.append([randi()])
    return seeds
```

### Scenario: Ferret Prefers Tubes

```gdscript
func test_ferret_prefers_tubes_over_open_floor():
    var sim := SimulationCore.new()
    sim.place_infrastructure("tcp_base:gerbil_tube", Vector2i(20000, 10000), Vector2i(40000, 10000))
    var ferret_id := sim.spawn_animal("tcp_base:ferret", Vector2i(30000, 20000))
    for tick in 600:  # 30 simulated seconds at 20 tps
        sim.tick()
    var ferret := sim.get_animal(ferret_id)
    assert_gt(ferret.time_in_zone("tube"), ferret.time_in_zone("open_floor") * 2,
        "Ferrets should spend >2x time in tubes vs open floor")
```

### Integration: Node Delegates to State

```gdscript
func test_animal_node_delegates_feed_to_state():
    var state := AnimalState.new("tcp_base:cat", {hunger = 500})
    var node := AnimalNode.new()
    node.initialize(state)
    add_child_autofree(node)
    node.apply_feed(300)
    assert_eq(state.hunger, 200,
        "Node.apply_feed() must delegate to state")
```

### Snapshot: Deterministic Simulation

```gdscript
func test_determinism():
    var snap_a := _run_sim(42, 500)
    var snap_b := _run_sim(42, 500)
    assert_eq(snap_a, snap_b, "Same seed must produce identical state")

func _run_sim(s: int, ticks: int) -> Dictionary:
    var sim := SimulationCore.new()
    sim.set_seed(s)
    sim.spawn_animal("tcp_base:cat", Vector2i(10000, 10000))
    sim.spawn_animal("tcp_base:ferret", Vector2i(20000, 10000))
    for t in ticks:
        sim.tick()
    return sim.snapshot()
```

### Soak: No Stuck Animals

```gdscript
func test_no_stuck_animals_20min():
    var sim := SimulationCore.new()
    sim.set_seed(99)
    sim.spawn_random_animals(30)
    var last_pos: Dictionary = {}   # entity_id → Vector2i
    var stuck_secs: Dictionary = {} # entity_id → int
    for tick in 24000:  # 20 min at 20 tps
        sim.tick()
        if tick % 20 == 0:  # check every second
            for animal in sim.get_all_animals():
                var prev: Vector2i = last_pos.get(animal.id, Vector2i(999999, 999999))
                if animal.position.distance_to(prev) < 50 and animal.behavior != "resting":
                    stuck_secs[animal.id] = stuck_secs.get(animal.id, 0) + 1
                else:
                    stuck_secs[animal.id] = 0
                last_pos[animal.id] = animal.position
                assert_lt(stuck_secs.get(animal.id, 0), 60,
                    "Animal %s stuck for >60s at %s" % [animal.id, animal.position])
```

### Performance: Spatial Hash Budget

```gdscript
func test_spatial_hash_query_under_1ms_at_5000():
    var grid := SpatialHash.new(6400)
    for i in 5000:
        grid.insert(i, Vector2i(randi_range(-200000, 200000), randi_range(-200000, 200000)))
    var start := Time.get_ticks_usec()
    for _i in 100:
        grid.query_radius(Vector2i.ZERO, 20000)
    var avg_us := (Time.get_ticks_usec() - start) / 100
    assert_lt(avg_us, 1000, "query_radius avg %dμs exceeds 1ms budget" % avg_us)
```
