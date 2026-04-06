# Ferret Ring 0 Behavior — Design Spec

**Date:** 2026-04-04
**Goal:** Make ferrets visibly distinct from cats using existing systems. Two behaviors: curiosity patrol (sniffing around racks) and snuggle sleep (sleeping near warm/fuzzy things).

---

## Problem

Ferrets are functionally identical to cats. They cycle between IDLE, SNIFFING, and SPEED_BUMP ambient states but never move purposefully. Their high curiosity_weight (800-900) has no effect because nothing advertises curiosity. The CuriosityTracker class exists but is never instantiated.

## Design Principles

- **No new systems.** Both behaviors work through the existing desire resolver, advertisement scoring, and movement code.
- **No species_filter on ads.** Ads broadcast what they offer; the animal's desire weights determine who cares. Cats with curiosity_weight 100 will naturally ignore curiosity ads. Ferrets with curiosity_weight 900 will prioritize them.
- **Novel things are always more interesting.** The CuriosityTracker's per-ferret visit history means freshly placed objects automatically out-compete familiar racks because they've never been sniffed.
- **Not all things are equally interesting.** A rack is static — a quick sniff and you're done. A cat is always changing — new scents from food, other animals, different places. A fresh pillow pile is a jackpot. Two values on curiosity ads control this: `novelty_duration` (how long the ferret stays interested on arrival) and `novelty_cooldown` (how long before it becomes interesting again after the ferret leaves).

---

## Behavior 1: Curiosity Patrol

### How it works

Curiosity ads go on anything a ferret might want to sniff. Each ad has three values:

| Target | strength | novelty_duration (ticks) | novelty_cooldown (ticks) |
|---|---|---|---|
| Rack | 300 | 30 (3s quick sniff) | 100 (10s before interesting again) |
| Cat | 400 | 150 (15s investigating) | 50 (5s — cats change fast) |
| Pillow pile | 500 | 500 (50s digging around) | 200 (20s to resettle) |

Every animal scores these through normal desire math. Cats mostly ignore them (low curiosity_weight). Ferrets patrol because high curiosity_weight makes curiosity ads their top-scoring option.

Each ferret gets its own CuriosityTracker instance (one Dictionary per ferret, maps entity_id to last_visit_tick). When the desire resolver scores a curiosity ad for a ferret, it checks the tracker. If `current_tick - last_visit_tick < novelty_cooldown`, the score is 0. Otherwise, normal scoring applies.

### Arrival behavior

When a ferret arrives at a curiosity target, it enters SNIFFING state. The SNIFFING duration is set to the ad's `novelty_duration` — 3 seconds for a rack, 15 seconds for a cat, 50 seconds for a pillow pile. The CuriosityTracker records the visit tick. When SNIFFING completes, the ferret returns to AMBIENT, the resolver picks the next unvisited target, and the cycle continues.

### Patrol pattern

At 5 racks with 3s sniff + 10s cooldown, a ferret cycles through all racks in about 30-40 seconds (including travel time). But if there's a cat nearby, the ferret spends 15 seconds investigating it and comes back sooner (5s cooldown). Two ferrets patrol independently — ferret A sniffing rack 2 doesn't affect ferret B's interest in rack 2.

### New objects

When a player places a new object, ferrets prioritize it automatically. The CuriosityTracker has no record of that entity, so it scores at full strength. A pillow pile (strength 500, novelty_duration 500) will massively out-compete a familiar rack (strength 300, recently visited). No special "new object" mechanism needed — novelty falls out of the visit history.

### Interaction with other desires

Curiosity competes with warmth and comfort through normal scoring. A freezing ferret won't sniff racks — warmth deficit * warmth_weight will beat curiosity. A content, warm ferret will patrol constantly. This matches real ferret behavior: they explore when comfortable, huddle when cold.

### Future scaling

At 100+ racks, ferrets won't try to visit all of them. The desire resolver's spatial query (8 RU radius) means ferrets only score nearby racks. They'll patrol their local area, occasionally wandering further when nearby racks are all "cold" in the tracker. This is fine — ferrets having a home range is realistic.

---

## Behavior 2: Snuggle Sleep

### How it works

Cats and soft objects (pillows, clothes piles) get a warmth advertisement: `{desire_type: "warmth", strength: 300, radius_ru: 2}`. Ferrets with unmet warmth desire score these through normal desire math and move toward them.

Cats are warm. Pillows are warm. Ferrets seek warmth. The desire resolver handles the rest.

### Arrival behavior

When a ferret arrives at a warmth source and its warmth desire is satisfied (< 400), the ambient state picker gives it SLEEPING (already works — ferrets can enter SLEEPING when warm). The ferret curls up near the cat or pillow.

### Why this works without special code

The warmth ad on cats means ferrets naturally gravitate toward cat clusters. A group of cats loafing together is a warmth hotspot. The ferret joins the pile. No "sleep near cat" behavior needed — it's just "seek warmth" and cats happen to be warm.

### Capacity

Warmth ads on cats could have capacity 1-2 to prevent all ferrets piling on one cat. Or we leave it uncapped and let pile-ons happen — that's cute and matches the design philosophy. For Ring 0, leave uncapped.

