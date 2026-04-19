---
name: trace-signal-flow
description: "Use when wiring a new cross-system signal or debugging how an existing signal propagates across HeatGrid, DesireResolver, AnimalRegistry, HUD, and SoundManager. Walks through four worked end-to-end traces showing which pattern (direct / event-bus / manager) applies at each hop."
user-invokable: true
---

# Trace signal flow

Slim rule (`.claude/rules/signals.md`) defines the three patterns and the naming rules. This skill is the **case-study companion**: four complete traces showing every hop from trigger to final visual/audio, with the pattern used at each step called out.

Use when:

- **Wiring a new multi-system signal** — pick the closest trace below, adapt the hops.
- **Debugging a signal that isn't reaching its listener** — walk the trace hop-by-hop and find where the chain breaks.
- **Reviewing a PR that introduces a new event** — check the proposed flow matches one of these shapes.

If none of the traces resemble your case, you're probably inventing a fifth pattern — stop and re-read `signals.md`'s decision flowchart first.

---

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

**No system calls backward in the tick.** DesireResolver reads HeatGrid state directly (sibling under GameServer). It does not subscribe to `heat_cell_changed` signals to maintain a shadow copy. GameServer siblings may read each other's public state; they use the event bus only to notify external listeners (HUD, Sound, client-side).

---

## Scenario 1: Ferret drags a tuna can near the robot arm

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

## Scenario 2: Cat's warmth drops below threshold and it relocates

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

## Scenario 3: Player places a server and heat propagation updates

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

## Scenario 4: Kitten unplugs a cable and the server goes cold

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
