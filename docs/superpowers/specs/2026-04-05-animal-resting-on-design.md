# Animal Resting-On Design Spec

> **Note (2026-04-16):** Identifiers referenced in this document may be outdated.
> `species_filter` was never implemented and is removed. `cat_presence` → `reclamation`,
> `cat_seconds` → `tended_seconds`, `is_purring` → `is_satisfied`. Anchor rule and
> species-recipe schema live in `CLAUDE.md` ("Species Are Component Recipes") and
> `.claude/rules/modding.md` (Species Recipe Schema).

**Date:** 2026-04-05
**Ring:** 1
**Status:** Approved
**Prerequisites:** Social desire type, STARTLED drop-to-floor recovery (both included in this spec)

## Summary

Animals can sleep on other animals and on objects. A ferret moves to a sleeping cat, climbs on, curls up, and rests. The system generalizes to any entity pair via config — cats, servers, boxes, clothes piles, anything with the right config is a surface.

**Core principle:** States produce advertisements. Advertisements attract animals. What happens on arrival is determined by the join type. Dissolution has two paths: gradual (ads change, desires shift, animal leaves naturally) and physical (surface removed, STARTLED cascade, everyone falls to the floor). No hardcoded cleanup triggers.

**Relationships are named after the state they join:** SLEEPING → `sleeping`, PLAYING → `playing`. No redundant vocabulary.

## 1. State Advertisements

### The general pattern

States can advertise desires. This is not a resting-on concept — it's a general system. A SLEEPING cat advertises warmth/comfort (attracts smaller animals to sleep on it). A PLAYING cat advertises social/stimulation (attracts others to join play). The mechanism is always the same: the state produces ads, other animals score them, behavior emerges.

On any state transition, the system looks up the new state in the species' `state_advertisements` config. The entity's state-sourced ads are replaced wholesale with the new state's ads. If the new state isn't listed, all state-sourced ads are removed. No diffing — just replace. State-sourced ads are tagged `"source": "state"` to distinguish them from permanent ads.

**Key consequence:** If two states share the same ads and join config (SLEEPING and SNORING both have `stack` join with warmth+comfort), transitioning between them changes nothing — the ads are replaced with identical ones, the ferret on top doesn't notice. But transitioning to a state with different ads (SLEEP_TWITCHING has warmth but no join) means the join ads disappear, the safety check fires, and the ferret falls off. The system reacts to what the ads *are*, not which state produced them.

### Config structure

```json
{
  "cat": {
    "state_advertisements": {
      "SLEEPING": {
        "ads": [
          {"desire_type": "warmth", "strength": 600, "radius_ru": 1},
          {"desire_type": "comfort", "strength": 500, "radius_ru": 1}
        ],
        "join": {
          "type": "stack",
          "direction": "any",
          "capacity": 3,
          "slots": [
            {"x": -200, "y": -800},
            {"x": 200, "y": -750},
            {"x": 0, "y": -850}
          ]
        }
      },
      "LOAFING": {
        "ads": [
          {"desire_type": "warmth", "strength": 400, "radius_ru": 1},
          {"desire_type": "comfort", "strength": 300, "radius_ru": 1}
        ],
        "join": {
          "type": "stack",
          "direction": "any",
          "capacity": 3,
          "slots": [
            {"x": -200, "y": -800},
            {"x": 200, "y": -750},
            {"x": 0, "y": -850}
          ]
        }
      },
      "PLAYING": {
        "ads": [
          {"desire_type": "social", "strength": 700, "radius_ru": 3},
          {"desire_type": "stimulation", "strength": 500, "radius_ru": 3}
        ],
        "join": {
          "type": "nearby",
          "direction": "same",
          "capacity": 4,
          "radius_ru": 2
        }
      }
    },
    "join_weight": 5,
    "distance_sensitivity": 300
  }
}
```

### Join types

The `join` block describes what happens when another animal arrives — the spatial contract between joiner and host.

