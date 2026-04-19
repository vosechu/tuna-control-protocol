---
paths:
  - "engine/animals/**"
  - "engine/desires/**"
  - "engine/core/contentment*"
  - "engine/core/animal*"
  - "engine/core/desire*"
  - "mods/*/species/**"
  - "config/balance/desire_thresholds.json"
---

# TCP Animal AI

## State Machine

Two layers: **meta-state** (AMBIENT vs. GOAL_DIRECTED) and **specific states**.

### States

**Ambient:** IDLE, GROOMING, LOAFING, STRETCHING, SLOW_BLINK, KNEADING, STARING, HEAD_TRACK, TAIL_FLICK, REPOSITIONING, SLEEPING, SNIFFING, SPEED_BUMP, STASH_CHECK

**Goal-directed:** SEEKING, MOVING_TO, PERFORMING, COMPLETING, HUNGRY, PACING, EATING

**Special:** STARTLED, RELOCATING, BEING_CARRIED

**States are universal, not species-specific.** `SLEEPING` covers what old specs called `DEAD_SLEEP`. Different species may weight states differently (ferrets sleep more dramatically, cats loaf more) but the state machine is the same. Species-flavored visuals live in each species recipe's `states` animation mapping, not in the state name. If you're tempted to add a state like `DEAD_SLEEP` or `WAR_DANCE`, add an animation variant keyed off `SLEEPING` or an existing ambient state instead.

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

**Reset commitment on arrival/completion/cancellation.** When an entity transitions from `GOAL_DIRECTED` back to `AMBIENT`, set `commitment_score = 0`. Leaving a stale commitment value in place traps the entity: typical ad scores are 200–350 and decay at 1/tick, so a post-arrival commitment of 315 demands the next target score > 315 + 150 = 465, which no ad produces. Symptom: entities that sniff one target and never move again. The goal that earned the commitment has been achieved — the value is meaningless after arrival.

### Ambient State Selection

Weighted random pool filtered by context: warm → grooming/kneading eligible, near other animal → slow blink eligible, high energy → SPEED_BUMP eligible, low energy → SLEEPING. Per-species weights live in the species recipe's `ambient_states` block, not in engine code.

---

## Object Advertisement Schema

```gdscript
class_name ObjectAdvertisement extends Resource

@export var desire_type: StringName    # "warmth", "food", "comfort", "quiet", etc. ("influence channel")
@export var strength: int = 500        # signed: positive = attractor (desire), negative = aversion. See Aversions section.
@export var radius_px: int = 3         # Rack units
@export var falloff_curve: Curve       # Linear by default (samples 0.0-1.0 for rendering)
@export var required_traversal: StringName = ""
@export var max_occupants: int = 1
var current_occupants: int = 0

func score_for(animal: AnimalAgent, distance_ru: int) -> int:
    if distance_ru > radius_px: return 0
    if required_traversal != "" and required_traversal not in animal.traversal_capabilities: return 0
    if not is_available(): return 0
    var desire_weight: int = animal.get_desire_weight(desire_type)
    var deficit: int = 1000 - animal.get_desire_satisfaction(desire_type)
    var dist_factor: int = 1000 - (distance_ru * 1000 / radius_px) if not falloff_curve else int(falloff_curve.sample(float(distance_ru) / float(radius_px)) * 1000)
    return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000
```

### PlacedObject Advertisement Config

```json
{
  "clothes_pile": {
    "advertisements": [
      {"desire_type": "comfort", "strength": 800, "radius_px": 1, "max_occupants": 3},
      {"desire_type": "stimulation", "strength": 400, "radius_px": 1, "max_occupants": 1}
    ]
  }
}
```

### No `species_filter` on ads

Advertisements never carry a species filter. The entity's own desire weights are the filter: a curiosity ad on a rack scores near-zero for a cat (curiosity weight ~100) and high for a ferret (weight ~700), emergently. Adding `species_filter: ["ferret"]` would be redundant and would also prevent any future curiosity-weighted species from ever interacting with the ad — exactly the species-label coupling the rest of the codebase avoids. If you want an ad only one species cares about today, give it a channel that species weights disproportionately.

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

- **Desire** — a channel expressed as a weight on the entity's `desires` component. Positive weight = attractor (the animal is pulled toward ads on this channel). Negative weight = repulsor (aversion). No separate `aversions` component exists; aversions are just negative entries in the same dict.
- **Signed advertisement** — objects emit ads with positive strength (attracting) or negative strength (repelling). A loud PDU advertises `{desire_type: &"noise", strength: -700, radius_px: 4}`. The word "desire_type" is retained for schema continuity; read it as "influence channel."
- **Satisfaction/deficit** — tracked for positive-weight channels only. An entity can be "hungry for warmth" (low satisfaction, high deficit) but not "hungry for silence." Aversions are simply avoided while present, never "met."

### Scoring formula (extended)

The advertisement score function branches on sign, but lives in one function:

```gdscript
func score_for(animal: AnimalAgent, distance_ru: int) -> int:
    if distance_ru > radius_px: return 0
    if required_traversal != "" and required_traversal not in animal.traversal_capabilities: return 0

    var dist_factor: int = 1000 - (distance_ru * 1000 / radius_px) if not falloff_curve else int(falloff_curve.sample(float(distance_ru) / float(radius_px)) * 1000)

    var weight: int = animal.get_desire_weight(desire_type)  # signed: positive = attractor, negative = aversion
    if strength >= 0 and weight >= 0:
        # Desire path: weighted by deficit so an entity with full warmth ignores warmth ads
        if not is_available(): return 0
        var deficit: int = 1000 - animal.get_desire_satisfaction(desire_type)
        return weight * deficit / 1000 * strength / 1000 * dist_factor / 1000
    else:
        # Aversion path: NO deficit term. An entity is not "deficit-hungry for quiet."
        # Either the ad is negative, the weight is negative, or both — in any case, no satisfaction to track.
        return weight * strength / 1000 * dist_factor / 1000
```

