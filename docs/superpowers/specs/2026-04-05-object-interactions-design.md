# Object Interactions & Robot Arm — Design Spec

**Date:** 2026-04-05
**Status:** Draft (dev team reviewed, pending user review)
**Depends on:** Ring 0 prototype (shipped), grid constants (done), ambient behaviors (done), desire model flip (done)

---

## 1. Scope & Success Criteria

### What we're building

The core gameplay loop: ferrets press a button that drops tuna cans, the robot arm opens them, cats eat the opened tuna. Plus box degradation from ferret shredding. These two interaction chains complete the Phase A prototype's "11 dynamics from 8 objects and 2 species" goal (partially — remaining dynamics deferred).

### Success criterion

A playtester watches a ferret press the button, sees a can drop, watches the arm open it, and sees a cat walk over to eat. The playtester says: "The ferret didn't *mean* to feed the cat." That's the emergent cooperation story.

### In scope

- PERFORMING state for animals executing timed actions on objects
- Robot arm as a desire-driven entity (wants "purpose", satisfied by work)
- Button entity (curiosity ad for ferrets, spawns cans on press)
- Tuna can state transitions: sealed → open → empty
- Object state component with HP for degradable objects
- Box degradation: new → worn → scraps (ferret shredding)
- Food desire for cats (new, fourth desire)
- Arm scanning nearby animals (advertise `scannable`)
- Stats bar update (add food bar)

### Out of scope

- Feather + fan, furballs, furball lifecycle
- Play/stimulation desire
- Ferret dragging objects
- Discovery event sequences (first-time reactions)
- Robot narrator text
- Pouncing, burrowing
- Kitten laser-chase behavior (future — needs kittens first)
- Cooling pipes, condensation

---

## 2. New Desire: Food

Added to all cats. Same model as warmth/comfort/curiosity:
- 0 = starving, 1000 = full
- Decays by -2 per tick (~50s to deplete — leisurely, not frantic, per abundance philosophy)
- Satisfied by eating opened tuna cans (+500 per eat action)
- Ferrets don't have food desire in prototype (they eat offscreen, per spec)

Initial spawn value: 800 (cats start fed).

### Personality weight

Cats get `food_weight` in their personality component. Default ~700 (food is important but not dominant when satisfied).

---

## 3. Object State System

Objects gain an `object_state` component:

```
{
  "current": "sealed",     # current state name
  "hp": 1000,              # for degradable objects, -1 if not degradable
  "max_hp": 1000
}
```

Each state defines its own advertisement profile. When an object transitions state, its `advertisements` component is swapped to the new state's ad list and its sprite updates.

### Tuna can states

| State | Ads | Sprite | Transition trigger |
|---|---|---|---|
| `sealed` | `openable` strength 800, radius 3 | tuna_can_sealed | Arm completes "open" action |
| `open` | `food` strength 800, radius 5 | tuna_can_open | Cat completes "eat" action |
| `empty` | none | despawn after 3 seconds | — |

### Cardboard box states

| State | HP Range | Ads | Sprite | Transition trigger |
|---|---|---|---|---|
| `new` | 1000-501 | comfort 700 r4, curiosity 500 r5 | box_cardboard_new | HP drops below 500 |
| `worn` | 500-1 | comfort 400 r3, curiosity 300 r4 | box_cardboard_new (modulate dimmer) | HP reaches 0 |
| `scraps` | — | comfort 600 r3 (nesting) | bedding_scraps | permanent |

---

## 4. PERFORMING State

New goal-directed state added to the state machine. An animal enters PERFORMING after arriving at a target whose ad specifies an action.

### Flow

1. Desire resolver picks best ad (existing flow)
2. Animal enters SEEKING → MOVING_TO → arrives at target
3. On arrival, check ad for `action` field
4. If action exists: enter PERFORMING with a timer equal to `action_duration`
5. While PERFORMING: animal stays in place, plays action-specific animation
6. On completion: execute the action's effect (state transition, HP change, desire satisfaction, entity spawn)
7. Return to AMBIENT/IDLE with commitment reset to 0

### Action definitions

Actions are defined in the advertisement config, not in code. The ad gains two optional fields:

```
{
  "desire_type": "openable",
  "strength": 800,
  "radius_ru": 3,
  "action": "open",           # what to do on arrival
  "action_duration": 30       # ticks (3 seconds at 10Hz)
}
```

