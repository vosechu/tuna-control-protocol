# TCP Signal Architecture

This is the definitive reference for how systems communicate in TCP. One pattern per situation, no alternatives, no "it depends." Follow this or explain in a PR comment why it is wrong.

## The Three Patterns and When to Use Each

TCP uses exactly three communication patterns. Each has one job.

**Pattern 1 — Direct signals: parent-child and tight siblings.**
Use when the emitter and listener are in the same scene and have a structural relationship (parent/child, or siblings under the same parent). The connection is made by the parent that owns both nodes.

```gdscript
# AnimalAgent.gd — emits when the state machine transitions
signal state_changed(old_state: StringName, new_state: StringName)
signal desire_updated(desire_type: StringName, old_value: float, new_value: float)

# AnimalRoot.gd — the CharacterBody2D scene root wires its own children
func _ready() -> void:
    $AnimalAgent.state_changed.connect(_on_agent_state_changed)
    $AnimalAgent.desire_updated.connect(_on_agent_desire_updated)

func _on_agent_state_changed(old_state: StringName, new_state: StringName) -> void:
    $Sprite.play(new_state)
    $SoundEmitter.play_transition(old_state, new_state)
```

**Why:** The parent scene created these children. It knows they exist. It is responsible for their lifecycle. This is the tightest, most debuggable connection type. If you are connecting nodes inside the same `.tscn` file, this is always correct.

**Pattern 2 — Event bus: cross-system broadcasts.**
Use when the emitter does not know (and should not know) who is listening, AND multiple unrelated systems need to react. The event bus is a single autoload singleton called `Events`.

```gdscript
# events.gd — autoload singleton, registered in Project > AutoLoad as "Events"
extends Node

# Simulation events (emitted by server-side systems)
signal heat_cell_changed(cell_id: int, old_temp: float, new_temp: float)
signal object_placed(object_id: int, rack: int, slot: int, object_type: StringName)
signal object_removed(object_id: int, rack: int, slot: int)
signal hum_reserve_changed(hum_id: int, old_reserve: int, new_reserve: int)
signal hum_brownout_entered(hum_id: int)
signal hum_brownout_recovered(hum_id: int)

# Animal events (emitted by AnimalRegistry or individual AnimalAgents)
signal animal_state_changed(animal_id: int, old_state: StringName, new_state: StringName)
signal animal_relocated(animal_id: int, from_pos: Vector2, to_pos: Vector2)
signal animal_desire_critical(animal_id: int, desire_type: StringName, value: float)
signal animal_arrived(animal_id: int, species: StringName)

# Interaction events (emitted by ProximityEventManager)
signal proximity_event_triggered(event_type: StringName, actor_id: int, target_id: int)
signal ferret_drag_started(ferret_id: int, object_id: int)
signal ferret_drag_completed(ferret_id: int, object_id: int, position: Vector2)
signal robot_arm_activated(trigger_object_id: int, trigger_actor_id: int)
signal robot_arm_action_completed(action_type: StringName, target_id: int)

# Infrastructure events
signal server_powered_on(object_id: int, rack: int, slot: int)
signal server_powered_off(object_id: int, rack: int, slot: int)
signal power_state_changed(rack: int, slot: int, powered: bool)
```

**Why:** HeatGrid should not import AnimalAgent. The HUD should not import HeatGrid. The SoundManager should not import AnimalAgent. These are separate systems that react to the same facts. The event bus is the postal service — it delivers without requiring the sender to know the recipient's address.

**Pattern 3 — Manager mediation: orchestrated multi-step sequences.**
Use when an event triggers a chain of operations that must happen in a specific order, where later steps depend on earlier results. The manager owns the sequence. It listens to a trigger (often from the event bus) and then calls methods directly on the systems it coordinates.

