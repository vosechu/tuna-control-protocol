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
signal cable_connected(from_id: int, to_id: int, cable_type: StringName)
signal cable_disconnected(from_id: int, to_id: int)

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

## Cross-System Communication Map

```
                         ┌─────────────────────────────────────────────────┐
                         │                  Events (bus)                   │
                         └──┬──────┬──────┬──────┬──────┬──────┬──────┬───┘
                            │      │      │      │      │      │      │
                  ┌─────────┘  ┌───┘  ┌───┘  ┌───┘  ┌───┘  ┌───┘  ┌───┘
                  ▼            ▼      ▼      ▼      ▼      ▼      ▼
               ┌──────┐  ┌──────┐  ┌────┐  ┌─────┐ ┌────┐ ┌─────┐ ┌──────┐
               │ HUD  │  │Sound │  │Nav │  │Anim │ │Heat│ │Desir│ │Proxim│
               │      │  │Mgr   │  │Graph│ │Reg  │ │Grid│ │Res  │ │EvtMgr│
               └──────┘  └──────┘  └────┘  └─────┘ └────┘ └─────┘ └──────┘
                  ▲          ▲                 │       │       │       │
                  │          │                 │       │       │       │
               listen     listen             emit    emit    emit    emit +
               only       only                via     via     via   orchestrate
                                              bus     bus     bus
```

**Data flows downward through the tick.** HeatGrid propagates, then DesireResolver scores, then AnimalRegistry executes actions, then ProximityEventManager checks triggers. Each step emits to the event bus after completing its work. Listeners (HUD, Sound, NavGraph) react asynchronously within the same frame.

**No system calls backward in the tick.** DesireResolver reads HeatGrid state directly (it is a sibling under GameServer and has a reference). It does NOT subscribe to `heat_cell_changed` signals to maintain a shadow copy. Within GameServer, siblings may read each other's public state. They only use the event bus to notify external listeners (HUD, Sound, client-side systems).

## Signal Naming Convention

**Past tense for things that happened. Always.**

```gdscript
# Correct — past tense, describes a completed fact
signal state_changed(old_state: StringName, new_state: StringName)
signal heat_cell_changed(cell_id: int, old_temp: float, new_temp: float)
signal object_placed(object_id: int, rack: int, slot: int, object_type: StringName)
signal cable_disconnected(from_id: int, to_id: int)
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

## One Event Bus

Not per-system buses. Not typed channels. One `Events` autoload with all signals declared in one file. At prototype scale this is trivially maintainable. If it grows past 50 signals, split into `Events` (simulation) and `UIEvents` (input/HUD) — but not before.

---

## Scenario Traces

Four complete signal traces through the architecture. Each shows the trigger, every hop, and the final visual/audio result.

### Scenario 1: Ferret drags a tuna can near the robot arm

**Trigger:** Ferret's AI chooses "drag tuna_can toward robot arm" as highest-scoring action during DesireResolver evaluation.

```
TICK N: DesireResolver scores ferret_01's options
  └─ "drag tuna_can_07 toward robot_arm" wins (stimulation desire + learned behavior)
  └─ AnimalRegistry.tick_actions() executes: ferret_01 enters PERFORMING state
      └─ AnimalAgent emits state_changed("SEEKING", "PERFORMING")  [direct signal]
          └─ AnimalRoot._on_agent_state_changed():
              ├─ Sprite.play("drag")                               [direct call]
              └─ SoundEmitter.play("ferret_churr")                 [direct call]
      └─ Events.animal_state_changed.emit(ferret_01_id, "SEEKING", "PERFORMING")
          ├─ HUD.InspectPanel: updates state label if inspecting ferret_01
          └─ SoundManager: no action (animal sound handled by SoundEmitter)

TICK N+3: Ferret drags can 1.5U closer to arm (drag step = 1.5U)
  └─ PlacedObject (tuna_can_07) position updates
  └─ Events.object_placed is NOT emitted (drag is not player placement)

