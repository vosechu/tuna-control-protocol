# SensoryEmissionSystem — data-driven, mod-extensible animal emission translation

**Status:** draft, 2026-05-09.
**Replaces:** `engine/core/contentment_purr_bridge.gd` (`ContentmentPurrBridge`).

---

## What this spec is

The `ContentmentPurrBridge` is the per-tick translator from a cat's interior state (`contentment.is_satisfied`, `purr_config.rate_when_satisfied`, `purr_config.base_radius_ru`) to its broadcast emission components (`purr.intensity`, `purr.radius_px`). HUM listens on `purr.intensity` and credits charge accordingly.

The bridge works for the one input it has, but it doesn't scale:

1. **Method-per-modifier.** When mood, stress, kitten amplifier compose into the formula, each becomes a hand-written branch in `tick()`. Most modifiers are very similar shapes (multiply by factor, conditionally apply); duplicating them as engine code is busywork.
2. **Mods can't reach in.** The bridge lives in `engine/core/`, which mods don't write to. A mod that wants its species to purr differently — or wants a new modifier (e.g. fur thickness reducing acoustic output) — has no surface.
3. **Translation logic is engine-coded but the inputs are data.** The cat recipe declares `purr.rate_when_satisfied: 1000` and `purr.base_radius_ru: 6`; the bridge hardcodes "satisfied → use that rate." The asymmetry is invisible until you try to add a second emission kind (a tuning fork's `ring`, a cat's `scent`, a future thermal radiation channel) and discover every new emission needs a new bridge file.

This spec replaces the bridge with a data-driven system whose input vocabulary is recipe-declared and mod-patchable. The cat declares *what it produces*; mod-patchable global config declares *how the produced output maps to a channel and what physics that channel obeys*; the engine has a small bounded library of operations and falloff curves that recipe and config draw from.

The replacement system is `engine/core/sensory_emission_system.gd` (`class_name SensoryEmissionSystem`).

---

## Goals