```gdscript
# ProximityEventManager.gd — orchestrates discovery events
# This is NOT a signal relay. It makes decisions and enforces ordering.

func _on_activation_zone_body_entered(body: Node2D) -> void:
    if not body is PlacedObject: return
    var obj := body as PlacedObject
    if obj.object_type != &"tuna_can": return
    if _arm_busy: return
    if not _cooldown_expired(&"robot_arm_activate"): return

    # Step 1: Lock the arm (prevents concurrent activations)
    _arm_busy = true

    # Step 2: Tell the arm to do its thing (direct method call, not signal)
    robot_arm.start_action(&"open_can", obj)

    # Step 3: Broadcast that this happened (event bus for everyone else)
    Events.robot_arm_activated.emit(obj.get_instance_id(), _get_nearest_animal_id(obj))

    # Step 4: Wait for arm completion (the arm calls us back via direct signal)
    # robot_arm.action_completed is connected in _ready()

func _on_arm_action_completed(action_type: StringName, target: PlacedObject) -> void:
    _arm_busy = false
    _reset_cooldown(&"robot_arm_activate")

    if action_type == &"open_can":
        # Transform the object (direct call — we own this decision)
        target.convert_to(&"open_tuna_can")
        # Broadcast result (event bus — anyone who cares can react)
        Events.robot_arm_action_completed.emit(action_type, target.get_instance_id())
```

**Why:** Some operations are not fire-and-forget broadcasts. They have preconditions, ordering requirements, and state to manage. A signal chain cannot enforce "check cooldown, then lock arm, then start animation, then wait, then transform object." That is control flow, and control flow belongs in a function, not a signal graph.

## Decision Flowchart

When you need A to talk to B, ask these questions in order:

1. **Are A and B in the same `.tscn` scene?** Use direct signals. The scene root wires them in `_ready()`.
2. **Does A need to know the result of B's reaction?** Use a manager. The manager calls B directly and handles the result.
3. **Is this a broadcast that zero or many systems might care about?** Use the event bus.

If you find yourself writing code that does not fit any of these three, stop and reconsider the system boundary. You are probably mixing responsibilities.

## Who Wires What — The Ownership Rule

**One rule: the node that creates a relationship owns that relationship.**

- **Scene-internal wiring:** The scene root connects its children in `_ready()`. Children never call `get_parent()` or `get_node("../../SomeDistantCousin")` to wire themselves. If you are typing `../` you are doing it wrong.
- **Cross-system wiring (event bus):** Each system connects itself to `Events` in its own `_ready()`. This is the ONE exception to "don't wire yourself" — because the event bus is a global singleton, there is no parent that owns both the emitter and the listener.
- **Manager wiring:** The manager connects to whatever it mediates in its own `_ready()`. It finds its dependencies through the scene tree (it is a child of GameServer and can access siblings via `get_parent().get_node()`), or receives them as exported NodePaths set in the editor.

## Anti-Patterns (NEVER)

```gdscript
# WRONG: Child reaching up to wire itself to a distant node
func _ready() -> void:
    get_node("/root/GameServer/HeatGrid").heat_cell_changed.connect(_on_heat_changed)

# WRONG: Main.gd wiring everything to everything (god object)
func _ready() -> void:
    heat_grid.heat_cell_changed.connect(desire_resolver.on_heat_changed)
    heat_grid.heat_cell_changed.connect(hud.on_heat_changed)
    heat_grid.heat_cell_changed.connect(sound_manager.on_heat_changed)
    # ... 300 more lines of this

# WRONG: Signal relay chains (A signals B, B signals C, C signals D)
# If you need A to reach D, use the event bus. Do not build a telephone game.
```

**The correct patterns:**

```gdscript
# CORRECT: Scene root wires its children (AnimalRoot.gd)
func _ready() -> void:
    $AnimalAgent.state_changed.connect(_on_agent_state_changed)

# CORRECT: System self-subscribes to event bus (HUD's InspectPanel.gd)
func _ready() -> void:
    Events.animal_state_changed.connect(_on_animal_state_changed)
    Events.heat_cell_changed.connect(_on_heat_cell_changed)

# CORRECT: Manager wires to its mediees (ProximityEventManager.gd)
func _ready() -> void:
    var arm := get_parent().get_node("RobotArmStation") as Node2D
    arm.get_node("ActivationZone").body_entered.connect(_on_activation_zone_body_entered)
    _robot_arm = arm
```

