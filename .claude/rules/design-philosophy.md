---
paths:
  - "engine/**"
  - "nodes/**"
---

# TCP Design Philosophy Rules

> **Use `/load-game-designer`** when about to make a design decision affecting systems, feedback loops, player motivation, or coherence with TCP's vision — and you want Mochi's principles in front of you first.
> **Spawn the `game-designer` agent** when you have a mechanic or system design to review against TCP's abundance/emergence philosophy and elegance principle.

> **Use `/load-game-programmer`** when about to make an architecture choice, refactor decision, or "what belongs in pure core" call — and you want Bramble's full TCP code-architecture context in front of you first.
> **Spawn the `game-programmer` agent** when you have GDScript code or an architecture decision to review for tick scheduling, signals, save/networking, and pure-core/integer/null-free adherence.

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

## Game Design Principles (Mochi)

These complement the engineering rules above. They govern *what* the game does, not *how* the engine works.

1. **Abundance, not scarcity.** Never design a mechanic around "running out of" something. If a resource exists, it exists to enable, not to constrain. The challenge is optimization, not survival.
2. **The Gnorp Question.** For every system, ask: "What's the theoretical maximum here, and why is it hard to reach?" The fun is in the asymptotic pursuit, not the binary pass/fail.
3. **Desire-driven, not script-driven.** Animals have desires (Maslow base + individual traits). Interesting behavior emerges from desire + environment + proximity. Resist the urge to script specific interactions. Start with exactly 5 needs (Hunger, Rest, Social, Comfort, Curiosity) — enough for interesting tradeoffs, few enough to understand. Personality modifies the *curves*, not the *needs*.
4. **Inter-species dependency is the progression engine.** Each species unlocks capabilities that other species need. This creates the "why would I leave Phase 1?" answer — you leave because new species enable higher happiness ceilings that single-species setups can't reach.
5. **Nothing is cosmetic.** Every placeable element should have a mechanical purpose, even if that purpose is discovered through emergence rather than designed explicitly.
6. **The robot's misunderstanding is the UI.** The player sees cute animals; the stats and HUD interpret everything through datacenter metrics. This gap is both the comedy and the information design.
7. **Cozy lives and dies by rhythm.** Every system gets evaluated at three timescales: 1 minute (moment-to-moment feedback loop), 1 hour (session arc), 1 week (long-term progression). A mechanic that feels right at one scale and wrong at another isn't shippable.
8. **Sound is a game mechanic, not a polish layer.** Purr-as-IOPS is a load-bearing system, not decoration. Every system should have an audio signature that conveys state without requiring the player to look at it. (Mechanics in `sound-design.md`.)

## Technical Principles (Bramble)

Cross-cutting engineering principles. Some overlap with the engineering rules above or with path-gated rules (`code-style.md`, `tick-architecture.md`, `scene-tree.md`, `networking.md`, etc.); they are reproduced here as Bramble's working set.

1. **Simplest first, architecture second.** The first playable should prove the *feel* — a cat walking to a warm spot, settling down, purring. That doesn't need ECS or spatial hashing. But the architecture MUST support TCP's targets (thousands of animals, multiplayer, emergence) without a rewrite. This means: clean interfaces from day one that start with simple implementations (arrays, linear search) and can swap in optimized backends (ECS, spatial hashing) when scale demands it. Design for the target, implement for the prototype.
2. **Utility AI with object-advertisement.** Use Dave Mark's IAUS (Infinite Axis Utility System): objects *advertise* what they can satisfy (a warm spot advertises "warmth +0.8"), and animals score advertisements against their current desire weights. This inverts the lookup — instead of each animal scanning all objects, objects broadcast and animals filter. Start with 5 needs max (Hunger, Rest, Social, Comfort, Curiosity). Personality is curve modifiers on the scoring functions, not a separate system. Animals should commit to chosen actions with hysteresis (don't switch until score delta > threshold) to prevent flickering.
3. **Animal memory creates narrative.** Each animal maintains 5-10 memory slots recording recent experiences ("ate tuna at rack 3," "played with ferret near tube junction"). Memory decays over time. Animals prefer locations and objects associated with positive memories, creating habits and "favorite spots" that players notice. This is where Steve Grand's *Creatures* insight applies — simple memory + association = believable individuals.
4. **Teaching as imperfect imitation.** When an animal with skill X performs an action near an animal without it, the observer has a probability of learning a degraded version (skill * 0.7). This requires proximity detection (spatial hash), a teaching cooldown, and a cap on chain depth to prevent unbounded propagation. Circuit breaker: max 3 generations of teaching per skill.
5. **Config is not code.** Per CLAUDE.md fundamentals: every formula number in JSON. But this means the config schema IS the API contract. Schema changes need migration paths. Config validation happens at load time, not at use time.
6. **Network from frame zero.** Even solo play should run through a local server. This means: authoritative game state lives on the server, the client sends intents ("place box at rack 1, unit 3"), the server validates and applies, and the client renders the authoritative state. This architecture is harder initially but prevents a "networking retrofit" disaster later.
7. **Simulation LOD.** Use datacenter rooms as natural spatial cells. At 1000 animals, you can't run full AI for all of them every frame. Nearby animals get full simulation (every tick). Mid-range animals get reduced simulation (every 5th tick). Distant animals get statistical approximation (update once per second based on probability). The player should never notice the difference.
8. **AI feel > AI speed.** The hardest part of utility AI isn't performance — it's making animals feel *alive*. Animals should deliberate (brief pause before choosing), commit (don't switch actions when scores change by 0.01), and have visible intent (walking toward a goal, not teleporting). The animation layer between AI decisions and visible behavior is where believability lives. Budget time for tuning AI *feel*, not just AI *correctness*.
9. **Two clocks, one truth.** Simulation ticks at 10Hz in `_physics_process` (set `Engine.physics_ticks_per_second = 10`). Rendering interpolates in `_process` using `Engine.get_physics_interpolation_fraction()`. GameStateDB is the single truth between them. Never put game logic in `_process`. Never put rendering in `_physics_process`.
10. **Nodes render, core decides.** Every node `_physics_process` and `_process` method should be <=10 lines, delegating to a RefCounted core object. Nodes legitimately handle: rendering, input capture, collision shape management (Area2D), audio playback, and scene tree lifecycle. These feed data INTO core objects but don't hold authoritative state.
11. **Typed arrays and StringName in hot paths.** `Array[int]` not `Array`. Dictionary keys are `StringName` (via `&"literal"`) not `String` in frequently-accessed stores like GameStateDB. GDScript typed arrays are 2-4x faster.
12. **Pool the visual, free the logical.** Node wrappers for animals are pooled (expensive to create/destroy). RefCounted core objects are created/freed directly (cheap). Always `queue_free()`, never `free()`.
13. **Boundaries convert, interiors trust.** Integer-to-float conversion happens at the node boundary. Inside core: all int. Inside node rendering: all float. Never mix in the same function.
14. **Preload base, async-load mods.** Base game assets use `preload()`. Mod assets use `ResourceLoader.load_threaded_request()`. Never `load()` during gameplay ticks.
15. **GDExtension escape hatch.** GDScript Dictionary performance at 1000+ entities with per-tick queries may bottleneck. Design GameStateDB's interface so the implementation can be swapped to a GDExtension (C++) without changing callers. Profile early, profile often.

---

The full GameStateDB API reference (method signatures, hot-path call frequency, column-storage internals) lives in `game-state-db.md`, path-gated narrowly to `engine/core/game_state_db*` so it only loads when working on the DB itself.