| Join type | Position coupling | Relationship | Spatial behavior |
|---|---|---|---|
| `stack` | Locked to host position + slot offset. Updated every tick. | `sleeping`, `loafing`, etc. (derived from state) | Physically on top. Moves with host. Falls if host's join disappears. z_index +1. |
| `nearby` | None — joiner moves freely within radius. | `playing`, etc. (derived from state) | Proximity-based. Desire-driven dissolution only. No safety check needed. |

Join type is required. `nearby` and `stack` are implemented in v1. Future join types (e.g., `face` — stand at a specific offset facing the host) can be added without changing existing config.

### Direction

Required on all join types. No magic defaults anywhere in this system.

| Direction | Meaning |
|---|---|
| `same` | Joiner faces the same way as host |
| `opposite` | Joiner faces the host (for face-to-face interactions) |
| `any` | Don't care (sleeping on top — facing doesn't matter) |

For `stack`, direction affects the joiner's sprite flip. For `nearby`, direction affects which way the joiner orients when it settles into proximity.

### Relationship naming

Relationships are derived from the state name: SLEEPING → `db.add_relationship(&"sleeping", joiner_id, host_id)`. No config needed. No redundant vocabulary. Queries read naturally: "who is `sleeping` on cat_02?" "who is `playing` with kitten_03?"

### Scoring

The DesireResolver scores state-sourced ads identically to object ads and permanent animal ads. No special path. Cats compete with clothes piles, warm servers, and other cats — whatever scores highest wins.

### Distance sensitivity

Species-specific distance weighting in config. Higher value = distance matters more in scoring.

```json
{
  "cat": { "distance_sensitivity": 300 },
  "ferret": { "distance_sensitivity": 800 }
}
```

Ferrets (short legs) prefer the nearest option. Cats are willing to walk further for the right spot. Affects ALL ad scoring, not just state ads.

### Desire weights handle filtering

No `species_filter` on advertisements. Ads broadcast, animals decide. A kitten's high comfort weight makes it score the cat's ad highly. A cat's lower comfort weight means it rarely targets another cat. The desire math handles it.

## 2. Weight-Based Occupancy

Flat capacity can't express "5 kittens OR 1 ferret." Instead, use weight-based capacity.

`join_weight` is a top-level property in each species' JSON (how much space this species takes when joining). `capacity` is per state's join config (how much weight this surface supports in this state). Different states can support different weights — a LOAFING cat might support less than a SLEEPING cat.

Example from `mods/tcp_base/species/cat.json`:
```json
{
  "join_weight": 5
}
```

Example from `mods/tcp_base/species/kitten.json`:
```json
{
  "join_weight": 1
}
```

Example from `mods/tcp_base/species/ferret.json`:
```json
{
  "join_weight": 3
}
```

A SLEEPING cat (capacity 3) fits 3 kittens (1 each), or 1 ferret (3), but not an adult cat (5). A SLEEPING dog (capacity 10) fits 3 ferrets + 1 kitten, or 8 kittens.

**Occupancy check at arrival, not scoring.** Scoring is speculative — two ferrets can both target the same cat. When the first arrives and creates the relationship, the second arrives, fails the occupancy check, and falls back to IDLE to re-evaluate.

**Capacity means different things per join type:**

- **`stack`**: weight-based. Each joiner's `join_weight` counts against capacity. A cat (capacity 3) fits 3 kittens (weight 1 each) or 1 ferret (weight 3). Physical size matters for stacking.
- **`nearby`**: headcount. `join_weight` is ignored. Capacity 4 means 4 animals, regardless of species. A cat can play with 4 kittens or 4 ferrets equally — play is about attention, not body size.

## 3. Relationship & Position Coupling

### Relationship creation

When a joiner arrives at a host entity (animal or object) and begins PERFORMING, the system:

1. Checks occupancy (total join_weight of existing joiners + new joiner <= capacity)
2. Creates relationship derived from state: `db.add_relationship(&"sleeping", joiner_id, host_id)`
3. For `stack` type: assigns the joiner to the next available slot
4. For `nearby` type: no slot assignment, joiner stays within radius

