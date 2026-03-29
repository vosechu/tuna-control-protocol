# TCP Save System

## GameStateDB
Single source of truth. Flat, ECS-ish. Entities are integer IDs. Components are named dictionaries. Commands mutate (return void), queries read (never null). Watchers fire end-of-tick (batched), not immediately on write.

## Save Format: MessagePack + Header

```
Bytes 0-3:    "TCP\0"              (magic)
Bytes 4-5:    uint16 schema_ver     (save schema version)
Bytes 6-7:    uint16 flags          (bit 0: compressed, bit 1: multiplayer)
Bytes 8-N:    payload               (MessagePack, optionally zstd-compressed)
```

Why MessagePack: 40-60% smaller than JSON, fast parse, inspectable with standard tools. Not custom binary (maintainable). Not SQLite (overkill, complicates sharing).

## Save Payload

All values are integers. Position in position-scale units. Desires/personality in thousandths.

```json
{
  "version": 1,
  "engine_version": "1.0.0",
  "mods": [{"id": "tcp_base", "version": "0.1.0"}],
  "seed": 42,
  "tick": 148201,
  "entities": {
    "1": {
      "species": {"id": "tcp_base:cat", "name": "Mochi"},
      "position": {"x": 15200, "y": 8400, "rack": 1, "slot": 8},
      "desires": {"hunger": 340, "warmth": 820, "social": 550},
      "personality": {"hunger_mod": 1200, "social_mod": 700},
      "memories": [{"loc_x": 300, "loc_y": 1200, "valence": 900, "tick": 48201}],
      "skills": [{"id": "knead_dough", "level": 490, "generation": 2}],
      "behavior": "resting"
    },
    "42": {
      "cable": {"from_id": 5, "to_id": 12, "cable_type": "power"}
    }
  }
}
```

## Versioning & Migration
Each save records schema version. Migrations are explicit sequential functions (`_migrate_v1_to_v2`). Golden save files from every version in `tests/snapshots/saves/`. CI asserts successful migration + no data loss.

## Sharing via `tuna://`
- **Direct:** Upload to relay, reference by content hash: `tuna://save/<base32-hash>`
- **Compact:** Small states base32-encoded into URI
- **Three-word names:** 256-word cat dictionary + 6 base32 chars: `tuna://whisker_noodle_biscuit/a3f9k2`

---

## Reference: Save Migrator

```gdscript
var _migrations: Dictionary = {
    1: _migrate_v1_to_v2,
    2: _migrate_v2_to_v3,
}

func migrate(data: Dictionary) -> Dictionary:
    while data["version"] < CURRENT_VERSION:
        var fn: Callable = _migrations[data["version"]]
        data = fn.call(data)
    return data
```

Golden save files from every schema version in `tests/snapshots/saves/`. CI loads each and asserts successful migration + no data loss.
