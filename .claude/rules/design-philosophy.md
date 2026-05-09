---
paths:
  - "engine/**"
  - "nodes/**"
---

# TCP Design Philosophy Rules

> **Use `/load-game-designer`** when about to make a design decision affecting systems, feedback loops, player motivation, or coherence with TCP's vision — and you want Mochi's principles in front of you first.
> **Spawn the `game-designer` agent** when you have a mechanic or system design to review against TCP's abundance/emergence philosophy and elegance principle.

These rules apply to ALL code written for TCP.

## Pure Core Pattern
All game logic lives in `RefCounted` or `Resource`, never `Node`. Nodes are thin wrappers that delegate to core objects. Test: if you can't unit-test without a scene tree, it's in the wrong place.

## Base Game Is a Mod
The engine is a framework; `tcp_base` is a mod. If something can't be done via the mod API, the framework needs work — not a special case. This is a day-one hard constraint like networking — not aspirational, not "we'll add it later." The mod loading pipeline, config merging, and namespaced IDs must work before any game content exists.

## Redux-Style Central State
All mutable game state in `GameStateDB`. Commands mutate (return void). Queries read (never null). State flows: Intent -> Command -> GameStateDB -> Event Bus -> Nodes React. Nodes never hold authoritative state.

## Batch-First API
The primary GameStateDB operations are "given a component, apply this to all matching entities" — not entity-by-entity access. Column-oriented storage for hot components (PackedInt32Array) behind a row-oriented single-entity view for AI scoring. Single-entity access exists but is not the default path.

## Integers Over Floats
Use integers for game values (0-1000 for 0.0-1.0). Floats only at rendering boundary (positions, audio, shaders, Vector2/Vector3). No float drift over ticks.

## Null Is the Enemy
Validate at system boundaries. Once past validation, data is trusted. Never accept/return null. Model absence explicitly: `NullDesireSource`, empty arrays, sentinel IDs (`INVALID_ID`).

## Explode Early
Invalid state crashes in debug, not propagates silently. Assert is a contract, not error handling. Production: log + skip.

## Deterministic Simulation
Same seed + same commands = identical output. Integer math, fixed tick rate, seeded RNG, deterministic iteration order.

## Config Is Not Code
Every tunable number in JSON. Only structural numbers in code (0, 1, -1, INVALID_ID, array indices, loop bounds).

## Change Detection
GameStateDB tracks which tick each component was last modified. `set_field` and `set_component` skip the write and notification if data is identical. Systems query `was_changed(entity_id, component, since_tick)` or `get_changed_entities(component, since_tick)` to react only to real mutations. This eliminates watcher noise at scale (1000 animals with desire decay every tick = 1000 no-op callbacks without this).

## Spawn Templates
Spawning an entity uses species JSON to auto-populate all required components. `spawn_from_template(species_id, overrides)` reads the species definition, creates the entity, deep-merges overrides. No manual component assembly. Every animal is guaranteed to have desires, personality, position, behavior — the template defines the *shape*, personality randomization provides the *values*.

## Lifecycle Hooks
GameStateDB fires callbacks on component lifecycle events — not just value changes. Three hooks beyond the existing watcher:
- **on_add**: component added to entity for the first time (spatial hash insertion, teaching system registration)
- **on_remove**: component removed from entity (spatial hash eviction, advertisement withdrawal)
- **on_despawn**: entity destroyed (relationship cleanup, nav graph removal, proximity cooldown purge)

Hooks are batched to end-of-tick like watchers. They do not execute synchronously during the mutation.

## Entity Relationships
GameStateDB maintains a relationship table for entity-to-entity connections: teaching lineages, social bonds, infrastructure links. Lightweight bidirectional lookup — forward (`get_targets`) and reverse (`get_sources`). Relationships auto-clean on entity despawn via lifecycle hooks. Relationship types are defined in config, not code.

---

## Game Design Principles

These complement the engineering rules above. They govern *what* the game does, not *how* the engine works.

- **Five needs, no more, ever.** Hunger, Rest, Social, Comfort, Curiosity. Personality modifies the curves and weights — not the list of needs. Adding a sixth need is a load-bearing design change, not a feature addition.
- **Inter-species dependency is the progression engine.** Each species recipe unlocks capabilities other recipes need. This is the "why would I leave Phase 1?" answer — new species enable higher happiness ceilings that single-species setups can't reach.
- **Cozy lives and dies by rhythm.** Every system gets evaluated at three timescales: 1 minute (moment-to-moment feedback loop), 1 hour (session arc), 1 week (long-term progression). A mechanic that feels right at one scale and wrong at another isn't shippable.
- **Sound is a game mechanic, not a polish layer.** Purr-as-IOPS is a load-bearing system, not decoration. Every system should have an audio signature that conveys state without requiring the player to look at it. (Mechanics in `sound-design.md`.)

---

The full GameStateDB API reference (method signatures, hot-path call frequency, column-storage internals) lives in `game-state-db.md`, path-gated narrowly to `engine/core/game_state_db*` so it only loads when working on the DB itself.