TICK N+6: Can enters RobotArmStation.ActivationZone (Area2D)
  └─ ActivationZone.body_entered signal fires                     [Godot built-in]
      └─ ProximityEventManager._on_activation_zone_body_entered()  [direct signal]
          ├─ Checks: is it a tuna can? Yes. Arm busy? No. Cooldown? Clear.
          ├─ _arm_busy = true                                      [state update]
          ├─ robot_arm.start_action("open_can", tuna_can_07)       [direct call]
          │   └─ ArmSprite starts "reach_and_open" animation       [internal]
          │   └─ AudioEmitter.play("servo_whir")                   [internal]
          └─ Events.robot_arm_activated.emit(can_07_id, ferret_01_id)
              ├─ HUD.RobotNarrator: "Processing packet... unusual form factor"
              ├─ SoundManager: plays robot diagnostic beep layer
              └─ HUD.InspectPanel: shows arm activity if inspecting arm

TICK N+12: Arm animation completes
  └─ robot_arm emits action_completed("open_can", tuna_can_07)    [direct signal]
      └─ ProximityEventManager._on_arm_action_completed():
          ├─ _arm_busy = false
          ├─ tuna_can_07.convert_to("open_tuna_can")              [direct call]
          │   └─ Object now advertises: food +0.9, radius 4U
          └─ Events.robot_arm_action_completed.emit("open_can", can_07_id)
              ├─ SoundManager: plays "can_pop" + "satisfied_hum"
              └─ HUD.RobotNarrator: "Packet unpacked. Contents: ???"

TICK N+13: DesireResolver picks up new food advertisement
  └─ Nearby cats score open_tuna_can highly (food deficit * 0.9 strength)
  └─ cat_02 transitions LOAFING → SEEKING → MOVING_TO (toward can)
      └─ (same state_changed flow as above)
```

**Pattern used:** ProximityEventManager is the **manager** for this sequence. It uses a direct signal from the ActivationZone, makes direct calls to the robot arm, and broadcasts results via the event bus. The HUD and SoundManager are passive listeners on the bus.

### Scenario 2: Cat's warmth drops below threshold and it relocates

**Trigger:** Player removes a server, HeatGrid propagates, a cat's warmth desire score changes.

```
TICK N: Player sends intent "remove server_03 from rack 1, slot 8"
  └─ GameServer validates and executes removal
  └─ ObjectRegistry removes server_03
  └─ Events.object_removed.emit(server_03_id, 1, 8)
      ├─ NavGraph: removes associated nav nodes, checks path disruption
      └─ HUD: updates rack view if visible

TICK N (same tick, step 1): HeatGrid.propagate()
  └─ Cells near rack 1, slots 6-14 lose heat
  └─ For each changed cell:
      Events.heat_cell_changed.emit(cell_id, old_temp, new_temp)
      ├─ HUD: updates heat overlay if visible
      └─ SoundManager: adjusts ambient hum volume for that area

