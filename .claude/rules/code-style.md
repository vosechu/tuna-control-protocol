---
paths:
  - "**/*.gd"
---

# TCP GDScript Code Style

## Types
Every variable, parameter, and return value has an explicit type annotation. No `Variant`. No `var x = 5`. Always `var x: int = 5`.

## Integers
Game values use int (0-1000 scale). Float only for rendering. Example: `var hunger: int = 850` not `var hunger: float = 0.85`.

## Return Conventions
- Commands: return `void`. Mutate state, emit events.
- Queries: return the object, never null. Assert on missing.
- Functional: return the transformed value.

## Null Handling
Never `null`. Use typed defaults, sentinel values (`INVALID_ID := -1`), or `NullObject` pattern. Check at boundaries, trust internally.

## Guard Clauses and Early Returns
Validate at top, early return on failure. Main logic at lowest indent level.

## Error Handling
`assert()` for programmer errors (debug only). `push_error()` + graceful skip for data errors (bad mod JSON). Never silent swallow.

## Signals
- Always past tense: `animal_relocated`, `cable_disconnected`
- Include ID of changed entity
- Include old + new values when delta matters
- Slot naming: `_on_<emitter>_<signal_name>`

## Naming Conventions
| What | Convention | Example |
|---|---|---|
| Classes | `PascalCase` | `AnimalState` |
| Functions | `snake_case` | `get_desire_weight()` |
| Variables | `snake_case` | `hunger_level` |
| Constants | `SCREAMING_SNAKE` | `MAX_MEMORIES` |
| Enums (type) | `PascalCase` | `enum Desire` |
| Enum values | `SCREAMING_SNAKE` | `Desire.HUNGER` |
| Private | `_prefix` | `_entities` |
| JSON keys | `snake_case` | `"base_desires"` |
| Mod IDs | `snake_case` | `"fluffy_ferret_friends"` |
| Namespaced IDs | `mod_id:entity_id` | `"tcp_base:cat"` |

## File Organization
One class per file. File name matches class name in snake_case. Inner classes only for private data structures.

## Comments
No obvious comments. Comments explain WHY, not WHAT. `# Ferrets score tubes higher when stressed because...` not `# Loop through ferrets`.

## Magic Numbers
None in logic. All game values from config JSON. Structural constants (`0`, `1`, `-1`, `INVALID_ID`) are fine.

## Config File Format
All config files use `.jsonc` (JSON with comments). Comments explain design intent, not structure. Schemas use JSON Schema for validation. Never use bare `.json` for game config — comments are mandatory for maintainability.

## `class_name` Registration
Use `class_name` for all `engine/` classes (public API). Omit for test files and internal helpers. `class_name` must match filename in PascalCase: `animal_state.gd` → `class_name AnimalState`.

## Typed Arrays
Always use typed arrays (`Array[int]`, `Array[AnimalState]`) in game logic. Untyped `Array` only when contents are genuinely heterogeneous (mod data before validation). Typed arrays are 2-4x faster due to skipping variant boxing.

## StringName for Hot Paths
Use `StringName` for signal names, component keys in GameStateDB, and any string used as a dictionary key in hot paths. Use `&"literal"` syntax for StringName literals. `String` is fine for display text, log messages, and cold paths.

## `@export` vs ConfigRegistry
`@export` is for scene-specific wiring (NodePaths, editor-time visual tweaks, debug toggles). Game balance values come from ConfigRegistry/JSON. Never duplicate a JSON config value as an export.

## `@onready` and Initialization Order
Core objects (RefCounted) are created in the node constructor or via `@onready`. Signal wiring happens in `_ready()`. Never access sibling nodes in `_enter_tree` — children are ready before parents (bottom-up).

## `_physics_process` vs `_process`
All simulation runs in `_physics_process` (fixed 10Hz timestep via `Engine.physics_ticks_per_second = 10`). `_process` is only for rendering interpolation, animation, and UI. Never put game logic in `_process`. Never put rendering in `_physics_process`.

## State Projection
GameStateDB is authoritative. Nodes project state to Godot systems (AnimationPlayer, ShaderMaterial, AudioStreamPlayer) in `_process`. Godot systems never write back to GameStateDB directly — they emit signals that the core interprets.

## Integer-Float Boundary
Positions are integer world pixels everywhere in the core (GameStateDB, AI, physics). The rendering boundary converts to `Vector2`/`float` via explicit cast:

```gdscript
# In core — integer pixels
var pos: Vector2i = db.get_component(id, &"position")
# In node rendering — cast to float
sprite.position = Vector2(pos)

static func to_unit(v: int) -> float:
    return float(v) / float(UNIT)
```

Never mix `int` and `float` coordinate math in the same function.

## Node Pooling
Node wrappers for animals are pooled (expensive to create/destroy). RefCounted core objects are created/freed directly (cheap). Always `queue_free()`, never `free()` on nodes.

## Resource Loading
Base game assets use `preload()`. Mod assets use `ResourceLoader.load_threaded_request()` during the mod loading phase. Never `load()` during gameplay ticks — it causes frame hitches.

---

## Reference Examples

### Integer scale constants

```gdscript
const UNIT := 1000              # General-purpose thousandths
const PERCENT := 100            # Percentages as 0-10000 (hundredths of percent)

# In core/ — integer math only
var happiness: int = 850  # 850/1000 = 0.85

# In nodes/ — convert for rendering
var display_happiness: float = float(state.happiness) / float(UNIT)
```

### Command / Query / Functional query

```gdscript
# COMMAND — mutates state, returns void
func place_item(entity_id: int, position: Vector2i) -> void:

# QUERY — reads state, returns object, never null
func get_animal(entity_id: int) -> AnimalState:
    assert(_entities.has(entity_id), "Unknown entity: %d" % entity_id)
    return _entities[entity_id]

# FUNCTIONAL QUERY — transforms + returns result
func sorted_by_happiness(animals: Array[AnimalState]) -> Array[AnimalState]:
```

### Sentinel pattern (no null)

```gdscript
const INVALID_ID := -1
func find_nearest_food(position: Vector2i) -> int:
    # Returns entity ID or INVALID_ID
    ...

var food_id := board.find_nearest_food(pos)
if food_id == INVALID_ID:
    return
var food := db.get_item(food_id)
```

### Guard clauses

```gdscript
func feed(animal_id: int, food_id: int) -> void:
    if not _db.has_entity(animal_id):
        assert(false, "Invalid animal: %d" % animal_id)
        return
    if not _db.has_entity(food_id):
        assert(false, "Invalid food: %d" % food_id)
        return
    var animal := _db.get_animal(animal_id)
    var food := _db.get_item(food_id)
    if food.remaining <= 0:
        return
    animal.satisfy_desire(Desire.HUNGER, food.nutrition_value)
    food.consume()
    _event_bus.emit_animal_fed(animal_id, food_id)
```

### Error handling quick reference

| Context | Mechanism |
|---|---|
| Programmer error | `assert()` |
| Expected "not found" | Sentinel (`INVALID_ID`, empty array) |
| Cross-system events | Event bus signals |
| Bad mod data | `ModLoader` logs + skips |
| Bad network message | Log + drop |
| Corrupt save | Log + attempt migration + fail to menu |