### Action effects (hardcoded for prototype)

| Action | Duration | Actor | Effect |
|---|---|---|---|
| `press` | 1.0s | Ferret | Spawn sealed tuna can at drop point. Startle the ferret. |
| `open` | 3.0s | Arm | Target can transitions sealed → open. Arm purpose +500. |
| `eat` | 5.0s | Cat | Target can transitions open → empty. Cat food +500. |
| `shred` | 2.0s | Ferret | Target box HP -200. Ferret curiosity +300. |
| `scan` | 2.0s | Arm | Arm purpose +200. No effect on target. |

Action durations are in seconds (float), matching the existing `_state_timers` system. Action effects are a match/case in game_server for prototype. Generalizing to config-driven effects is deferred.

### Arrival validation

On arrival at a target, the animal must verify:
1. Target entity still exists (`db.has_entity`)
2. Target still has the expected object_state (e.g., can is still `sealed`, not already `open`)

If validation fails, the animal falls back to IDLE with commitment reset to 0. This prevents two cats eating the same can or an arm opening an already-opened can.

### Food ads: scoring only, not passive scatter

Food advertisements drive target selection via the desire resolver but do NOT passively satisfy food through `_scatter_from_ads`. A cat must complete the "eat" action to gain food satisfaction. The `_scatter_from_ads` function skips ads with `desire_type == &"food"` (and `&"openable"` and `&"scannable"`). This prevents cats from getting fed just by standing near an open can.

### PERFORMING state label

During PERFORMING, the state label shows the action name (e.g., "eating", "opening", "pressing") instead of just "performing". This is the minimum visual feedback for accessibility — a player can see what the animal is doing without audio.

### Animation mapping

| Action | Cat animation | Ferret animation | Arm animation |
|---|---|---|---|
| `eat` | crouch | — | — |
| `press` | — | sneak | — |
| `open` | — | — | idle (placeholder) |
| `shred` | — | sneak | — |
| `scan` | — | — | idle (placeholder) |

---

## 5. Robot Arm Entity

The arm is an entity with desires, like animals, but it cannot move.

### Components

- `species`: `{ "id": "tcp_base:robot_arm", "name": "ARM-01" }`
- `position`: fixed on floor, near rack 3-4
- `desires`: `{ "purpose": 800 }`
- `personality`: `{ "openable_weight": 900, "scannable_weight": 500 }`
- `ai_state`: same state machine as animals
- `advertisements`: `{ "list": [{ "desire_type": "scannable", "strength": 300, "radius_ru": 4 }] }`

The arm advertises `scannable` — nearby animals are things it wants to scan. The arm also *scores* `openable` ads from sealed cans. This bidirectional relationship emerges naturally from the existing ad system.

### Key difference: no movement

