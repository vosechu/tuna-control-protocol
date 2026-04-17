# TCP Animal AI

## State Machine

Two layers: **meta-state** (AMBIENT vs. GOAL_DIRECTED) and **specific states**.

### States

**Ambient:** IDLE, GROOMING, LOAFING, STRETCHING, SLOW_BLINK, KNEADING, STARING, HEAD_TRACK, TAIL_FLICK, REPOSITIONING, WAR_DANCE (ferret), DEAD_SLEEP (ferret), SPEED_BUMP (ferret), SNIFFING (ferret), SLEEPING_ON_CAT (ferret), STASH_CHECK (ferret)

**Goal-directed:** SEEKING, MOVING_TO, PERFORMING, COMPLETING

**Special:** STARTLED, RELOCATING, BEING_CARRIED

### Transitions

- AMBIENT → GOAL_DIRECTED: desire score exceeds current commitment + SWITCH_THRESHOLD (150)
- GOAL_DIRECTED → AMBIENT: action complete or desire satisfied
- Any → STARTLED: pounce, loud noise, infrastructure removal
- STARTLED → AMBIENT/IDLE: after 0.5-1.5 sec flee to safe spot

### Hysteresis Integration

```gdscript
var commitment_score: int = 0
var min_duration: float = 0.0  # Minimum time in current state (engine seconds)

func try_transition(new_state: State, score: int) -> bool:
    if state_timer < min_duration: return false
    if meta_state == GOAL_DIRECTED:
        if score < commitment_score + SWITCH_THRESHOLD: return false
    _enter_state(new_state, score)
    return true

func tick(delta: float) -> void:  # delta is engine time, stays float
    state_timer += delta
    commitment_score = maxi(0, commitment_score - int(10 * delta))  # Decays (10/1000 per sec)
```

### Ambient State Selection

Weighted random pool filtered by context: warm → grooming/kneading eligible, near other animal → slow blink eligible, ferret high energy → war dance, ferret low energy → dead sleep.

---

## Object Advertisement Schema

```gdscript
class_name ObjectAdvertisement extends Resource

@export var desire_type: StringName    # "warmth", "food", "comfort", "quiet", etc. ("influence channel")
@export var strength: int = 500        # signed: positive = attractor (desire), negative = aversion. See Aversions section.
@export var radius_ru: int = 3         # Rack units
@export var falloff_curve: Curve       # Linear by default (samples 0.0-1.0 for rendering)
@export var required_traversal: StringName = ""
@export var max_occupants: int = 1
var current_occupants: int = 0

func score_for(animal: AnimalAgent, distance_ru: int) -> int:
    if distance_ru > radius_ru: return 0
    if required_traversal != "" and required_traversal not in animal.traversal_capabilities: return 0
    if not is_available(): return 0
    var desire_weight: int = animal.get_desire_weight(desire_type)
    var deficit: int = 1000 - animal.get_desire_satisfaction(desire_type)
    var dist_factor: int = 1000 - (distance_ru * 1000 / radius_ru) if not falloff_curve else int(falloff_curve.sample(float(distance_ru) / float(radius_ru)) * 1000)
    return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000
```

### PlacedObject Advertisement Config

```json
{
  "clothes_pile": {
    "advertisements": [
      {"desire_type": "comfort", "strength": 800, "radius_ru": 1, "max_occupants": 3},
      {"desire_type": "stimulation", "strength": 400, "radius_ru": 1, "max_occupants": 1}
    ]
  }
}
```

### Scoring Loop (DesireResolver)

Uses the adaptive time budget from `tick-architecture.md`. Each tick, evaluates dirty entities in priority order (highest desire deficit first) until the time budget is spent.

```gdscript
const EVAL_TIME_BUDGET_USEC: int = 1000  # 1ms per tick

func evaluate_budget() -> void:
    var start := Time.get_ticks_usec()
    while _dirty.size() > 0:
        if Time.get_ticks_usec() - start >= EVAL_TIME_BUDGET_USEC:
            break
        var id: int = _pop_highest_deficit()
        _evaluate_one(id)

func _evaluate_one(entity_id: int) -> void:
    var x: int = db.get_field(entity_id, &"position", &"x")
    var y: int = db.get_field(entity_id, &"position", &"y")
    var ads: Array[int] = db.query_radius_with(x, y, 8_00, &"advertisements")
    var best_score: int = 0
    var best_ad_id: int = GameStateDB.INVALID_ID
    for ad_id in ads:
        var score: int = _score_advertisement(entity_id, ad_id)
        if score > best_score:
            best_score = score
            best_ad_id = ad_id
    var commitment: int = db.get_field(entity_id, &"ai_state", &"commitment_score")
    if best_score > commitment + SWITCH_THRESHOLD:
        _transition(entity_id, best_ad_id, best_score)
```

**Dirty marking:** The scatter system (see `tick-architecture.md`) marks entities dirty when a desire value crosses a threshold band (multiples of 100). Entities are also marked dirty on: cell movement, nearby entity arrival/departure, object placement/removal within perception radius.

**Priority:** `_pop_highest_deficit` returns the dirty entity with the largest gap between any desire's current value and its satisfaction level. Most-uncomfortable entities react first.

---

## Aversions (Signed Advertisements)

Animals have **desires** (attractors — warmth, food, comfort) and **aversions** (repulsors — noise, being sat on by big animals, being chased). Both live in the same scoring pass, using a single `advertisements` concept with **signed strength**. There is no separate "avoid list," no second scoring pipeline.

### Terminology