## UI Listening Pattern

The HUD subscribes to the event bus. Period. No ViewModel, no UI dispatcher, no push model.

```gdscript
# inspect_panel.gd — part of the HUD CanvasLayer
extends PanelContainer

var _inspected_animal_id: int = -1

func _ready() -> void:
    Events.animal_state_changed.connect(_on_animal_state_changed)
    Events.animal_desire_critical.connect(_on_animal_desire_critical)
    Events.heat_cell_changed.connect(_on_heat_cell_changed)
    Events.robot_arm_activated.connect(_on_robot_arm_activated)

func inspect(animal_id: int) -> void:
    _inspected_animal_id = animal_id
    _refresh()

func _on_animal_state_changed(animal_id: int, _old: StringName, new_state: StringName) -> void:
    if animal_id != _inspected_animal_id: return
    %StateLabel.text = tr("STATE_" + new_state.to_upper())

func _on_animal_desire_critical(animal_id: int, desire_type: StringName, value: float) -> void:
    if animal_id != _inspected_animal_id: return
    %DesireBar.update_desire(desire_type, value)

func _on_heat_cell_changed(cell_id: int, _old: float, new_temp: float) -> void:
    if not _is_cell_relevant(cell_id): return
    %TempReadout.value = new_temp
```

**Why not a ViewModel?** At prototype scale (5 animals, 210 heat cells), the event bus has trivial traffic. A ViewModel adds an indirection layer that helps nobody and makes debugging harder. If we hit 1000 animals and the UI is receiving 10,000 events/sec it does not need, we add filtering at the event bus level (interest management), not an intermediate ViewModel. Cross that bridge if we reach it.

**Why not direct references?** The HUD is a CanvasLayer child of GameClient. GameServer owns the simulation state. These live on different sides of the client/server boundary. The HUD must never hold a reference to a GameServer child. The event bus is the client/server membrane.

## GameServer Siblings

Read each other's state directly during tick (they're siblings). Only emit to event bus for external listeners (HUD, Sound).

```gdscript
# DesireResolver.gd — reads HeatGrid directly, does not subscribe to its signals
@onready var _heat_grid: HeatGrid = get_parent().get_node("HeatGrid")

func _score_warmth(animal: AnimalAgent) -> float:
    var cell := _heat_grid.world_to_cell(animal.global_position)
    var temp := _heat_grid.get_temperature(cell)
    var deficit := animal.get_desire_deficit(&"warmth")
    return deficit * _warmth_curve.sample(temp / _heat_grid.max_temp)
```

**Rule: siblings under GameServer read each other. Everything else uses the event bus.**

## Signal Naming Convention

**Past tense for things that happened. Always.**

```gdscript
# Correct — past tense, describes a completed fact
signal state_changed(old_state: StringName, new_state: StringName)
signal heat_cell_changed(cell_id: int, old_temp: float, new_temp: float)
signal object_placed(object_id: int, rack: int, slot: int, object_type: StringName)
signal food_dispensed(can_id: int)
signal animal_relocated(animal_id: int, from_pos: Vector2, to_pos: Vector2)

# WRONG — present tense (ambiguous: is it happening? should it happen?)
signal animal_moving(animal_id: int, target: Vector2)
signal heat_changing(cell_id: int, new_temp: float)

# WRONG — imperative (signals are notifications, not commands)
signal move_animal(animal_id: int, target: Vector2)
signal update_heat(cell_id: int, temp: float)
```