When the desire resolver picks a target for the arm, instead of entering SEEKING → MOVING_TO, the arm checks if the target is within its `reach_radius` (3 RU). If yes: go directly to PERFORMING. If no: skip (can't reach, stays AMBIENT).

This is the only special-case code for the arm. Everything else uses the existing pipeline.

### Ambient behavior

The arm uses the same universal ambient state pool. At rest it cycles through IDLE (retracted) and STARING (scanning). Its animations are arm-specific but map to the same state names.

### Purpose decay

Purpose decays at -6 per tick. Opening a can gives +500. Scanning gives +200. An idle arm gradually gets restless. Multiple sealed cans in reach = the arm is busy and purposeful.

---

## 6. Button Entity

A fixed object on the floor next to the robot arm.

### Components

- `position`: fixed, adjacent to arm station
- `object_type`: `{ "type": "dispenser_button" }`
- `advertisements`: curiosity for ferrets (strength 600, radius 6)
- Ad includes: `"action": "press"`, `"action_duration": 10`, `"novelty_cooldown": 200`

The novelty cooldown prevents button-mashing. After pressing, the ferret's CuriosityTracker marks the button as visited. The ferret wanders off and does other things. Eventually the cooldown expires, the button looks interesting again.

### Press effect

1. Spawn a sealed tuna can entity at a predefined drop point (within arm reach)
2. Transition the pressing ferret to STARTLED (the can drop startles it)
3. The ferret's startled recovery sends it dashing away — the comedy beat

### Can supply

Cans are infinite (abundance design). Every button press spawns one. Empty cans despawn after 3 seconds. No resource management, no scarcity.

---

## 7. Entity Summary

| Entity | Position | Desires | Ads it broadcasts | Ads it scores | Actions it performs |
|---|---|---|---|---|---|
| Cat | Mobile | warmth, comfort, curiosity, **food** | warmth (body heat), curiosity | warmth, comfort, curiosity, **food** | eat |
| Ferret | Mobile | warmth, comfort, curiosity | warmth (body heat), curiosity | warmth, comfort, curiosity | press, shred |
| Robot arm | Fixed | **purpose** | **scannable** | **openable, scannable** | open, scan |
| Button | Fixed | — | curiosity | — | — (acted upon) |
| Tuna can | Spawned | — | openable (sealed), food (open) | — | — (acted upon) |
| Cardboard box | Placed | — | comfort, curiosity | — | — (acted upon) |
| Clothes pile | Placed | — | comfort, warmth, curiosity | — | — |
| Server | Placed | — | warmth | — | — |

---

## 8. Changes to Existing Systems

### game_server.gd

- Add food desire decay in `_scatter_desires`: `db.add_all(&"desires", &"food", -2)`
- Add `_execute_action()` function called when PERFORMING timer completes
- Modify arrival logic: check for action field in ad, enter PERFORMING if present
- Add arm reach check: if entity is robot_arm species, skip SEEKING/MOVING_TO, go straight to PERFORMING if target in range

### desire_resolver.gd

- No changes needed — the scoring math already handles any desire type via personality weight keys

### animal_node.gd

- Add PERFORMING to animation map (uses action-specific anim or fallback)
- Load arm sprites when species is robot_arm

### animal_stats_bar.gd

- Add food bar (gold/amber) for cats
- Add purpose bar for robot arm
- Handle entities without certain desires gracefully (ferrets have no food, arm has no warmth)

### game_client.gd

- Spawn robot arm, button, and initial tuna can entities
- Handle object state sprite updates (subscribe to state transitions)
- Handle can despawn (remove sprite on empty timeout)

### constants.gd

- No changes needed

---

## 9. Testing Strategy

### Unit tests

- `test_object_state_transition`: sealed → open → empty state changes
- `test_box_degradation`: HP reduction through shred actions, state transitions at thresholds
- `test_arm_scores_openable`: arm with purpose desire scores sealed can ad
- `test_arm_skips_unreachable`: arm ignores sealed can beyond reach radius
- `test_food_desire_scoring`: hungry cat scores food ad, full cat ignores it
- `test_press_spawns_can`: button press action creates new tuna can entity

### Integration tests

- `test_performing_state_flow`: animal arrives at target with action → enters PERFORMING → completes → effect fires
- `test_arm_opens_can_in_reach`: arm + sealed can within reach → arm performs open → can transitions to open

### Scenario tests

- `test_tuna_chain`: button press → can spawns → arm opens → cat eats. Full chain in ~200 ticks. Assert intermediate states.
- `test_box_degrades_to_scraps`: ferret shreds box over multiple visits → box transitions through states
- `test_ferret_startled_after_press`: ferret presses button → enters STARTLED after can drops

### Edge case tests (from dev team review)

- `test_two_cats_target_same_can`: only one eats, other falls back to IDLE on arrival validation
- `test_target_despawned_during_move`: animal MOVING_TO a can that gets eaten by another → IDLE on arrival
- `test_arm_target_removed_during_performing`: player removes can mid-action → arm aborts to IDLE
- `test_can_spawns_within_arm_reach`: verify drop point is always within arm reach radius
- `test_no_cans_available_cats_wander`: all cans eaten + button on cooldown → cats wander, no stuck state
- `test_food_not_scattered_passively`: cat near open can without eating does NOT gain food satisfaction

---

## 10. Art & Sound Assets Needed

### Art (tracked in docs/art-asset-tracker.md)

- Robot arm sprite (placeholder static) — 32x40
- Button sprite — 16x12
- Arm "reaching" animation (placeholder: static sprite swap)

### Sound (tracked in docs/sound-asset-tracker.md)

- Can drop / clang (one-shot, 0.3s)
- Arm servo whir (one-shot, 1-2s)
- Can open chunk (one-shot, 0.5s)
- Cat eating (one-shot, 1-2s)
- Button press click (one-shot, 0.2s)
- Box shred / rip (one-shot, 0.5s)
