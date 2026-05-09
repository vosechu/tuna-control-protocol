# TCP File Structure

```
res://
  engine/                          # Framework (the HOW)
    core/                          # Game loop, tick scheduling, entity management
      game_state_db.gd             # Central state store (RefCounted)
      entity_registry.gd           # Entity ID allocation
      event_bus.gd                 # Global signal hub
      tick_scheduler.gd            # Fixed timestep, LOD scheduling
      version.gd                   # Semver constants for each system
    desires/                       # Desire evaluation engine
      desire_system.gd             # Evaluates desires against advertisements
      utility_scorer.gd            # Scoring with response curves
      response_curves.gd           # Library: linear, logistic, exponential, step
      advertisement_board.gd       # Objects advertise what they satisfy
    spatial/                       # Spatial indexing
      spatial_hash.gd              # Grid-based spatial lookup
      viewport_manager.gd          # LOD zones, subscription management
    animals/                       # Animal simulation
      animal_state.gd              # Per-animal instance data
      memory_bank.gd               # 5-10 memory slots with decay
      teaching_system.gd           # Skill transfer with degradation
    economy/                       # Resource flow
      resource_flow.gd             # Pipe/wire resource transfer
    inspect/                       # Inspect drawer state (RefCounted)
      inspect_drawer_state.gd      # State machine + content builders
    network/                       # Networking
      net_server.gd                # Authoritative server
      net_client.gd                # Client intent sender
      net_protocol.gd              # Message schema
      net_lod.gd                   # Interest management / subscription zones
    save/                          # Serialization
      save_writer.gd               # GameStateDB -> MessagePack
      save_reader.gd               # MessagePack -> GameStateDB
      save_migrator.gd             # Version migration functions
    mod/                           # Mod loading
      mod_loader.gd                # Discovery, validation, layering
      mod_registry.gd              # Active mod list, version resolution
      config_registry.gd           # Merged config from all layers
      asset_registry.gd            # Virtual filesystem overlay

  nodes/                           # Thin Godot wrappers (rendering layer)
    animal_node.gd                 # Owns AnimalState, renders sprite, plays audio
    infrastructure_node.gd         # Owns infra config, renders, advertises
    robot_arm_node.gd              # Robot arm rendering + animation
    hud/                           # UI nodes
    camera/                        # Viewport, zoom, LOD transitions

  mods/                            # Mod directory
    tcp_base/                      # THE BASE GAME (ships as a mod)
      mod.json
      species/                     # cat.json, ferret.json
      items/                       # cardboard_box.json, tuna_can.json, comfy_pile.json
      desires/                     # hunger.json, warmth.json, social.json, comfort.json, curiosity.json
      infrastructure/              # server_1u.json, pdu.json, cooling_pipe.json, gerbil_tube.json
      behaviors/                   # seek.json, consume.json, rest.json, play.json, wander.json, teach.json
      sounds/                      # cat/purr_low.ogg, ferret/dook.ogg, robot/servo.ogg, etc.
      sprites/                     # cat/idle.png, ferret/idle.png, etc.
      config/                      # balance.json, teaching.json, desire_thresholds.json, spawn_conditions.json
      locale/                      # en.json

  tests/                           # All tests
    unit/                          # Pure logic, no scene tree
    scenario/                      # Specific AI behavior regressions
    integration/                   # Needs scene tree (minimal)
    simulation/                    # Headless stress/soak tests
    performance/                   # Benchmark assertions
    snapshots/                     # Golden files for regression
```