This works for any entity with a `join` config — cats, servers, boxes, clothes piles, anything.

### Position coupling (stack type only)

A second pass in the movement system runs *after* the main movement loop (not interleaved). This avoids 1-tick lag where the joiner reads the host's stale position.

```gdscript
# After main movement loop — iterate all stack-type relationships
for joiner_id in _get_stack_joiners():
    var host_id: int = _get_stack_host(joiner_id)
    # Safety: is the host still valid with a stack join?
    if not db.has_entity(host_id) or not _has_stack_join(host_id):
        _remove_join_relationship(joiner_id, host_id)
        _startle(joiner_id)
        continue
    var offset: Dictionary = _get_assigned_slot(joiner_id, host_id)
    db.set_field(joiner_id, &"position", &"x",
        db.get_field(host_id, &"position", &"x") + offset.x)
    db.set_field(joiner_id, &"position", &"y",
        db.get_field(host_id, &"position", &"y") + offset.y)
```

### Slots

Slots are defined in the host's state join config. Joiners are assigned to slots on arrival (first-come, first-served). Multiple joiners each get a distinct position — 3 kittens on a cat don't stack on the same pixel.

### Relationship dissolution: emergent, not triggered

**No hardcoded cleanup triggers.** Dissolution has two paths, both driven by the ad/join system:

**Gradual (desire-driven):** The host's state ads satisfy the joiner's desires. When the host transitions to a state with different or no ads, the joiner's satisfaction drops. The DesireResolver re-evaluates, and the joiner transitions out through normal AI. The joiner *discovers* the problem through its own desires, like ClumsyMan discovering CatWithLongTail moved.

**Physical (STARTLED cascade):** The host's surface is physically removed (player removes server, object enters CLEARING). The host animal falls to the floor with STARTLED. STARTLED has no `join` config, so the host's join ads disappear. The safety check in the position coupling pass fires immediately — joiners are STARTLED and fall to the floor too. Cascade completes in 1-2 ticks.

**Examples:**

- **Cat gets hungry:** Cat exits LOAFING → state ads replaced with nothing (SEEKING has no entry) → ferret's comfort/warmth satisfaction drops → DesireResolver scores ferret → ferret transitions to SEEKING something else. Desire-driven, takes a few ticks.
- **Cat shifts to lighter sleep:** SLEEPING → SNORING (both have stack join with same ads) → ads replaced with identical ones → ferret notices nothing. Seamless.
- **Cat twitches:** SLEEPING → SLEEP_TWITCHING (warmth only, no join) → join ads gone → safety check fires → ferret STARTLED.
- **Server removed:** Server enters CLEARING → cat evicted + STARTLED → cat drops to floor → STARTLED has no join → cat's join ads gone → safety check fires for ferret → ferret STARTLED + drops to floor. Both on the floor, startled, within 1-2 ticks.
- **Modder adds new state:** YOGA not in `state_advertisements` → no ads → stacking dissolves. Nothing to forget.

### Safety check in position coupling

The position coupling pass checks each tick: does the host entity still exist, and does it still have a `stack` join in its current state ads? If either fails, break the relationship immediately and STARTLED the joiner. This covers the 1-2 tick window between ads disappearing and the DesireResolver budget reaching the joiner.

This is belt-and-suspenders for `stack` joins only. `nearby` joins dissolve purely through desires — no safety check needed because there's no position coupling to break.

### Mutual desire effects

While a joiner is stacked on a host animal:

- **Host animal:** comfort reduced per joiner (-50 per join_weight unit), social increased (+150 per joiner, capped). A cat with degraded comfort stands up naturally — emergent rejection, no special mechanic.
- **Joining animal:** warmth satisfied, comfort satisfied, social satisfied (from proximity scatter + direct stacking bonus).

### Save/load

The relationship table serializes in the save payload:

