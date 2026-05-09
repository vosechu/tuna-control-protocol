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

State timers are integer ticks (incremented by 1 per simulation tick at 10 Hz). Minimum durations come per-state from the entity's recipe — never from an engine-side default table.

```gdscript
var commitment_score: int = 0       # decays at 1 per tick
var state_timer: int = 0            # ticks elapsed in current state

func try_transition(new_state: StringName, score: int) -> bool:
    if state_timer < min_duration_ticks_for(current_state): return false
    if meta_state == &"GOAL_DIRECTED":
        if score < commitment_score + SWITCH_THRESHOLD: return false
    _enter_state(new_state, score)
    return true
```

`AiStateSystem` increments `BehaviorTimers.state_timers[entity_id]` by 1 per tick and reads `min_duration_ticks` from the active ambient pool entry (`warm` or `cold`, picked by the entity's current `desires.warmth`). For special states (currently `STARTLED`), the duration comes from `special_states[STATE_NAME].min_duration_ticks`. The `SpeciesSchemaValidator` enforces both fields' presence at mod load — the runtime fallback is debug-only safety.

**Reset commitment on arrival/completion/cancellation.** When an entity transitions from `GOAL_DIRECTED` back to `AMBIENT`, set `commitment_score = 0`. Leaving a stale commitment value in place traps the entity: typical ad scores are 200–350 and decay at 1/tick, so a post-arrival commitment of 315 demands the next target score > 315 + 150 = 465, which no ad produces. Symptom: entities that sniff one target and never move again. The goal that earned the commitment has been achieved — the value is meaningless after arrival.

### Ambient State Selection

Weighted random pool filtered by context: warm → grooming/kneading eligible, near other animal → slow blink eligible, high energy → SPEED_BUMP eligible, low energy → SLEEPING. Per-species weights and per-state `min_duration_ticks` both live in the recipe's `ambient_states` block, not in engine code.

### Common slip patterns

| Slip | Why it bites | Fix |
|---|---|---|
| Leaving `commitment_score` non-zero on arrival, completion, or cancellation | Typical ad scores are 200-350; a stale 315 demands the next score > 465, which no ad produces. Symptom: entity sniffs one target and never moves again. | Set `commitment_score = 0` on every `GOAL_DIRECTED → AMBIENT` transition. |
| Adding a species-specific state like `DEAD_SLEEP` or `WAR_DANCE` | States are universal; species-specific naming bakes species into the AI and breaks the recipe-driven model. | Add an animation variant keyed off the existing state (e.g. `SLEEPING`) in the species recipe's `states` mapping. |
| Checking `is_available()` or capacity inside advertisement scoring | Cats can't see at distance whether a box is full — that's omniscience and kills emergence. | Score on weight × strength × deficit × distance only. Soft-cap on arrival via reduced comfort as occupants accumulate. |

---

## Object Advertisement Schema

```gdscript
class_name ObjectAdvertisement extends Resource

@export var channel: StringName            # must exist in Constants.CHANNELS — see perception-channels spec
@export var strength: int = 500            # 0-1000, always positive. Effect direction comes from CHANNELS[channel].effect.
@export var effect_radius_px: int = 16     # Hard cutoff for radius-delivery scatter. Cap: BAY_WIDTH_PX. Mutually exclusive with effect_slot.
@export var effect_slot: bool = false      # Slot-delivery: full strength to slot occupants, zero elsewhere. Mutually exclusive with effect_radius_px.
@export var falloff: StringName = &"quadratic"   # step | linear | quadratic | inverse_square — radius delivery only.
@export var required_traversal: StringName = ""
@export var max_occupants: int = 1
var current_occupants: int = 0

func score_for(animal: AnimalAgent, distance_px: int) -> int:
    if required_traversal != "" and required_traversal not in animal.traversal_capabilities: return 0
    var meta: Dictionary = Constants.CHANNELS[channel]
    var sense: StringName = meta[&"sense"]
    var sense_range: int = animal.senses.get(sense, Constants.BAY_WIDTH_PX)
    if distance_px > sense_range: return 0
    var target: StringName = meta[&"desire"]
    var weight: int = animal.get_desire_weight(target)             # always positive
    var dist_factor: int = 1000 - (distance_px * 1000 / sense_range)
    if meta[&"effect"] == &"satisfy":
        var deficit: int = 1000 - animal.get_desire(target)
        return weight * strength / 1000 * deficit / 1000 * dist_factor / 1000
    else:  # deplete
        return -1 * weight * strength / 1000 * dist_factor / 1000
```

`is_available()` is **not** checked in scoring. Cats cannot see whether a box is full at distance — that would be omniscient. Capacity dynamics are handled on arrival via soft-occupancy (cap reduces comfort proportionally as occupants accumulate). Distance falloff in scoring scales over sense range, not `effect_radius_px` — scoring answers "how far must I walk?", scatter answers "is the effect reaching me right now?"

### PlacedObject Advertisement Config

```json
{
  "clothes_pile": {
    "advertisements": [
      {"channel": "comfort", "strength": 800, "effect_slot": true, "max_occupants": 3},
      {"channel": "warmth",  "strength": 300, "effect_radius_px": 16, "max_occupants": 3}
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
    var ads: Array[int] = db.query_radius_with(x, y, Constants.BAY_WIDTH_PX, &"advertisements")
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

The spatial query bound is `BAY_WIDTH_PX = 186` (one bay). Per-sense gating happens inside `score_for` after the query returns the candidate set. Single best ad wins — sum-with-aversion is a future spec, not the current shape.

**Dirty marking:** The scatter system (see `tick-architecture.md`) marks entities dirty when a desire value crosses a threshold band (multiples of 100). Entities are also marked dirty on: cell movement, nearby entity arrival/departure, object placement/removal within perception radius.

**Priority:** `_pop_highest_deficit` returns the dirty entity with the largest gap between any desire's current value and its satisfaction level. Most-uncomfortable entities react first.

---

## Aversions (Channel Effect Direction)

Animals have a single `desires` dict of **positive weights**. Aversion is encoded by the **channel registry's effect direction**, not by signing a weight. There is no signed-strength concept anywhere — the previous shipped encoding (`desires.noise: -600`) is retired.

### Terminology

- **Channel** — emitter-side name (`warmth`, `noise`, `chaos`, `startle`, etc.). What's being emitted.
- **Desire** — receiver-side name (`warmth`, `quiet`, `peace`, `safety`, etc.). What's being affected on the cat. Always tracked as a positive value (0–1000).
- **Effect** — `satisfy` or `deplete`. Lives in the channel registry, not on the ad. A `warmth` ad always satisfies; a `noise` ad always depletes.

The registry in `Constants.CHANNELS` maps each channel to its `{sense, desire, effect}` triple. See `docs/superpowers/specs/2026-05-02-perception-channels-design.md` for the full schema. Six attractors (`warmth`, `comfort`, `safety`, `food`, `social`, `curiosity`) and six aversions (`chill`, `chaos`, `startle`, `stench`, `hostility`, `noise`).

Two aversion channels target dedicated rest desires: `noise → quiet (deplete)`, `chaos → peace (deplete)`. The other four deplete an attractor desire directly: `chill → warmth`, `startle → safety`, `stench → food`, `hostility → social`.

### Scoring formula

`ObjectAdvertisement.score_for()` branches on `effect`, not on a sign bit. See the §"Object Advertisement Schema" section above for the full code. Summary:

- `satisfy` → `weight * strength / 1000 * deficit / 1000 * dist_factor / 1000` (positive contribution; weighted by how unmet the desire is).
- `deplete` → `-1 * weight * strength / 1000 * dist_factor / 1000` (negative contribution; **no deficit term** — a cat is not "deficit-hungry for quiet").

`_evaluate_one` picks the highest single score (best_score). Sum-with-aversion across multiple ads is a future spec, not the current shape — the previous draft of this rule said sums were the rule, but shipped behavior is best-score.

### Pitfalls (do not skip)

1. **No deficit term on deplete channels.** A cat is not "deficit-hungry for quiet." `weight × strength × dist_factor` only.
2. **All weights are positive.** If you're writing `desires.noise: -600`, stop. The cat wants `desires.quiet: 600`; `noise` is an emitter-side channel that depletes that desire via the registry.
3. **Distance falloff scales over sense range, not effect_radius.** Scoring's distance term answers "how far must I walk?" — relative to the cat's sense, not the ad's emitter physics. `effect_radius_px` is for scatter only.
4. **Hysteresis is free.** `SWITCH_THRESHOLD=150` and commitment_score decay prevent twitching away from transient depleters. Negative best_score is handled by the existing transition logic (a strongly depleting candidate only "wins" if no positive candidate scores higher).

### Scatter pipeline

Scoring picks goals to walk toward; **scatter applies effects** to entities physically reached by an ad. They're separate passes — scatter runs *before* scoring within each tick (see perception spec §"Tick discipline") so that scoring's deficit term reflects the current scatter contribution.

Scatter writes to `desires` via `CHANNELS[channel].effect`:
- `satisfy` → `desires[target] += strength × falloff`, clamped to 1000.
- `deplete` → `desires[target] -= strength × falloff`, clamped at 0.

Slot-delivery ads (`effect_slot: true`) land at full strength on every entity in the ad owner's slot; radius-delivery ads scatter with the ad's `falloff` curve, gated additionally by the receiver's `senses` block. Ambient depleters (a buzzing PDU emits `noise`) follow the same scatter pattern as warmth — see `tick-architecture.md`.

### Warmth: heat grid + warm objects

Warmth satisfaction has two independent sources. Both run in scatter, both write the same `desires.warmth` channel:

1. **Heat grid** (`_scatter_desires` in game_server) — sets warmth from the cell temperature under the entity. Only covers cells near powered servers.
2. **Warm-object scatter** (`_scatter_warmth_from_objects`) — reduces warmth desire for entities near other entities that advertise warmth (clothes piles, sleeping cats, any entity with a `warmth` ad).

The heat grid doesn't know about warm objects, and object ads don't reach the grid — so without the object scatter, an entity curled on a clothes pile far from any server registers as cold. Warmth ads pull entities toward the warm object (SEEKING); the object scatter makes them *feel* warm on arrival. New warm objects participate automatically via their `warmth` ad plus the scatter's capability-driven query — no per-object code path.

### Species configuration

Species recipes declare a `senses` block (perception acuity) and a `desires` dict (motivation weights co-located with passive decay rates). All weights are positive — effect direction comes from the registry.

```jsonc
"senses": {
  "sight":   186,   // bay-wide visual acuity
  "hearing": 186,
  "smell":   186,
  "touch":    64    // cats sense ambient temperature gradients out to ~64 px
},
"desires": {
  "warmth":    { "weight": 700, "decay": -2 },
  "comfort":   { "weight": 700, "decay": -5 },
  "hunger":    { "weight": 700, "decay":  0 },
  "safety":    { "weight": 800, "decay":  0 },
  "social":    { "weight": 500, "decay": -2 },
  "curiosity": { "weight": 150, "decay": -3 },
  "quiet":     { "weight": 600, "decay":  0 },   // auditory-rest, depleted by noise ads
  "peace":     { "weight": 500, "decay":  0 }    // visual-rest, depleted by chaos ads
}
```

The desire dict has at most 8 entries: 6 attractor desires (`warmth`, `comfort`, `hunger`, `safety`, `social`, `curiosity`) + `quiet` + `peace`. Aversion channels that target attractor desires (`chill → warmth`, `startle → safety`, etc.) use the same weight as the attractor — the `safety` weight applies to both incoming `safety` ads (satisfy) and `startle` ads (deplete). All thresholds, curves, and hysteresis bands stay in `config/balance/desire_thresholds.json`.

### Per-species desire decay

Each `desires.<channel>.decay` is the per-tick passive decay applied to that entity's `desires.<channel>` value. Decay must be `<= 0` (decay-only mechanic — `SpeciesSchemaValidator` rejects positive values). `decay: 0` means no passive decay; the channel only changes via scatter or explicit writes.

`DesireDecaySystem` runs inside the scatter step every tick. It reads each entity's `desire_decay` component (a flat `{channel: int}` dict materialized from the recipe at spawn) and applies the per-channel deltas in one batched `GameStateDB.add_field_subset` call per channel — never branches on species labels.

### Walking speed

Each species recipe declares walk speed in `body_capabilities.walks.speed_px_per_tick` (integer pixels per simulation tick, currently 10 Hz). `MovementSystem.tick()` reads this per-entity for every step — different recipes step at different speeds without code changes.

```jsonc
"body_capabilities": {
  "walks": { "speed_px_per_tick": 2 },
  "jumps": { "max_height_ru": 4 }
}
```

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
