---
paths:
  - "engine/core/contentment.gd"
  - "engine/core/sensory_emission_system.gd"
---

# TCP Contentment System

The keystone between desires and the purr loop. Reads each entity's `desires` component, decides whether enough basic needs are met, and writes a single `contentment.is_satisfied` flag. The `SensoryEmissionSystem` reads that flag (via the recipe-declared trigger) to gate `purr.intensity`. No other system writes `contentment`.

Tick step 4, between `_scatter_desires` (writes `desires`) and `sensory_emission.tick()` (reads `is_satisfied` via the recipe's trigger). See `tick-architecture.md` for full ordering.

## Component shape

```gdscript
{ &"is_satisfied": int }   # 0 or 1, never floats, never bool
```

Binary on/off — the bridge gates a binary purr. If you want a continuous "satisfaction score," add a separate component; do not change `is_satisfied`'s shape.

## Satisfaction formula

A bar is met when its `desires` field is `>= THRESHOLD`. An entity is satisfied when at least `BARS_NEEDED` of `BARS` are met.

```
THRESHOLD     = 400   # 0–1000 desire scale
BARS_NEEDED   = 3
BARS          = [&"warmth", &"comfort", &"hunger", &"attention"]
```

Boundary: exactly 400 counts (`>=`, not `>`). 399 does not. A bar missing from `desires` counts as **unmet** — there is no implicit "missing means satisfied" branch. This is what lets non-cat entities cleanly score 0 without any species check.

## Capability gating

`evaluate_all` iterates `db.get_entities_with(&"desires")`. Object entities (no `desires`) never receive a `contentment` component, which is what the bridge expects. If two species ever need different thresholds, add a per-recipe `contentment_config: {bars_needed: int}` component — never a species check.

## Debug override

`debug_force_satisfied: {active: 1}` bypasses the formula and writes satisfied. Forces *satisfied* only — there's no "force unhappy" channel. Not saved.

## The `attention` bar — known drift

`BARS` includes `attention`, but `animal-ai.md`'s 8-desire registry does not. `attention` is written by `engine/core/player_verbs.gd` (petting). Two future resolutions are open (promote to a first-class channel, or rename to `social`); both require migrating the petting verb and the bars list together. **Until that resolves, do not "clean up" by silently swapping the entry — the petting verb writes `attention` and would suddenly stop counting toward satisfaction.**

## Failure modes to watch

1. **Threshold drift via tuning.** Lowering `THRESHOLD` to "make cats purr more reliably" hides aversions — a cat under loud `noise` should *stop* purring, and that signal lives in the bars. Tune ad strengths or species weights instead. The threshold is a contract with the design.
2. **Adding a fifth bar without changing `BARS_NEEDED`.** 3-of-4 is why one moderately-unmet need still allows purring. Bumping to 4-of-5 keeps the ratio; 3-of-5 makes satisfaction much easier; 4-of-4 makes it brittle. Pick consciously, and update `tests/unit/test_contentment.gd` in the same commit.

## Related

- `animal-ai.md` — desire registry (the producer of `desires`)
- `hum-cable-system.md` — `SensoryEmissionSystem` and downstream HUM charging (recipe-driven emission)
- `core-loop.md` — design intent: "contented cats purr, purring charges HUM"
- `tick-architecture.md` — step ordering for the contentment → purr → charge chain