```json
{
  "relationships": {
    "sleeping": [[joiner_id, host_id, slot_index], ...],
    "playing": [[joiner_id, host_id], ...]
  }
}
```

### Multiplayer (designed, not implemented in prototype)

Relationships are server-authoritative. Included in `snapshot_delta()` / `apply_delta()`.

**`stack` joins are server-confirmed before any visual transition.** The client does NOT predict stack joins. When a joiner arrives at a host, the client shows the joiner standing next to the host and waits for the server delta confirming the relationship. Then it plays the climb-on tween. This means a ~100ms delay (one server tick at 10Hz) between arrival and the visual climb — barely noticeable in a cozy game. The benefit: if two joiners race for the same host, the loser never starts climbing. No rollback, no awkward reversal, no bounce-off animation. The client only ever shows confirmed state.

**`nearby` joins don't need this** — there's no visual transition to fake. The animal is just nearby, moving freely.

**Position coupling for `stack` joins:** Client must derive joiner position from host position while relationship exists (not interpolate independently). Otherwise the joiner visually slides off the host during interpolation frames. Estimated 10-15 lines in the node layer when networking arrives — not an architectural change.

## 4. Prerequisites

### 4a. Social Desire

Currently implemented: warmth, comfort, curiosity. Social is referenced in the rules but not yet in code.

**Implementation:**

- Add `social` to desire components on all animals (initial value + weight per species in config)
- `scatter_social_to_desires()` in tick loop: counts nearby animals per cell, maps count to social satisfaction via curve
- Social weight per species: cats moderate (~500), ferrets high (~700), kittens very high (~800)
- Hysteresis: activation/deactivation thresholds differ per the existing Maslow layer design, tunable in `config/balance/desire_thresholds.json`

**Interaction with resting-on:** The proximity scatter naturally satisfies social for co-located animals. Stacking provides additional social via mutual desire effects (host animal gets +150 per joiner). The two stack — being rested on while surrounded by other animals is extra social. Abundance philosophy.

**Scope note:** Social desire is useful far beyond resting-on (companionship-seeking, group formation, loneliness as motivation). This spec implements the minimum needed, but the scatter system naturally enables broader behaviors.

### 4b. STARTLED Drop-to-Floor Recovery

Currently STARTLED just waits 0.5-1.5 seconds then transitions to IDLE at the animal's current position. There is no "find valid ground" logic. This means removing a server leaves a cat floating in midair — broken regardless of resting-on, but this spec makes it critical because physical cascades (server removed → cat falls → ferret falls) depend on it.

**The problem:** An animal can be STARTLED while standing on something that no longer exists (removed server, removed object, animal that moved away). It needs to end up on a valid surface.

**Implementation:**

On STARTLED entry, check whether the entity's current position is on a valid surface:

1. **On a valid surface (floor, existing object, existing animal with stack join):** Stay put. Wait 0.5-1.5 sec. Recover to IDLE normally.
2. **On nothing (surface was removed):** Find the nearest valid position below. In prototype without full navgraph: drop to the floor directly below (same x, floor y). Visually: downward tween at gravity speed to sell the fall. Then wait startled duration. Then IDLE.

```gdscript
func enter_startled(entity_id: int) -> void:
    state_machine.enter_startled()
    # Check if we're standing on air
    if not _has_valid_surface_below(entity_id):
        var floor_y: int = _get_floor_y_at(entity_id)
        db.set_field(entity_id, &"position", &"y", floor_y)
        # Node layer handles the visual tween from old y to new y
```

**Why "drop to floor below" is enough for prototype:** The full nav system (AStar2D point graph) isn't implemented yet. When it is, this becomes "pathfind to nearest valid floor node." For now, every position has a floor directly below it — the floor strip runs the full width of the datacenter. Dropping straight down is always valid.

**This fixes more than resting-on:** Any object removal that leaves an animal hovering (server pulled out, shelf removed, tube disconnected) now works correctly. It's a general fix exposed by the resting-on cascade.

## 5. Visual & Audio

