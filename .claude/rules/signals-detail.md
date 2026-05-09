---
paths:
  - "engine/**"
  - "nodes/**"
---

# TCP Signal Architecture — Worked Examples

Companion to `signals.md`. Code-level examples and design rationale for each of the three patterns. Read this when wiring a new signal connection. For end-to-end traces, invoke `/trace-signal-flow`.

## Pattern 1 — Direct signal (parent-child)

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

The parent created the children. It knows they exist. It is responsible for their lifecycle. Tightest, most debuggable connection type.

## Pattern 2 — Event bus

```gdscript
# events.gd — autoload singleton, registered in Project > AutoLoad as "Events"
extends Node

# Simulation events (emitted by server-side systems)
signal heat_cell_changed(cell_id: int, old_temp: float, new_temp: float)
signal object_placed(object_id: int, rack: int, slot: int, object_type: StringName)
signal hum_reserve_changed(hum_id: int, old_reserve: int, new_reserve: int)
signal hum_brownout_entered(hum_id: int)

# Animal events
signal animal_state_changed(animal_id: int, old_state: StringName, new_state: StringName)
signal animal_relocated(animal_id: int, from_pos: Vector2, to_pos: Vector2)
signal animal_arrived(animal_id: int, species: StringName)

# Interaction events
signal proximity_event_triggered(event_type: StringName, actor_id: int, target_id: int)
signal robot_arm_activated(trigger_object_id: int, trigger_actor_id: int)
signal robot_arm_action_completed(action_type: StringName, target_id: int)

# Infrastructure events
signal server_powered_on(object_id: int, rack: int, slot: int)
signal power_state_changed(rack: int, slot: int, powered: bool)
```

HeatGrid does not import AnimalAgent. The HUD does not import HeatGrid. They react to the same facts via `Events`. The bus is the postal service — the sender doesn't know the recipient's address.

## Pattern 3 — Manager mediation

```gdscript
# ProximityEventManager.gd — orchestrates discovery events
# This is NOT a signal relay. It makes decisions and enforces ordering.

func _on_activation_zone_body_entered(body: Node2D) -> void:
    if not body is PlacedObject: return
    var obj := body as PlacedObject
    if obj.object_type != &"tuna_can": return
    if _arm_busy: return
    if not _cooldown_expired(&"robot_arm_activate"): return

    # Step 1: lock the arm
    _arm_busy = true
    # Step 2: direct method call (not signal) — we own this sequence
    robot_arm.start_action(&"open_can", obj)
    # Step 3: broadcast that this happened (event bus for everyone else)
    Events.robot_arm_activated.emit(obj.get_instance_id(), _get_nearest_animal_id(obj))
    # Step 4: arm calls back via direct signal connected in _ready()

func _on_arm_action_completed(action_type: StringName, target: PlacedObject) -> void:
    _arm_busy = false
    _reset_cooldown(&"robot_arm_activate")
    if action_type == &"open_can":
        target.convert_to(&"open_tuna_can")
        Events.robot_arm_action_completed.emit(action_type, target.get_instance_id())
```

A signal chain cannot enforce "check cooldown, then lock arm, then start animation, then wait, then transform object." That's control flow. Control flow belongs in a function.

## Anti-patterns

```gdscript
# WRONG: Child reaching up to wire itself to a distant node
func _ready() -> void:
    get_node("/root/GameServer/HeatGrid").heat_cell_changed.connect(_on_heat_changed)

# WRONG: Main.gd wiring everything to everything (god object)
func _ready() -> void:
    heat_grid.heat_cell_changed.connect(desire_resolver.on_heat_changed)
    heat_grid.heat_cell_changed.connect(hud.on_heat_changed)
    heat_grid.heat_cell_changed.connect(sound_manager.on_heat_changed)

# WRONG: Signal relay chains (A → B → C → D)
# If A needs to reach D, use the event bus. No telephone games.
```

Correct patterns:

```gdscript
# Scene root wires its children (AnimalRoot.gd)
func _ready() -> void:
    $AnimalAgent.state_changed.connect(_on_agent_state_changed)

# System self-subscribes to event bus (HUD's InspectPanel.gd)
func _ready() -> void:
    Events.animal_state_changed.connect(_on_animal_state_changed)
    Events.heat_cell_changed.connect(_on_heat_cell_changed)

# Manager wires to its mediees (ProximityEventManager.gd)
func _ready() -> void:
    var arm := get_parent().get_node("RobotArmStation") as Node2D
    arm.get_node("ActivationZone").body_entered.connect(_on_activation_zone_body_entered)
    _robot_arm = arm
```

## UI listening — full example

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

**Why not a ViewModel?** At prototype scale (5 animals, 210 heat cells), the bus has trivial traffic. A ViewModel adds indirection that helps nobody. If we hit 1000 animals and 10,000 events/sec the UI doesn't need, add filtering at the bus level (interest management) — not an intermediate ViewModel.

**Why not direct references?** The HUD is a CanvasLayer child of GameClient. GameServer owns simulation state. The HUD must never hold a reference to a GameServer child. `Events` is the client/server membrane.

## GameServer siblings

```gdscript
# DesireResolver.gd — reads HeatGrid directly, does not subscribe to its signals
@onready var _heat_grid: HeatGrid = get_parent().get_node("HeatGrid")

func _score_warmth(animal: AnimalAgent) -> float:
    var cell := _heat_grid.world_to_cell(animal.global_position)
    var temp := _heat_grid.get_temperature(cell)
    var deficit := animal.get_desire_deficit(&"warmth")
    return deficit * _warmth_curve.sample(temp / _heat_grid.max_temp)
```

Siblings under GameServer read each other directly. Everything else uses the bus.

## Emit/listen rationale

Producer/consumer phrasing silently couples the emitter to a single downstream. "Cats produce HUM" bakes HUM into the cat — removing HUM tomorrow means touching cats. "Cats emit on `purr`; HUM receivers listen on `purr`" lets any number of independent readers consume the channel without modifying each other or the emitter.

Concrete rules:

- **Don't generalize across physics.** Purr is acoustic; solar is electrical; heat is thermal. Each is its own channel with its own receiver. A single `power` channel that both cats and solar panels emit on is over-generalization that hides domain differences.
- **Only things that genuinely produce the signal emit on its channel.** Tuning forks ring — they don't purr. When that feature ships, it gets `ring` as a separate capability with its own receiver.
- **The emitter's domain system writes the emission via a small scoped bridge.** `ContentmentPurrBridge` reads `contentment` and writes `purr.intensity`. The bridge knows contentment and the purr channel; it never names HUM.
- **Tests should assert the consumer doesn't read the emitter's domain state.** `HumSystem.tick_charge` reads only `hum_receiver`, `purr`, `position` — never `contentment`, never species labels.

Discovered while designing the HUM cable system; it's why Ring 1's naming shipped as `purr` (the thing) rather than `hum_producer` (the coupling).
