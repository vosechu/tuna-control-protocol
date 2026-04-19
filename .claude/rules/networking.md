---
paths:
  - "engine/**/net_*"
  - "engine/**/network*"
  - "engine/**/peer*"
  - "nodes/**/net_*"
---

# TCP Networking Rules

## Architecture
Client-server, always. Solo game starts a local server. Client sends **intents**. Server validates and applies. Server broadcasts **deltas**.

```
Player Input -> Client Intent -> Server Validates -> GameStateDB Mutated -> Delta Broadcast -> Clients Apply
```

## What goes over the wire

**Intents (client -> server):** place_item, move_item, assign_priority, etc.

**Deltas (server -> clients):** entity_moved, entity_spawned, desire_changed, item_placed, etc.

**NOT sent:** cursor position, camera position, UI state, animation state, per-tick AI scoring, sound mixing. All derived client-side.

## Protocol
MessagePack over ENet (UDP with reliability). Message format: `[uint8 type][uint32 tick][MessagePack payload]`.

Types: CLIENT_INTENT (0x01), SERVER_DELTA (0x02, reliable ordered), SERVER_SNAPSHOT (0x03, full state sync), HEARTBEAT (0x04, unreliable).

Deltas batched per tick. One message per server tick.

## Bandwidth
Only send deltas when state actually changes:
- Position: only on spatial hash cell crossing
- Desires: only on threshold band crossing (multiples of 100)
- Behavior: every state transition
- Items: place/remove/transform

At 1000 animals, ~5% changing/tick = ~50 deltas * ~20 bytes = ~1KB/tick = ~20KB/sec.

## Interest Management
See viewport-lod.md for subscription zones.