1. Adding a new modifier to an existing emission (e.g. stress dampens purr) is a recipe edit, not an engine PR.
2. Adding a new emission to an entity (e.g. cats also emit scent) is a recipe edit + a global-config entry, not an engine PR.
3. Adding a new emission *kind from a different mod* (e.g. tuning fork's `ring`) is a recipe + config patch from that mod's files, never touching `engine/`.
4. The cat recipe expresses what a cat would know about itself (it's contented, stress dampens it, it produces purr at a certain loudness). It does not express channel mapping or physics-of-propagation — those are properties of the channel, not the cat.
5. The engine retains ownership of the *vocabulary* (which ops exist, which falloff curves exist) so the system can't be turned into a formula DSL via JSON.
6. HUM's intake (`HumSystem.tick_charge` reading `purr.intensity`) does not change. The replacement is internal to the bridge layer.

## Non-goals

- **No unifying** the per-output emission components (`purr.intensity`, future `scent.intensity`) with the existing `advertisements` system used for object ads. Animals' dynamic emissions and objects' static ads stay separate surfaces in this spec.
- **No channel-based propagation.** Today HUM reads `purr.intensity` directly. The `channel: "acoustic"` mapping is forward-compat metadata; no consumer reads it in this spec.
- **No falloff applied in this system.** Falloff is a propagation concern. SensoryEmissionSystem produces `intensity` and `radius_px` per output. Downstream consumers decide how to apply falloff.
- **No writer for `stress`.** Stress lands as a recipe-declared component initialized to 0 and read by the bridge. The mechanic that *raises* stress is a separate spec.
- **No expansion of the modifier-op library** beyond `factor` and `inverse_factor` in this spec. Future ops (additive, gate, ceiling/floor, etc.) ship when a real recipe needs them.
- **No independent radius modifiers.** Radius scales linearly with intensity (`radius_px = base_radius_ru × SLOT_HEIGHT_PX × intensity / UNIT`). A future "muffler" component that reduces radius without reducing intensity is its own spec.
- **No use of dB or other physically-correct units** for source strength. TCP doesn't simulate acoustic propagation; `radius_px` is a hard cutoff, not a dB-vs-distance computation. Linear thousandths stay the convention. Revisit if real acoustic simulation ships.

---

## Recipe shape — what the cat declares

The current cat recipe (`mods/tcp_cats/species/cat.jsonc`):

```jsonc
"purr": {
  "rate_when_satisfied": 1000,
  "base_radius_ru": 6
}
```

becomes:

```jsonc
"sensory_emissions": {
  "purr": {
    "trigger":         { "component": "contentment", "field": "is_satisfied", "equals": 1 },
    "base_intensity":  1000,
    "modifiers": [
      { "component": "stress", "field": "level", "op": "inverse_factor" }
    ],
    "base_radius_ru":  6
  }
},
"stress": { "level": 0 }
```

`sensory_emissions` is a dict keyed by **output_name** (`purr` here, `scent`/`ring`/etc. in future recipes). Each entry has:

| Field | Required? | Type | Meaning |
|---|---|---|---|
| `trigger` | optional | `{component, field, equals}` | Gate: if the field on the entity's component does not equal the int, intensity = 0 this tick. Component absent → also 0. Omit to always evaluate. |
| `base_intensity` | required | `int` literal **or** `{component, field}` ref | The starting value before modifiers. |
| `modifiers` | optional | array of `{component, field, op}` | Ordered list. Each looks up the field on the entity's component and applies the named op against the running intensity. Component absent → modifier silently skipped (identity). |
| `base_radius_ru` | required | `int` literal **or** `{component, field}` ref | Loudness ceiling at full intensity, in rack units (slot heights). |

The cat declares **what a cat knows about itself**: it's a contented animal that purrs, its stress dampens its purring, it has a certain loudness. It does **not** declare its channel (`acoustic`) or its falloff curve (`quadratic`) — those are properties of the channel and live in the global config below.

`stress` lands as a separate component (`{level: int}`) on the cat. Today it stays at 0 because no system writes it; the modifier reads it anyway and produces identity behavior, which proves the modifier shape works.

### `base_intensity` and `base_radius_ru` value sources

Both fields accept either an int literal or a `{component, field}` ref. Today the cat uses int literals (`1000` and `6`). The ref form is forward-compat for cases where the value should vary per-entity-instance (e.g. a "loud purr" trait that overrides the species default). The validator accepts both.

---

## Global config — translation and physics

Lives at `config/balance/sensory_outputs.jsonc`, mod-patchable through the standard ConfigRegistry layering described in `modding.md`.

```jsonc
{
  "schema_version": 1,
  "channels": {
    "acoustic": { "falloff": "quadratic" }
    // future: "thermal":   { "falloff": "inverse_square" },
    //         "olfactory": { "falloff": "linear" }
  },
  "outputs": {
    "purr": { "channel": "acoustic" }
    // future: "ring":  { "channel": "acoustic" },
    //         "scent": { "channel": "olfactory" }
  }
}
```

Two registries:

- **`channels`** — names a channel and declares its physics (`falloff` curve drawn from the engine's library). All outputs on the same channel share these properties.
- **`outputs`** — maps each output_name a recipe might declare to its channel.

A mod adding a new output_name patches `outputs`. A mod introducing a new channel patches `channels`. Both use the standard config-merge rules (deep merge per key; later mods override).

**Channel and falloff are forward-compat metadata.** No consumer reads them in this spec; HUM still reads `purr.intensity` directly. Their job is to (a) be present so the system has the right shape when channel-based propagation does ship, and (b) let the validator reject recipes that declare a `sensory_emissions.<x>` for an `<x>` that's not registered.

---

## Engine library — bounded vocabulary

The recipe and global config draw from a small set of named values. The set is engine-defined; mods do not extend it via JSON. Adding a new entry is an engine PR.

| Category | Today's set | Where it's used |
|---|---|---|
| **Modifier ops** | `factor` (× value / UNIT), `inverse_factor` (× (UNIT − value) / UNIT) | `modifiers[].op` |
| **Falloff curves** | `quadratic`, `linear`, `step`, `inverse_square` (existing `DesireScatter._apply_falloff` set) | `channels.<channel>.falloff` |
| **Value sources** | int literal, `{component, field}` ref | `base_intensity`, `base_radius_ru` |

Two ops cover stress (`inverse_factor`) and forecast mood (`factor`). When a third real shape proves out, it joins the library. The library being small is the point — modifier ops are a bounded vocabulary, not a formula DSL.

---

## Engine — `SensoryEmissionSystem`

```gdscript
class_name SensoryEmissionSystem extends RefCounted

var _db: GameStateDB
var _output_config: Dictionary  # output_name -> {channel: StringName}


func _init(db: GameStateDB, output_config: Dictionary) -> void:
    _db = db
    _output_config = output_config


func tick() -> void:
    for entity_id: int in _db.get_entities_with(&"sensory_emissions"):
        var emissions: Dictionary = _db.get_component(entity_id, &"sensory_emissions")
        for output_name: StringName in emissions:
            _emit_one(entity_id, output_name, emissions[output_name])


func _emit_one(entity_id: int, output_name: StringName, def: Dictionary) -> void:
    var intensity: int = _evaluate_intensity(entity_id, def)
    var base_radius_ru: int = _read_int(entity_id, def[&"base_radius_ru"])
    var base_radius_px: int = base_radius_ru * Constants.SLOT_HEIGHT_PX
    var radius_px: int = base_radius_px * intensity / Constants.UNIT
    _db.set_field(entity_id, output_name, &"intensity", intensity)
    _db.set_field(entity_id, output_name, &"radius_px", radius_px)


func _evaluate_intensity(entity_id: int, def: Dictionary) -> int:
    if def.has(&"trigger") and not _trigger_passes(entity_id, def[&"trigger"]):
        return 0
    var intensity: int = _read_int(entity_id, def[&"base_intensity"])
    for modifier: Dictionary in def.get(&"modifiers", []):
        intensity = _apply_modifier(entity_id, intensity, modifier)
    return maxi(0, intensity)


func _trigger_passes(entity_id: int, trigger: Dictionary) -> bool:
    var component: StringName = trigger[&"component"]
    if not _db.has_component(entity_id, component):
        return false
    var actual: int = _db.get_field(entity_id, component, trigger[&"field"])
    return actual == int(trigger[&"equals"])


func _apply_modifier(entity_id: int, intensity: int, modifier: Dictionary) -> int:
    var component: StringName = modifier[&"component"]
    if not _db.has_component(entity_id, component):
        return intensity   # absent → modifier is identity
    var value: int = _db.get_field(entity_id, component, modifier[&"field"])
    var op: StringName = modifier[&"op"]
    match op:
        &"factor":
            return intensity * value / Constants.UNIT
        &"inverse_factor":
            return intensity * (Constants.UNIT - value) / Constants.UNIT
        _:
            push_error("SensoryEmissionSystem: unknown modifier op: %s" % op)
            return intensity


func _read_int(entity_id: int, source: Variant) -> int:
    if source is int:
        return source
    if source is Dictionary:
        var ref: Dictionary = source
        return _db.get_field(entity_id, ref[&"component"], ref[&"field"])
    push_error("SensoryEmissionSystem: bad value source: %s" % source)
    return 0
```

**Tick behavior:** for each entity with a `sensory_emissions` component, evaluate every output the entity declares. For each output, compute intensity (trigger → base → modifiers → clamp at 0) and derive `radius_px = base_radius_px × intensity / UNIT`. Write to per-output components named after the output_name (so today's `purr.intensity` and `purr.radius_px` writes are unchanged from HUM's perspective).

**Failure handling:**
- Component referenced by `trigger` absent → trigger fails → intensity 0. Recipe error or transient absence; bridge silently degrades.
- Component referenced by a modifier absent → modifier is identity. Lets recipes declare modifiers for components that are conditionally present (a stress modifier that only matters when stress has been added by another spec).
- Unknown op → `push_error` + identity. Validator should have caught this at mod load; runtime error means a mod was patched in without revalidation.
- Bad `_read_int` source → `push_error` + 0. Same: validator should have caught.

The `Variant` parameter in `_read_int` is one of the rare allowed exceptions to the no-`Variant` rule: the recipe value is genuinely either int or Dictionary, and the discrimination happens at that one site.

---

## Materialization — `EntityDefRegistry` changes

Today `entity_def_registry.gd` lines 267–275 special-case the `purr` recipe block:

```gdscript
if def.has("purr"):
    var purr_cfg: Dictionary = def["purr"]
    var rate: int = int(purr_cfg.get("rate_when_satisfied", 0))
    var base_radius_ru: int = int(purr_cfg.get("base_radius_ru", 0))
    db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    db.set_component(
        id, &"purr_config",
        {&"rate_when_satisfied": rate, &"base_radius_ru": base_radius_ru},
    )
```

This block is **deleted**. Replaced by a generic materializer:

```gdscript
if def.has("sensory_emissions"):
    var emissions: Dictionary = _materialize_sensory_emissions(def["sensory_emissions"])
    db.set_component(id, &"sensory_emissions", emissions)
    for output_name: StringName in emissions:
        db.set_component(id, output_name, {&"intensity": 0, &"radius_px": 0})
```

`_materialize_sensory_emissions` walks the recipe block, rewriting String keys to StringName (the existing `_to_stringname_keys` pattern) so hot-path lookups use StringName.

The `purr_config` component vanishes from the data model. Its two fields (`rate_when_satisfied`, `base_radius_ru`) live as `base_intensity` and `base_radius_ru` inside `sensory_emissions.purr`. The `purr` component (`{intensity, radius_px}`) is unchanged — it's still where the bridge writes and HUM reads.

The `stress` component is materialized by an existing top-level pattern: any recipe-level dict with a known component name is projected directly. We add `stress` to the materialized component list (next to `hum_receiver`, `arm`, etc. in the existing `for comp_name` loop) so `"stress": {"level": 0}` in the recipe becomes a `&"stress"` component on the entity.

---

## Validator — `SensoryEmissionsSchemaValidator`

New file at `engine/mod/sensory_emissions_schema_validator.gd`. Runs at mod load alongside `SpeciesSchemaValidator`. Errors are grouped per recipe (matching the existing pattern).

Per-entry rules:
- Must have `base_intensity` (int OR `{component, field}` dict).
- Must have `base_radius_ru` (int OR `{component, field}` dict).
- If `trigger` is present: must have `component` (string), `field` (string), `equals` (int).
- If `modifiers` is present: each entry must have `component`, `field`, `op` ∈ engine's known op set.
- The output_name (the dict key) must exist in the loaded `outputs` global config.

Cross-referenced with `outputs` global config:
- Each `outputs.<name>.channel` must reference a name in `channels`.
- Each `channels.<name>.falloff` must be in the engine's known falloff set.

The validator does **not** check that referenced components (in `trigger.component`, `modifiers[].component`, value-ref components) actually exist on the entity — recipes can declare components later, and conditionally-present components are a valid pattern. Runtime gracefully handles absence.

---

## `cat.jsonc` migration

Diff against the current recipe:

```diff
   "tends_servers": true,
-  "purr": {
-    "rate_when_satisfied": 1000,
-    "base_radius_ru": 6
-  },
+  "sensory_emissions": {
+    "purr": {
+      "trigger":         { "component": "contentment", "field": "is_satisfied", "equals": 1 },
+      "base_intensity":  1000,
+      "modifiers": [
+        { "component": "stress", "field": "level", "op": "inverse_factor" }
+      ],
+      "base_radius_ru":  6
+    }
+  },
+  "stress": { "level": 0 },
```

No other recipe changes. Cat retains all its desire weights, ambient states, sprite config, etc.

---

## Tick order

Step 5 in `nodes/game_server.gd::_physics_process` becomes:

```gdscript
sensory_emission.tick()  # 5 — translates entity interior to per-output emissions
```

Same load-bearing constraints as the bridge it replaces:
- After `contentment.evaluate_all()` (step 4) so `is_satisfied` is fresh.
- Before `hum_system.tick_charge()` (step 6) so `purr.intensity` is current.

`tick-architecture.md`'s step list and `tests/integration/test_tick_loop.gd::EXPECTED_ORDER` both update to reference `sensory_emission` instead of `contentment_purr_bridge`.

---

## Tests

| Test | Status | Coverage |
|---|---|---|
| `tests/unit/test_sensory_emission_system.gd` | New | Trigger pass/fail/component-absent; base_intensity as int literal vs ref; intensity clamps at 0; tick is no-op when no entities have `sensory_emissions`. |
| `tests/unit/test_sensory_emission_modifiers.gd` | New | `inverse_factor` against stress (full / half / zero); modifier component absent → identity; unknown op → push_error + identity; modifier order matters (later modifiers see earlier ones' output). |
| `tests/unit/test_sensory_emission_radius.gd` | Migrated from `test_contentment_purr_bridge_radius.gd` | `radius_px` scales with intensity; `base_radius_ru` as ref vs literal; radius_px = 0 when intensity = 0. |
| `tests/unit/test_sensory_emissions_schema_validator.gd` | New | Missing `base_intensity` rejected; unknown op rejected; output_name not in global config rejected; channel not in `channels` rejected. |
| `tests/integration/test_purr_loop_soak.gd` | Modify | Setup uses `EntityDefRegistry.spawn(&"tcp_cats:cat", db, ...)` instead of hand-built components. No behavioral change. |
| `tests/integration/test_cat_in_box_charges_hum.gd` | Modify | Same — go through the registered recipe. |
| `tests/integration/test_hum_tick.gd` | Modify | Same. |
| `tests/unit/test_contentment_purr_bridge.gd` | Delete | Replaced by `test_sensory_emission_system.gd`. |
| `tests/unit/test_contentment_purr_bridge_radius.gd` | Delete | Replaced by `test_sensory_emission_radius.gd`. |

All new and modified tests are stamped via `script/stamp_tests` in the same commit (per `feedback_stamp_per_task_not_deferred`).

---

## Commit shape

Single atomic commit (per `feedback_atomic_commit_when_plan_would_break_validate` — all consumers must land together for `script/validate` to stay green).

Files added:
- `engine/core/sensory_emission_system.gd`
- `engine/mod/sensory_emissions_schema_validator.gd`
- `config/balance/sensory_outputs.jsonc`
- `tests/unit/test_sensory_emission_system.gd`
- `tests/unit/test_sensory_emission_modifiers.gd`
- `tests/unit/test_sensory_emission_radius.gd`
- `tests/unit/test_sensory_emissions_schema_validator.gd`

Files modified:
- `engine/mod/entity_def_registry.gd` — drop `purr` block, add `sensory_emissions` materializer, add `stress` to component projection list.
- `nodes/game_server.gd` — instantiate `SensoryEmissionSystem` with output config from `ConfigRegistry`; replace step-5 call.
- `mods/tcp_cats/species/cat.jsonc` — migrate per the diff above.
- `tests/integration/test_purr_loop_soak.gd`, `tests/integration/test_cat_in_box_charges_hum.gd`, `tests/integration/test_hum_tick.gd` — switch setup to recipe-driven spawn.
- `tests/integration/test_tick_loop.gd` — update `EXPECTED_ORDER`.
- `.claude/rules/hum-cable-system.md` — replace `purr_config` row in components table with `sensory_emissions`; rename "contentment→purr bridge" references to `SensoryEmissionSystem`.
- `.claude/rules/contentment.md` — bridge is now `SensoryEmissionSystem`; tick step 5 reference updates.
- `.claude/rules/tick-architecture.md` — step 5 reference and load-bearing constraints update.
- `.claude/rules/modding.md` — capability components table replaces `purr_config` row with `sensory_emissions`.
- `.claude/rules/animal-ai.md` — if any reference to `purr_config` or the bridge name needs updating.

Files deleted:
- `engine/core/contentment_purr_bridge.gd` (+ `.gd.uid` sidecar)
- `tests/unit/test_contentment_purr_bridge.gd`
- `tests/unit/test_contentment_purr_bridge_radius.gd`

`script/validate` green. Commit message focuses on *why* (data-driven mod surface, kill the method-per-modifier scaling problem) over *what* (the diff speaks for itself).

---

## Future extensions (informational, not in this spec)

- **Stress writer.** A separate spec adds the mechanic that raises stress (loud objects, hostile entities, kitten chaos). Once the writer ships, the cat's purr naturally dampens under stress without touching `SensoryEmissionSystem`.
- **Mood modifier.** Lands as a recipe edit: add `{ component: "mood", field: "factor", op: "factor" }` to `cat.jsonc`'s purr modifiers. No engine change.
- **Kitten amplifier.** Probably an event-driven writer to a `kitten_amplifier.factor` component on adult cats when kittens are nearby; then a `factor` modifier reads it. Recipe edit + writer system.
- **Thermal emission.** Cats radiate body heat. Recipe gets a `sensory_emissions.thermal` block; `outputs` config gets a `thermal: {channel: "thermal"}` entry; `channels` config gets a `thermal: {falloff: "inverse_square"}` entry. No engine change.
- **Scent emission.** Same shape, channel `olfactory`. Ferrets later subscribe to scent for tracking.
- **Channel-based propagation.** When HUM (or any future receiver) wants to subscribe by channel rather than by component name, a propagation system reads the `outputs.<name>.channel` mapping to know which per-output components to aggregate. This is what makes the `channel` field non-vestigial. Out of scope here.
- **Independent radius modifiers.** A "muffler" component that reduces `radius_px` without reducing `intensity` is its own spec. The current shape (radius scales linearly with intensity) covers every forecast modifier.
- **More modifier ops.** `additive`, `subtractive`, `gate`, `ceiling`, `floor` join the library when a real recipe needs them. Speculative additions stay out.
- **Per-channel real propagation.** If TCP ever simulates acoustic occlusion / Doppler / room reverb, revisit dB units, falloff math, and whether `radius_px` is still the right shape. Today it isn't worth the complexity.