### V1 (existing assets, no new art/sound)

| Moment | Visual | Sound |
|---|---|---|
| Approach | Existing walk cycle | Existing footsteps |
| Climb on | Position tween upward (~300ms) using walk frames, then swap to sleep/liedown frame | `clothing_rustle_01.wav` at -8 dB |
| Settled | Ferret: `lilotter_sleep_strip4`. Kitten: last frame of `liedown` | Cat purr continues |
| Startled off | Existing STARTLED animation + downward tween (4px over 150ms) | `ferret_dook_01.wav` + purr gap (50-100ms) |
| Cat reaction | None (existing liedown) | None |

### Z-sorting

Resting animals get `z_index += 1` on the node when a `stack` relationship starts, reset to 0 when it ends. Y-sort alone fails because the joiner's y-origin is higher than the host's.

### Bespoke assets (when available)

Tracked in living docs:
- Art: `docs/art-asset-tracker.md` — ferret curl (high), climb-on frames (high), cat weighted liedown (medium)
- Sound: `docs/sound-asset-tracker.md` — ferret churr settle (high), ferret breathing loop (high), cat mrrp (medium)

Key audio vision: ferret sleep breathing layered at -12 dB on cat purr creates a polyrhythm — the audible indicator of stacking. A player who knows the sound can hear "that's not just a cat" without looking.

### Future visual enhancement: breath riding

When stacked, the joiner's y-offset could include a small sine wave synced to the host's breathing animation. In a tall stack (dog → cat → ferret → mouse), the mouse at the top would bob noticeably as all the breathing cycles align and diverge. Pure rendering — no core position change. Not in v1.

## 6. Testing

### Unit tests

- Cat in SLEEPING has state-sourced ads with stack join; cat in SEEKING has none
- Cat transitioning SLEEPING→SNORING (both have stack join with same ads): ads unchanged, joiners unaffected
- Cat transitioning SLEEPING→SLEEP_TWITCHING (no join): join ads gone
- State not in state_advertisements: all state-sourced ads removed
- Object with join config (server, box) has ads when placed
- Relationship created with state-derived name: SLEEPING → `sleeping`
- Position coupling: joiner pos = host pos + slot offset after movement tick
- Slot assignment: first joiner gets slot 0, second gets slot 1
- Occupancy: arrival fails when join_weight sum would exceed capacity
- Weight math: 3 kittens (weight 1) fit on cat (capacity 3), 1 ferret (weight 3) fills it
- Social desire scatter: nearby animals increase social satisfaction
- Safety check: host entity gone → relationship removed, joiner startled
- Safety check: host has no stack join in current state → relationship removed, joiner startled
- STARTLED on valid surface → stays at current position, recovers to IDLE
- STARTLED on nothing (surface removed) → position drops to floor y below
- Direction `same`/`opposite`/`any` correctly affects joiner sprite flip

### Integration tests

- Full cycle: cat sleeps → ferret scores cat's ad → moves → arrives → `sleeping` relationship → positions coupled
- Full cycle on object: cat scores server warmth → moves → arrives → stacked on server
- Cat's comfort degrades from joiner weight → cat eventually seeks comfort elsewhere → state ads replaced with nothing → ferret's desires shift → ferret transitions out naturally
- Two ferrets target same cat → first wins occupancy → second bounces to IDLE
- Cascade: ferret stacked on cat stacked on server → server removed → CLEARING evicts cat → cat STARTLED (drops to floor) → cat's state ads gone → safety check fires for ferret → ferret STARTLED (drops to floor). Both on the floor, startled, within 1-2 ticks.

### Scenario tests

- Server removed → heat drops → cat relocates → cat's state ads gone → ferret displaced → both find new spots
- Cat does ambient REPOSITIONING while ferret stacked → cat still in SLEEPING → ads persist → ferret rides along
- Player removes object while animal is stacked on it → CLEARING pattern → animal STARTLED → drops to floor
- Full cascade: ferret on cat on server → server removed → cat STARTLED + drops to floor → cat state ads gone → ferret STARTLED + drops to floor
- Mutual desire: cat comfort decreases and social increases while being stacked on → cat with low comfort tolerance eventually stands
- `nearby` join: cat plays → kitten joins `playing` relationship → cat stops playing → kitten's social/stimulation drops → kitten wanders off naturally

