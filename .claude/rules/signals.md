# TCP Signal Architecture

TCP uses three communication patterns. Each has one job. See `signals-detail.md` (path-gated to `engine/**` + `nodes/**`) for worked code examples; invoke `/trace-signal-flow` for end-to-end signal traces.

## The three patterns

1. **Direct signal — parent-child / scene siblings.** The parent that owns both nodes connects them in `_ready()`. Use when emitter and listener are in the same `.tscn` scene.
2. **Event bus — cross-system broadcast.** Emitter calls `Events.<signal>.emit()`. Listeners self-subscribe to `Events` in their own `_ready()`. Use when the emitter shouldn't know its listeners.
3. **Manager mediation — orchestrated sequence with ordering.** Manager listens for a trigger, makes direct method calls in order, broadcasts the result on the event bus. Use when later steps depend on earlier results.

## Decision flowchart

When A needs to talk to B:

1. Same `.tscn` scene? → direct signal, parent wires children.
2. A needs B's result, or there's ordering? → manager.
3. Broadcast to zero-or-many unknown listeners? → event bus.

If none fit, the system boundary is probably wrong.

## Ownership rule

The node that creates a relationship owns it.

- **Scene-internal:** scene root wires children. No `../` reaches.
- **Cross-system:** each system connects itself to `Events` in `_ready()`. The bus is the only sanctioned self-wire — no parent owns both emitter and listener.
- **Manager:** manager wires its mediees in its own `_ready()` (sibling lookup or `@export NodePath`).

## GameServer siblings

Siblings under GameServer read each other's state directly during tick. No signals needed for tick-synchronous reads inside the server. Cross-boundary (HUD, Sound) goes through the event bus.

## UI listening

The HUD subscribes directly to `Events`. No ViewModel, no UI dispatcher. The HUD never holds references to GameServer children — `Events` is the client/server membrane.

## Signal naming

Past tense. Always.

- `noun_verbed` or `noun_verb_past_participle`: `state_changed`, `food_dispensed`, `animal_relocated`.
- Include the ID of the thing that changed. Include old + new when delta matters.
- Slot naming: `_on_<emitter>_<signal_name>` (direct) or `_on_<noun>_<signal_name>` (event bus).
- WRONG: `animal_moving` (present tense, ambiguous), `move_animal` (imperative — signals are notifications, not commands).

## Emit / listen, not produce / consume

Name signals by what they *are* (`purr`, `heat_cell_changed`), never by what consumes them (`hum_producer`, `power_source`). Producer/consumer phrasing couples the emitter to a single downstream — removing HUM tomorrow would mean touching cats. "Cats emit on `purr`; HUM receivers listen on `purr`" lets any number of independent readers (HUM battery, ferret-calm, sound mixer, narrator) consume the channel without modifying each other or the emitter.

Don't generalize across physics — purr is acoustic, solar is electrical, heat is thermal. Each gets its own channel and own receiver. Rationale and concrete rules in `signals-detail.md`.

## One event bus

One `Events` autoload, all signals in one file. Split into `Events` + `UIEvents` only past 50 signals.

## Summary

1. Same scene? Direct signal, parent wires.
2. Broadcast to unknowns? Event bus.
3. Multi-step ordering? Manager.
4. GameServer siblings read each other directly.
5. HUD only touches `Events`.
6. Signals are past tense.
7. No `../` paths. No god-object wiring.
8. One event bus.