- **Desire** — a thing the animal is pulled toward. Stored as `AnimalState.desires[type] = weight`. Tracked with a `satisfaction` value so a deficit can be computed.
- **Aversion** — a thing the animal is pushed away from. Stored as `AnimalState.aversions[type] = weight`. No satisfaction/deficit — aversions are not "met," they are simply avoided when present.
- **Signed advertisement** — objects emit ads with positive strength (attracting) or negative strength (repelling). A loud PDU advertises `{desire_type: &"quiet", strength: -700, radius_ru: 4}`. The word "desire_type" is retained for schema continuity; read it as "influence channel."

### Scoring formula (extended)

The advertisement score function branches on sign, but lives in one function:

```gdscript
func score_for(animal: AnimalAgent, distance_ru: int) -> int:
    if distance_ru > radius_ru: return 0
    if required_traversal != "" and required_traversal not in animal.traversal_capabilities: return 0

    var dist_factor: int = 1000 - (distance_ru * 1000 / radius_ru) if not falloff_curve else int(falloff_curve.sample(float(distance_ru) / float(radius_ru)) * 1000)

    if strength >= 0:
        # Desire path: weighted by deficit so an entity with full warmth ignores warmth ads
        if not is_available(): return 0
        var desire_weight: int = animal.get_desire_weight(desire_type)
        var deficit: int = 1000 - animal.get_desire_satisfaction(desire_type)
        return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000
    else:
        # Aversion path: NO deficit term. An entity is not "deficit-hungry for quiet."
        var aversion_weight: int = animal.get_aversion_weight(desire_type)
        return aversion_weight * strength / 1000 * dist_factor / 1000  # result is negative
```

**Candidate scoring (`_evaluate_one`)** sums *all* ads in the radius rather than picking the single-best ad. A candidate location's utility is the sum of its attractors and repulsors. Clamp the *total*, not per-ad.

### Pitfalls (do not skip)

1. **Do not multiply aversion strength by deficit.** There is no "how hungry am I for silence." Aversion weight × strength × distance only.
2. **Clamp total score, not per-ad.** A strong nearby attractor should be able to pull an entity *into* a moderately noisy area if the warmth is compelling enough. Per-ad clamping prevents this and feels wrong.
3. **Distance falloff on negatives.** The `1000 - distance_factor` curve produces full strength at distance 0 and zero strength at the radius edge. This is correct for aversions: the PDU is maximally annoying when you're sitting on it and imperceptible from across the room. Do not invert the curve "because it's a negative."
4. **Hysteresis is free.** `SWITCH_THRESHOLD=150` and commitment_score decay already prevent entities from twitching away from transient loud noises. Aversions don't need their own hysteresis — the existing transition logic is sign-agnostic.

### Scatter pattern integration

Ambient aversions that radiate from a source (noise, heat-as-discomfort, crowding) follow the same scatter pattern as heat in `tick-architecture.md`. Example for noise:

```gdscript
# Step 3 (in tick order): scatter noise to aversions
func scatter_noise_to_aversions() -> void:
    for cell_idx in noise_grid.cell_count():
        var level: int = noise_grid.get_noise(cell_idx)
        for entity_id in _cell_entities[cell_idx]:
            db.set_field(entity_id, &"aversions", &"quiet", level)
```

Dirty-flagging works identically: when an aversion value crosses a 100-band, mark the entity dirty.

### Species configuration

Species JSON declares aversion weights the same way it declares desire weights:

```json
{
  "cat": {
    "desires": {"warmth": 800, "food": 700, "comfort": 900, "social": 600},
    "aversions": {"quiet": 400, "unchased": 900, "unsquished": 1200}
  },
  "ferret": {
    "desires": {"stimulation": 900, "hiding": 700},
    "aversions": {"quiet": 100, "open_space": 300}
  }
}
```

**Naming convention:** aversions are named by the *desired state*, not the thing being avoided. `quiet` not `noise`, `unchased` not `chased`. This keeps signed-advertisement semantics intuitive: a loud PDU advertises `{desire_type: "quiet", strength: -700}` — it reduces quietness in its radius. All thresholds, curves, and hysteresis bands go in `config/balance/desire_thresholds.json` alongside desires.

---

## Desire Activation (Maslow Layer)

Higher-order desire weights (curiosity, social, stimulation) scale via sigmoid as base needs (warmth, food, water) are met. No hard thresholds.

**Hysteresis offset:** Activation and deactivation thresholds differ. Example: curiosity activates around 600 warmth satisfaction, doesn't deactivate until warmth drops below ~450. Brief dips don't snap off behavior.

All threshold numbers, curve parameters, and hysteresis bands in `config/balance/desire_thresholds.json`, tunable per species.

## Occupancy & Collision

Soft occupancy, no hard blocking. Per-surface capacity in config (server top: 1 cat, clothes pile: 3 cats + 2 ferrets, tube segment: 1 ferret hard). Over-capacity → choose next-best destination. Pile-on exception: soft cap reduces everyone's comfort proportionally. Animals never block pathfinding. Visual overlap: z-sort + random offset.

## Object Removal

Universal 2-second CLEARING state. Object pulses, occupants receive eviction stimulus, exit via normal movement. Not clear in 2 sec → force-eject to floor with STARTLED. Never trap. Cancelling removal during CLEARING: object returns to normal, departing animals continue (hysteresis).

## Ambient-to-Goal Ratio

Target ~70/30 emerges naturally from desire math, not enforced. Well-met needs → 80-90% ambient. Critically unmet → 10-20% ambient. Dev metric: flag if 60-second average drops below 40%.