### Soak invariants (10,000+ ticks)

- No `stack` relationship where host entity does not exist
- No `stack` relationship where host has no stack join in current state ads
- No entity in a `stack` relationship with zero position updates for 60+ consecutive ticks
- Joiner position minus host position equals assigned slot offset (within 1 unit tolerance) every tick while stacked
- Total join_weight on any host never exceeds that state's capacity
- No orphaned relationships after entity removal (both directions)
- All dissolution happens through desire-driven transitions or safety check — no hardcoded trigger paths
- No animal floating above the floor with no valid surface below (STARTLED drop-to-floor invariant)

## 7. Modding

### What modders get for free

**Animals as surfaces:** Add a `state_advertisements` entry with a `stack` join for the relevant states. Animals with matching desires will naturally stack on it. No code, no cleanup triggers to maintain.

**Animals as social attractors:** Add a `state_advertisements` entry with a `nearby` join for states like PLAYING. Animals with social/stimulation desires will come join in. Same config pattern, different spatial behavior.

**Objects as surfaces:** Add a `join` config to an object's JSON (servers, boxes, pillows, custom furniture). Objects that already advertise warmth/comfort get stacking for free.

**New states automatically work.** State transitions replace ads wholesale. If the new state's ads have a join, joiners stay. If not, they leave. A modder adding new states never needs to update a cleanup list.

### Config knobs

| Config | Where | Purpose |
|---|---|---|
| `state_advertisements` | Species JSON | Per-state ads and join config |
| `join.type` | Per state entry | `stack` or `nearby` (required if join present) |
| `join.direction` | Per state entry | `same`, `opposite`, or `any` (required) |
| `join.capacity` | Per state entry / Object JSON | Weight budget for joiners (required) |
| `join.slots` | Per state entry / Object JSON | Offset positions for `stack` type (required for stack) |
| `join.radius_ru` | Per state entry | Proximity radius for `nearby` type (required for nearby) |
| `join_weight` | Species JSON | How much "space" this species takes when joining (required) |
| `distance_sensitivity` | Species JSON | How much distance affects ad scoring (required) |

### No magic defaults

Every config value must be explicitly set. Missing required fields are a validation error at mod load time, not silently defaulted. This is a modding principle for the entire system — if a modder forgets a field, they get a clear error, not mysterious behavior from a default they didn't know about.

### Known limitations (v1)

- Single-layer stacking only (no ferret on cat on dog). The relationship system does not hard-block chains — documented for future expansion.
- Only `stack` and `nearby` join types implemented. `face` (fixed offset facing host) documented for future.
- No per-pair animation overrides. Optional `"animation_override"` field reserved for future use.

## 8. Implementation Estimate

| Area | Lines | Notes |
|---|---|---|
| State ad replacement on state transition | ~12 | Look up new state in config, replace state-sourced ads |
| Position coupling pass (stack joins) | ~12 | Second pass after main movement, with safety check |
| Arrival occupancy check | ~8 | join_weight sum vs capacity |
| Slot assignment bookkeeping | ~8 | Track which slots are occupied per host |
| Direction/sprite flip on join | ~5 | Set joiner facing based on direction config + host facing |
| Save/load (relationship serialization) | ~5 | Add relationships key to payload |
| Social desire scatter | ~15 | New scatter function in tick loop |
| STARTLED drop-to-floor | ~10 | Surface validity check + floor y lookup + position set |
| Config validation at mod load | ~10 | Required fields, join type validation |

**New assets (v1):** 0 sprites, 0 sounds. All composed from existing.
**New config:** Species JSON additions (state_advertisements, join_weight, distance_sensitivity).