---

## Code Changes

### 1. Implement species_filter check in desire resolver

`desire_resolver.gd` — `score_ad()` currently ignores species_filter. This is a non-change: we decided ads should NOT have species_filter. All ads are scored by all animals; desire weights handle filtering naturally. No code change needed here.

### 2. Add CuriosityTracker per ferret

`game_server.gd` — When spawning ferrets, create a CuriosityTracker instance and store it in a Dictionary keyed by entity_id.

```
var _curiosity_trackers: Dictionary = {}  # entity_id -> CuriosityTracker
```

### 3. Update CuriosityTracker to support per-target cooldowns

`engine/animals/curiosity_tracker.gd` — Currently has a single `NOVELTY_COOLDOWN_TICKS` constant. Change to accept a cooldown parameter per visit:

```
func visit(entity_id: int, current_tick: int) -> void:
    _visit_times[entity_id] = current_tick

func is_novel(entity_id: int, current_tick: int, cooldown_ticks: int) -> bool:
    if not _visit_times.has(entity_id):
        return true
    return current_tick - _visit_times[entity_id] >= cooldown_ticks
```

### 4. Wire CuriosityTracker into desire resolver

`desire_resolver.gd` — Accept an optional CuriosityTracker when scoring. If present and the ad's desire_type is "curiosity", check `tracker.is_novel(ad_entity_id, current_tick, ad.novelty_cooldown)`. If not novel, return score 0.

The resolver needs access to the trackers. Options:
- Pass the tracker Dictionary to `evaluate_budget()` — simplest, keeps resolver stateless
- Store trackers on the resolver — tighter coupling but fewer arguments

**Decision:** Pass tracker Dictionary to evaluate_budget(). The resolver remains a pure scoring function.

### 5. Add curiosity ads to rack entities

`game_server.gd` — Racks are not currently entities. Create one lightweight entity per rack with position (centered on rack floor) + advertisements components. These are static — created once at startup, never destroyed.

```
{desire_type: "curiosity", strength: 300, radius_ru: 8, novelty_duration: 30, novelty_cooldown: 100}
```

### 6. Add curiosity + warmth ads to cat entities

`game_server.gd` — When spawning cats, add to their advertisements component:

```
[
  {desire_type: "warmth", strength: 300, radius_ru: 2},
  {desire_type: "curiosity", strength: 400, radius_ru: 3, novelty_duration: 150, novelty_cooldown: 50}
]
```

Cats are both warm (ferrets sleep near them) and interesting (ferrets investigate them). Pillows/clothes piles get similar ads when implemented.

### 7. Record visits and set SNIFFING duration on arrival

`game_server.gd` — In `_move_animals()`, when a ferret arrives at its target:
- Check if the target had a curiosity ad
- If so, record the visit in the ferret's CuriosityTracker via `tracker.visit(target_entity_id, current_tick)`
- Enter SNIFFING state with min_duration set to the ad's `novelty_duration` (overriding the default 10s)

### 8. Enter SNIFFING on curiosity arrival, SLEEPING on warmth arrival

`game_server.gd` — When a ferret arrives at a target, check what desire drove the movement. If curiosity → SNIFFING (with duration from ad). If warmth → let the ambient state picker handle it (ferret is now warm, will naturally pick SLEEPING).

---

## What We're NOT Doing (Ring 1+)

- Hoarding/stashing objects
- WAR_DANCE, DEAD_SLEEP energy states
- Box discovery sequences / proximity events
- Species-filtered advertisements
- Full ambient_behavior.jsonc-driven system
- Ferret climbing / vertical movement
- CuriosityTracker cell-level granularity (we use rack-level for Ring 0)

---

## Testing

- **Unit:** CuriosityTracker.is_novel() returns true for unvisited entity
- **Unit:** CuriosityTracker.is_novel() returns false within cooldown period
- **Unit:** CuriosityTracker.is_novel() returns true after cooldown expires
- **Unit:** Different cooldown values per target (rack 100 ticks, cat 50 ticks)
- **Unit:** Desire resolver scores curiosity ad at 0 for recently-visited target
- **Unit:** Desire resolver scores curiosity ad normally for unvisited target
- **Scenario:** Ferret with high curiosity_weight moves toward rack with curiosity ad
- **Scenario:** Ferret enters SNIFFING on arrival at curiosity target
- **Scenario:** SNIFFING duration matches ad's novelty_duration (3s for rack, 15s for cat)
- **Scenario:** Ferret does not re-visit same rack within cooldown period
- **Scenario:** Ferret prefers unvisited rack over recently-visited rack
- **Scenario:** Ferret prefers new object (never visited) over familiar rack
- **Scenario:** Ferret moves to cat with warmth ad when cold
- **Scenario:** Cat with low curiosity_weight ignores curiosity ads (scores below warmth/comfort)
- **Soak:** No ferret gets stuck — visits multiple racks over 1000 ticks
- **Soak:** Ferret visits all 5 racks within 200 ticks (patrol coverage)