**Naming structure:** `noun_verb_past_participle` or `noun_verbed`. Include only the parameters needed to react. Always include the ID of the thing that changed. Include old and new values when the listener needs to know the delta (heat, state). Omit old values when only the new state matters (object_placed).

**Slot naming:** `_on_<emitter>_<signal_name>`. If listening to the event bus, replace emitter with a descriptive noun.

```gdscript
# Direct signal slot
func _on_agent_state_changed(old_state: StringName, new_state: StringName) -> void:

# Event bus slot
func _on_animal_state_changed(animal_id: int, old_state: StringName, new_state: StringName) -> void:
```

## Emit / listen, not produce / consume

Name a cross-system signal by **what it is** (`purr`, `heat_cell_changed`, `food_dispensed`), never by what consumes it (`hum_producer`, `warmth_producer`, `power_source`). The emitter does not know its listeners.

Producer/consumer phrasing silently couples the emitter to a single downstream use. "Cats produce HUM" bakes HUM into the cat — removing HUM tomorrow means touching cats. "Cats emit on `purr`; HUM receivers listen on `purr`" lets any number of independent readers (HUM battery, ferret-calm system, sound mixer, narrator) consume the channel without modifying each other or the emitter.

Concrete rules that follow from this:

- **Don't generalize across physics.** Purring is acoustic; solar is electrical; heat is thermal. Each is its own channel with its own receiver. A single `power` channel that both cats and solar panels emit on is over-generalization that hides domain differences.
- **Only things that genuinely produce the signal emit on its channel.** If you catch yourself writing "a tuning fork could also declare `purr`," stop — tuning forks ring. When that feature ships, it gets `ring` as a separate capability with its own receiver.
- **The emitter's domain system writes the emission via a small scoped bridge.** For TCP: `ContentmentPurrBridge` reads `contentment` and writes `purr.intensity`. The bridge knows contentment and the purr channel; it never names HUM.
- **Tests should assert the consumer doesn't read the emitter's domain state.** `HumSystem.tick_charge` reads only `hum_receiver`, `purr`, `position` — never `contentment`, never species labels. A unit test that greps the charge path for `contentment` catches regressions.

Discovered while designing the HUM cable system; it's why Ring 1's naming shipped as `purr` (the thing) rather than `hum_producer` (the coupling).

## One Event Bus

Not per-system buses. Not typed channels. One `Events` autoload with all signals declared in one file. At prototype scale this is trivially maintainable. If it grows past 50 signals, split into `Events` (simulation) and `UIEvents` (input/HUD) — but not before.

---

## Scenario Traces → skill

Four worked end-to-end traces (ferret-drag, warmth-drop relocation, server placement, kitten cable-pull) plus the cross-system communication map used to live here. They moved to the `trace-signal-flow` skill — invoke `/trace-signal-flow` when wiring a new cross-system signal or debugging how an existing one propagates.

The traces are dense and only relevant during signal work; keeping them as a lazy-loaded skill cuts ~200 lines from this always-loaded rule without losing the information.

## Summary Rules

1. **Same scene? Direct signal.** Parent wires children in `_ready()`.
2. **Broadcast to unknown listeners? Event bus.** Emitter calls `Events.<signal>.emit()`. Listeners self-subscribe in their own `_ready()`.
3. **Multi-step sequence with ordering? Manager.** Manager listens for trigger, makes direct calls, broadcasts results.
4. **GameServer siblings read each other directly.** No signals needed for tick-synchronous data reads within the server.
5. **HUD only touches the event bus.** Never holds references to GameServer children.
6. **Signals are past tense.** They report facts. `thing_happened`, not `thing_happening` or `do_thing`.
7. **No `../` paths.** No child reaching up. No god-object wiring. If you cannot explain who owns the connection, the connection is wrong.
8. **One event bus.** Not per-system buses. Not typed channels. One `Events` autoload with all signals declared in one file. At prototype scale this is trivially maintainable. If it grows past 50 signals, split into `Events` (simulation) and `UIEvents` (input/HUD) — but not before.