TICK N (step 3): AnimalRegistry.tick_desires()
  └─ cat_00 is in rack 1, slot 10 (was near removed server)
  └─ warmth satisfaction drops: 0.85 → 0.42 (below comfort threshold 0.5)
  └─ Events.animal_desire_critical.emit(cat_00_id, "warmth", 0.42)
      ├─ HUD.InspectPanel: warmth bar turns yellow if inspecting cat_00
      └─ SoundManager: no action (desire changes don't have sounds)

TICK N (step 4): DesireResolver.evaluate_next_batch()
  └─ cat_00 is in this batch
  └─ DesireResolver reads HeatGrid directly: current cell temp is low
  └─ Scores all advertisements: "warm spot at rack 2, slot 12" scores 0.78
  └─ Current commitment_score for LOAFING: 0.55, decayed
  └─ 0.78 > 0.55 + 0.15 (hysteresis threshold) → transition approved
  └─ cat_00.AnimalAgent transitions LOAFING → SEEKING
      └─ AnimalAgent emits state_changed("LOAFING", "SEEKING")    [direct signal]
          └─ AnimalRoot._on_agent_state_changed():
              ├─ Sprite.play("stand_stretch")                      [3-5 sec anim]
              └─ SoundEmitter.play("cat_mrrp")
      └─ Events.animal_state_changed.emit(cat_00_id, "LOAFING", "SEEKING")
          ├─ HUD.InspectPanel: "Status: RELOCATING" if inspecting
          └─ SoundManager: no additional action

TICK N+1 (step 5): AnimalRegistry.tick_actions()
  └─ cat_00 pathfinds to rack 2, slot 12 via NavGraph (direct read)
  └─ cat_00 enters MOVING_TO, begins interpolated movement
      └─ Events.animal_relocated.emit(cat_00_id, old_pos, target_pos)
          └─ SoundManager: soft paw-pad sounds based on surface type

TICK N+30ish: cat_00 arrives, enters PERFORMING → settles → LOAFING
  └─ warmth satisfaction climbs as it sits in the warm cell
  └─ Sprite.play("curl_up"), SoundEmitter.play("purr_start")
```

**Pattern used:** No manager needed. HeatGrid emits to the event bus. DesireResolver reads HeatGrid state directly (sibling read). AnimalAgent uses direct signals to its scene root. External listeners (HUD, Sound) subscribe to the event bus.

### Scenario 3: Player places a server and heat propagation updates

**Trigger:** Player clicks to place a server.

```
INPUT: Player clicks rack 0, slot 5 while holding a 2U server

GameClient sends intent to GameServer:
  └─ GameServer.ObjectRegistry validates placement (slots 5-6 clear? yes)
  └─ ObjectRegistry creates server_04, assigns to rack 0, slots 5-6
  └─ HeatGrid.add_source(rack 0, slots 5-6, heat_value from config)
  └─ Events.object_placed.emit(server_04_id, 0, 5, "server_1u")
      ├─ NavGraph._on_object_placed():
      │   └─ Adds RACK_SLOT_NODEs for slots 5-6
      │   └─ Connects edges to adjacent nodes (slot 4, slot 7, floor)
      ├─ HUD: places server sprite, plays "server_slide_in" animation
      ├─ SoundManager: plays "rack_slide" + "fan_spinup"
      └─ GameClient.World: instantiates visual PlacedObject scene

NEXT TICK, step 1: HeatGrid.propagate()
  └─ New heat source radiates: 3U up, 1U down, 3U left/right
  └─ ~12 cells update temperatures
  └─ For each changed cell:
      Events.heat_cell_changed.emit(cell_id, old_temp, new_temp)
      ├─ HUD: heat overlay updates (if toggled on)
      └─ SoundManager: ambient hum adjusts for warm zone

NEXT TICK, step 3: AnimalRegistry.tick_desires()
  └─ Animals near rack 0 gain warmth satisfaction
  └─ cat_01 in rack 0, slot 3: warmth 0.6 → 0.82 (contented)
  └─ No critical desire change — no event emitted (only critical emits)

NEXT TICK, step 4: DesireResolver.evaluate_next_batch()
  └─ New server also advertises: comfort +0.3 (warm flat surface)
  └─ If a cat is currently seeking warmth, the new spot may win
  └─ Otherwise, hysteresis keeps everyone where they are (abundance, not disruption)
```

**Pattern used:** Event bus for the placement broadcast. HeatGrid updates internally on the next tick. NavGraph and HUD self-subscribe to `object_placed` on the bus. No manager needed — placement is a single atomic operation, not a multi-step sequence.

### Scenario 4: Kitten unplugs a cable and the server goes cold

**Trigger:** Kitten ambient behavior "tangle with cable" succeeds in disconnecting a power cable.

```
TICK N: AnimalRegistry.tick_actions()
  └─ kitten_00 is in ambient state EXPLORING near rack 1
  └─ Ambient behavior roller picks "tangle_cable" (weighted by curiosity desire)
  └─ kitten_00 targets cable_05 (power cable from PDU to server_02)
  └─ Cable.disconnect() is called by AnimalRegistry (it owns action execution)
      └─ Events.cable_disconnected.emit(pdu_01_id, server_02_id)

TICK N (immediate consequence, still in tick_actions):
  └─ ObjectRegistry receives cable_disconnected (direct subscription, sibling)
  └─ server_02.set_powered(false)
      └─ Server stops emitting heat: HeatGrid.remove_source(server_02 cells)
      └─ Events.server_powered_off.emit(server_02_id, 1, 8)
          ├─ HUD: server sprite fans stop, status lights go dark
          ├─ SoundManager: "fan_spindown" + "power_off_click"
          ├─ HUD.RobotNarrator: "WARNING: Server offline. Last IOPS: 47. Cause: unknown"
          └─ NavGraph: no change (server still physically present)

  └─ Events.cable_disconnected is also heard by:
      ├─ HUD: in wiring view, cable_05 turns gray / dashed
      └─ SoundManager: plays "cable_pop" at cable_05's position

TICK N, step 1 (next tick cycle): HeatGrid.propagate()
  └─ Cells around server_02 cool down
  └─ Events.heat_cell_changed emitted for affected cells
      └─ (same flow as Scenario 2 from here)

TICK N, step 3: AnimalRegistry.tick_desires()
  └─ cat_02 sleeping ON server_02: warmth drops 0.9 → 0.4
  └─ Events.animal_desire_critical.emit(cat_02_id, "warmth", 0.4)

TICK N, step 4: DesireResolver scores cat_02
  └─ cat_02 transitions to SEEKING warm spot → RELOCATING
  └─ (same relocation flow as Scenario 2)

MEANWHILE: kitten_00 transitions to next ambient behavior
  └─ AnimalAgent emits state_changed("EXPLORING", "IDLE")         [direct signal]
      └─ Sprite.play("sit_lick_paw")  — the kitten is unconcerned
      └─ SoundEmitter.play("kitten_mew")
  └─ Events.animal_state_changed.emit(kitten_00_id, "EXPLORING", "IDLE")
      └─ HUD.RobotNarrator: (if it noticed the correlation)
           "Diagnostics: power anomaly coincided with small server activity in sector 1.
            Recommend firmware update."
```

**Patterns used:** AnimalRegistry executes the cable disconnect (it owns action execution). ObjectRegistry reacts to the disconnection via direct sibling subscription. The power-off consequence cascades through the event bus. HeatGrid updates on the next tick. The kitten's state change uses direct signals internally, event bus externally. The RobotNarrator listens to multiple event bus signals and correlates them for comedy.

---

## Summary Rules

1. **Same scene? Direct signal.** Parent wires children in `_ready()`.
2. **Broadcast to unknown listeners? Event bus.** Emitter calls `Events.<signal>.emit()`. Listeners self-subscribe in their own `_ready()`.
3. **Multi-step sequence with ordering? Manager.** Manager listens for trigger, makes direct calls, broadcasts results.
4. **GameServer siblings read each other directly.** No signals needed for tick-synchronous data reads within the server.
5. **HUD only touches the event bus.** Never holds references to GameServer children.
6. **Signals are past tense.** They report facts. `thing_happened`, not `thing_happening` or `do_thing`.
7. **No `../` paths.** No child reaching up. No god-object wiring. If you cannot explain who owns the connection, the connection is wrong.
8. **One event bus.** Not per-system buses. Not typed channels. One `Events` autoload with all signals declared in one file. At prototype scale this is trivially maintainable. If it grows past 50 signals, split into `Events` (simulation) and `UIEvents` (input/HUD) — but not before.