**Candidate scoring (`_evaluate_one`)** sums *all* ads in the radius rather than picking the single-best ad. A candidate location's utility is the sum of its attractors and repulsors. Clamp the *total*, not per-ad.

### Pitfalls (do not skip)

1. **Do not multiply aversion strength by deficit.** There is no "how hungry am I for silence." Aversion weight × strength × distance only.
2. **Clamp total score, not per-ad.** A strong nearby attractor should be able to pull an entity *into* a moderately noisy area if the warmth is compelling enough. Per-ad clamping prevents this and feels wrong.
3. **Distance falloff on negatives.** The `1000 - distance_factor` curve produces full strength at distance 0 and zero strength at the radius edge. This is correct for aversions: the PDU is maximally annoying when you're sitting on it and imperceptible from across the room. Do not invert the curve "because it's a negative."
4. **Hysteresis is free.** `SWITCH_THRESHOLD=150` and commitment_score decay already prevent entities from twitching away from transient loud noises. Aversions don't need their own hysteresis — the existing transition logic is sign-agnostic.

### Scatter pattern integration

Ambient aversions that radiate from a source (noise, heat-as-discomfort, crowding) follow the same scatter pattern as heat in `tick-architecture.md`. Example for noise: grid cells accumulate noise intensity from sources, and each tick the scatter phase projects cell-level noise into the receiving entity's `desires` satisfaction for the matching channel. Dirty-flagging works identically: when a value crosses a 100-band, mark the entity dirty.

### Warmth: heat grid + warm objects

Warmth satisfaction has two independent sources. Both run in scatter, both write the same `desires.warmth` channel:

1. **Heat grid** (`_scatter_desires` in game_server) — sets warmth from the cell temperature under the entity. Only covers cells near powered servers.
2. **Warm-object scatter** (`_scatter_warmth_from_objects`) — reduces warmth desire for entities near other entities that advertise warmth (clothes piles, sleeping cats, any entity with a `warmth` ad).

The heat grid doesn't know about warm objects, and object ads don't reach the grid — so without the object scatter, an entity curled on a clothes pile far from any server registers as cold. Warmth ads pull entities toward the warm object (SEEKING); the object scatter makes them *feel* warm on arrival. New warm objects participate automatically via their `warmth` ad plus the scatter's capability-driven query — no per-object code path.

### Species configuration

Species recipes declare one `desires` dict with signed weights. Negative entries are aversions:

```jsonc
"desires": {
  "warmth": 700,
  "comfort": 700,
  "curiosity": 150,
  "hunger": 700,
  "attention": 500,
  "noise": -600,      // aversion: cat is repelled by noise ads
  "chased": -900      // aversion: cat is repelled by being chased
}
```

**Naming convention:** aversions are named by the *thing being avoided* with a negative weight (the shipped choice). A loud PDU advertises `{desire_type: "noise", strength: 700}` (positive strength describing the thing); the cat's `"noise": -600` negative weight inverts the sign in scoring. Channel names are shared — the cat's `-600` weight on `noise` pairs with anyone emitting positive-strength `noise` ads. All thresholds, curves, and hysteresis bands go in `config/balance/desire_thresholds.json`.

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

## WANDERING (unmet-desire exploration)

When an entity is AMBIENT, has `commitment == 0`, its worst desire is ≥ `WANDER_THRESHOLD` (shipped: 800), and no in-range advertisement beats the switch threshold, the resolver picks a random floor position and transitions to `WANDERING`. On arrival, commitment is still 0 so the resolver re-evaluates immediately. If the new position is within range of an ad, normal SEEKING takes over.

**Why:** Perception radius is 8 RU. An entity can have a high unmet desire with the only satisfying ad outside perception — without WANDERING it would idle forever.

**Species-agnostic.** WANDERING branches on components + desire deficits, not on species labels. Any entity with a `desires` component participates. The threshold is intentionally high so mildly uncomfortable entities don't wander.

## Curiosity tracking

Entities carrying `curiosity_tracker` remember which curiosity ads they recently visited. The desire resolver applies a novelty check before scoring — recently-visited targets score 0 until their per-target `novelty_cooldown` elapses. On arrival at a novel curiosity target, the entity enters `SNIFFING` for `novelty_duration` ticks.

Current tuning (shipped in `game_server.gd`; should migrate to `config/balance/desire_thresholds.json`):

| Source | strength | novelty_duration | cooldown |
|---|---|---|---|
| Rack | 500 | 30 ticks (3s) | 100 ticks (10s) |
| Cat | 400 | 150 ticks (15s) | 50 ticks (5s) |
| Cardboard box | 500 | 400 ticks (40s) | 300 ticks (30s) |
| Clothes pile | 400 | 300 ticks (30s) | 200 ticks (20s) |

Ferret recipes weight `curiosity` heavily (starting value 700) because scores are multiplicative — at curiosity 0 the ad scores 0 regardless of deficit. Other species can participate by declaring `curiosity` and `curiosity_tracker` in their recipe; the system is capability-driven.
