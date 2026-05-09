# SensoryEmissionSystem — data-driven, mod-extensible animal emission translation

**Status:** draft, 2026-05-09. Round 1 dev-team review folded in.
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
- **No stress modifier in cat.jsonc.** The stress component, the inverse_factor modifier line on cat's purr, and the modifier-shape proof landed via unit-test synthetic recipes only (Mochi R1). When a separate spec adds the stress writer, that spec also adds the modifier line to cat.

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
    "modifiers":       [],
    "base_radius_ru":  6
  }
}
```

Cat ships with **no modifiers**. The modifier-composition shape is proven in unit tests via a synthetic test recipe (see Tests). Stress lands when the spec that adds the stress *writer* ships — until there's a real mechanic raising stress, putting `inverse_factor stress` on cat is a Chekhov's gun the design caught (Mochi, R1). Mods can patch in their own modifiers without an engine change; this scope intentionally does not ship the example modifier in cat.jsonc.

`sensory_emissions` is a dict keyed by **output_name** (`purr` here, `scent`/`ring`/etc. in future recipes). Each entry has:

| Field | Required? | Type | Meaning |
|---|---|---|---|
| `trigger` | optional | `{component, field, equals}` | Gate: if the field on the entity's component does not equal the int, intensity = 0 this tick. Component absent → also 0. Omit to always evaluate. |
| `base_intensity` | required | `int` literal **or** `{component, field}` ref | The starting value before modifiers. |
| `modifiers` | required (may be empty) | array of `{id, component, field, op, priority?}` | Ordered list of modifiers (see "Modifier shape" below). |
| `base_radius_ru` | required | `int` literal **or** `{component, field}` ref | Loudness ceiling at full intensity, in rack units (slot heights). |

The cat declares **what a cat knows about itself**: it's a contented animal that purrs, it has a certain loudness. It does **not** declare its channel (`acoustic`) or its falloff curve (`quadratic`) — those are properties of the channel and live in the global config below.

### Modifier shape

Each modifier entry:

```jsonc
{ "id": "tcp_stress_writer:dampening", "component": "stress", "field": "level", "op": "inverse_factor", "priority": 0 }
```

| Field | Required? | Meaning |
|---|---|---|
| `id` | required | Mod-namespaced unique identifier (e.g. `tcp_stress_writer:dampening`). Required so `_remove` can target this entry across mods (`modding.md`). Validator rejects collisions within an emission. |
| `component`, `field`, `op` | required | What to read and how to apply. |
| `priority` | optional, default `0` | Composition order: lower priority applies first. Modifiers with equal priority compose in list order. |

Modifiers compose in **priority-then-list-order**. This is deterministic across mod-load permutations (Patches, R1): two mods adding modifiers via array-concat produce the same result regardless of which loads first, as long as they pick distinct priorities (or accept tied priority means "earlier-loading mod's modifier runs first within that tier"). For commutative ops (`factor`, `inverse_factor`) order is benign; for forecast non-commutative ops (`additive`, etc.) modders set `priority` deliberately. The validator emits a warning when a mod's modifier-array patch lands on an emission that already has modifiers, listing the resulting composition order so authors can spot unintended interleaving.

### `base_intensity` and `base_radius_ru` value sources

Both fields accept either an int literal or a `{component, field}` ref:

```jsonc
"base_intensity": 1000

// or (forward-compat, for per-instance variation):
"base_intensity": { "component": "purr_quality", "field": "rate" }
```

A mod adding a "loud purr" trait would declare `purr_quality: {rate: 1500}` in its species recipe and switch `base_intensity` to the ref form. The validator accepts both. **At materialization, both forms are canonicalized to a uniform tagged Dictionary** (see Materialization below) so runtime never branches on `int`-vs-`Dictionary` — there's no `Variant` in the hot path.

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

`modding.md` gets a new "Sensory Emission vocabulary" section listing the op names, falloff names, and value-source forms so modders can find them without grepping engine source. Validator error messages quote the known set: `unknown op "multiply" — known ops: factor, inverse_factor` (Patches, R1).

**Op commutativity.** `factor` and `inverse_factor` are both multiplicative and order-insensitive against each other. When a non-commutative op (forecast: `additive`, `subtractive`) joins the library, the validator emits a warning if mixed-commutativity modifiers appear in the same emission without explicit `priority` ordering — surfaces the design footgun without blocking (Mochi, R1).

---

## Engine — `SensoryEmissionSystem`

```gdscript
class_name SensoryEmissionSystem extends RefCounted

# Per-output universal contract: every emission writes intensity and
# radius_px on a component named after the output_name. radius_px is
# universal because every emission has a propagation distance — sound,
# scent, and light all attenuate over space (Bramble, R1).
#
# AI-DEV: Writes BOTH intensity AND radius_px each tick. radius_px =
# base_radius_px * intensity / UNIT. Future modifiers compose into the
# intensity formula via the modifiers list; do not reintroduce a
# fixed-radius shortcut.

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
    var base_radius_ru: int = _read_value(entity_id, def[&"base_radius_ru"])
    var base_radius_px: int = base_radius_ru * Constants.SLOT_HEIGHT_PX
    var radius_px: int = base_radius_px * intensity / Constants.UNIT
    _db.set_field(entity_id, output_name, &"intensity", intensity)
    _db.set_field(entity_id, output_name, &"radius_px", radius_px)


func _evaluate_intensity(entity_id: int, def: Dictionary) -> int:
    if def.has(&"trigger") and not _trigger_passes(entity_id, def[&"trigger"]):
        return 0
    var intensity: int = _read_value(entity_id, def[&"base_intensity"])
    var modifiers: Array[Dictionary] = def[&"modifiers"]   # priority-sorted at materialize
    for modifier: Dictionary in modifiers:
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


# Reads a canonicalized value source. The materializer rewrites recipe
# value sources (int literal OR {component, field} ref) into uniform
# tagged Dictionary form: {kind: &"literal", value: int} or
# {kind: &"ref", component: StringName, field: StringName}. Runtime
# branches once on `kind`; no Variant in hot path (Bramble, R1).
func _read_value(entity_id: int, source: Dictionary) -> int:
    var kind: StringName = source[&"kind"]
    if kind == &"literal":
        return source[&"value"]
    if kind == &"ref":
        return _db.get_field(entity_id, source[&"component"], source[&"field"])
    push_error("SensoryEmissionSystem: unknown value source kind: %s" % kind)
    return 0
```

**Tick behavior:** for each entity with a `sensory_emissions` component, evaluate every output the entity declares. For each output, compute intensity (trigger → base → modifiers → clamp at 0) and derive `radius_px = base_radius_px × intensity / UNIT`. Write to per-output components named after the output_name (so today's `purr.intensity` and `purr.radius_px` writes are unchanged from HUM's perspective).

**Failure handling:**
- Component referenced by `trigger` absent → trigger fails → intensity 0. Recipe error or transient absence; bridge silently degrades.
- Component referenced by a modifier absent → modifier is identity. Lets recipes declare modifiers for components that are conditionally present (e.g. a stress modifier that only matters when a future spec ships the stress writer).
- Unknown op → `push_error` + identity. Validator should have caught this at mod load; runtime error means a mod was patched in without revalidation.
- Unknown value-source `kind` → `push_error` + 0. Validator should have caught.

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

`_materialize_sensory_emissions` does three transformations the existing `_to_stringname_keys` (line 352) does not (Bramble, R1 — that helper is shallow):

1. **Recursive StringName key conversion.** Walks every nested dict (`trigger`, `modifiers[]`, value-source refs) rewriting String keys to StringName so hot-path `def[&"trigger"]` lookups hit. The existing shallow helper would silently miss nested keys.
2. **Value-source canonicalization.** Recipe forms (`1000` int literal, `{component: "x", field: "y"}` ref) both rewrite to a uniform tagged dict:
   - `1000` → `{&"kind": &"literal", &"value": 1000}`
   - `{component: "x", field: "y"}` → `{&"kind": &"ref", &"component": &"x", &"field": &"y"}`
   Runtime `_read_value` branches once on `kind`. No `Variant`.
3. **Modifier priority sort.** Modifiers are sorted by `priority` (default 0) ascending; ties preserve list order. Materialization-time sort means runtime iteration is straightforward and deterministic.

The `purr_config` component vanishes from the data model. Its two fields (`rate_when_satisfied`, `base_radius_ru`) live as `base_intensity` and `base_radius_ru` inside `sensory_emissions.purr`. The `purr` component (`{intensity, radius_px}`) is unchanged — it's still where the bridge writes and HUM reads.

This refactor does **not** add a `stress` component projection to the registry. Cat ships with no stress modifier (F1), so no recipe references `stress`. When a future spec adds stress, it adds the projection then.

---

## Validator — `SensoryEmissionsSchemaValidator`

New file at `engine/mod/sensory_emissions_schema_validator.gd`. Runs at mod load alongside `SpeciesSchemaValidator`. Errors are grouped per recipe (matching the existing pattern).

**Load order (Patches, R1):** all `config/balance/*.jsonc` layering — including `sensory_outputs.jsonc` — completes via `ConfigRegistry` before any `SensoryEmissionsSchemaValidator` or `SpeciesSchemaValidator` runs. The mod loader's existing phase ordering (config layering → schema validation → entity registration) covers this; the spec calls it out so cross-mod scenarios (`tcp_chef_cats` declaring an output its own patch defines) boot deterministically regardless of alphabetical mod-load order. Add a defensive assertion in `ModLoader._validate_phase` so future refactors can't reorder this silently.

**Per-entry rules** (every rule below is a `push_error` rejection path that has a corresponding test in `test_sensory_emissions_schema_validator.gd` — Kibble, R1):

1. `base_intensity` must be an int OR a `{component, field}` dict.
2. `base_radius_ru` must be an int OR a `{component, field}` dict.
3. If `trigger` is present: must have `component` (string), `field` (string), `equals` (int). Each missing/wrong-type field is a distinct rejection.
4. `modifiers` must be present (may be `[]`).
5. Each modifier must have `id` (mod-namespaced string), `component`, `field`, `op`.
6. Each modifier's `op` must be in the engine's known op set. Error message lists known ops.
7. Each modifier's `priority` (if present) must be an int.
8. Modifier `id`s within a single emission must be unique. Cross-emission duplicates are allowed.
9. The output_name (the dict key) must exist in the loaded `outputs` global config.
10. Ref-form value sources (`{component, field}`) must have string `component` and string `field`; non-string types are rejected.

**Cross-referenced with `outputs` global config:**
- Each `outputs.<name>.channel` must reference a name in `channels`.
- Each `channels.<name>.falloff` must be in the engine's known falloff set. Error message lists known falloff names.

**Component-ref existence check (warning, not error — Patches, R1):**
The validator does **not** *reject* recipes whose `trigger.component`, `modifiers[].component`, or value-source `component` is unresolved at load time — conditionally-present components are a valid pattern (a stress modifier that only matters when another mod ships the stress writer). But typos pass silently into runtime identity behavior, which is hard to debug. Compromise: validator emits a `push_warning` per unresolved component reference, listing the recipe and the resolution it tried. Modders see typos at load; legitimate forward-references still work.

**Modifier-merge warning (Patches, R1):**
When a mod's `modifiers` array-concat patch lands on an emission that already has modifiers from a base mod, the validator emits a warning summarizing the resulting composition order (priorities and tie-breaking). Mod authors can spot unintended interleaving without the system blocking on every patch.

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
+      "modifiers":       [],
+      "base_radius_ru":  6
+    }
+  },
```

No other recipe changes. Cat retains all its desire weights, ambient states, sprite config, etc. **No `stress` component is added** — the modifier-composition shape is proven in unit tests via a synthetic test recipe (Mochi, R1: avoid the half-built feature in cat.jsonc).

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

Test coverage was tightened in R1 review (Kibble) so each `push_error` site, branch, and regression-guard from the deleted bridge has a unit test that fails when the relevant code breaks. **No new integration tests are added** — the three existing integration tests switch to recipe-driven spawn; that's it.

### `tests/unit/test_sensory_emission_system.gd` — new

Covers the runner's outer iteration and per-emission writeback:

- `tick` is a no-op when no entities carry `sensory_emissions`.
- One entity with two outputs (e.g. `purr` and a synthetic `test_pulse`) writes both per-output components without clobbering. Proves the inner-loop iteration. (Kibble R1: missing in original list.)
- Multiple entities, one output each, all written. Proves the outer loop doesn't bail after the first.
- Trigger pass: `intensity = base_intensity`, `radius_px = base_radius_px`.
- Trigger fail (field mismatch): asserts **both** `intensity == 0` AND `radius_px == 0` in the same call. (Kibble R1: prevents regression where early return skips the radius writeback.)
- Trigger fail (component absent): same dual assertion.
- `base_intensity` as int literal — produces literal value.
- `base_intensity` as ref form — produces value from referenced component+field.
- Intensity clamps at 0 when modifiers drive it negative.
- `_read_value` with unknown `kind` → `assert_push_error`. (Kibble R1: validator should catch this at load, but the runtime branch needs explicit coverage so the `push_error` doesn't silently regress to a return-without-error.)

### `tests/unit/test_sensory_emission_modifiers.gd` — new

Covers modifier composition. Uses a synthetic test recipe with a `test_dampener` component (no production cat dependency).

- `factor` op: `intensity = 800 × 500 / 1000 = 400`.
- `inverse_factor` op: `intensity = 800 × (1000 − 250) / 1000 = 600`.
- Modifier component absent → modifier is identity.
- Unknown op → `assert_push_error` + identity.
- Modifier order: chain `factor 500` then `inverse_factor 500` against a base of 1000. Reversing the order produces a different result (250 vs. 250 for these specific values is commutative but `factor 800` then `inverse_factor 200` produces 640 vs. `inverse_factor 200` then `factor 800` produces 640 — pick non-commuting values for the assertion). (Kibble R1: original "later modifiers see earlier ones' output" test was underspecified; pick values where order genuinely changes the result.)
- Priority sort at materialization: declare `[priority: 10, priority: 0]` in recipe; materialized list applies priority 0 first.
- Integer truncation rounding: `intensity * value / UNIT` truncates toward zero. Pin with one assertion (`999 * 999 / 1000 == 998`). Future "fix" to `round()` would change HUM charge rates measurably; pinning the rounding contract prevents silent shifts. (Kibble R1.)

### `tests/unit/test_sensory_emission_radius.gd` — migrated from `test_contentment_purr_bridge_radius.gd`

- `radius_px` scales linearly with intensity.
- `radius_px == 0` when `intensity == 0`.
- `base_radius_ru` as ref form (different per-entity radius).
- **Stale-radius regression guard, ported verbatim** with its AI-DEV note: tick once at full intensity, tick again with trigger failing, assert `radius_px == 0` (not previous tick's value). The original test's existence is documented as a Ring 0 bug fix — the migration must preserve the assertion or the regression goes silent. (Kibble R1.)

### `tests/unit/test_sensory_emissions_schema_validator.gd` — new

One assertion per `push_error` path. Covers all 10 per-entry rules plus the 2 cross-referenced rules (channel resolution + falloff in known set). Specific cases:

- Missing `base_intensity` → rejected.
- Missing `base_radius_ru` → rejected.
- Trigger missing `field` / `equals` / non-int `equals` → each rejected.
- Modifier missing `id` / `component` / `field` / `op` → each rejected.
- Unknown op → rejected; error message lists known ops.
- Non-int `priority` → rejected.
- Duplicate modifier `id`s within an emission → rejected.
- `output_name` not in global config → rejected.
- Ref-form value with non-string `component` or `field` → rejected.
- Channel not in `channels` registry → rejected.
- Falloff not in known set → rejected.
- Unresolved component ref (typo'd `&"strss"`) → `push_warning`, not error. Recipe still loads. (Confirms the warn-not-error policy.)

### `tests/unit/test_entity_def_registry_sensory_emissions.gd` — extend existing registry tests

One assertion per materialization invariant (Kibble R1: keep this in the existing registry test file rather than adding a new test file):

- Recipe `sensory_emissions.purr` with String keys materializes to StringName keys in the component, including nested `trigger.component` and modifier entries.
- Recipe `base_intensity: 1000` materializes to `{kind: &"literal", value: 1000}`.
- Recipe `base_intensity: {component: "x", field: "y"}` materializes to `{kind: &"ref", component: &"x", field: &"y"}`.
- Recipe modifiers with explicit `priority` materialize sorted by priority ascending; tied priorities preserve list order.
- Recipe declaring `sensory_emissions.purr` initializes a `purr {intensity: 0, radius_px: 0}` component on the spawned entity.

### Species-purity guard, ported

`test_contentment_purr_bridge.gd::test_bridge_does_not_read_species` (line 51-58) → `test_sensory_emission_system.gd::test_system_does_not_read_species`. Implicitly covered by recipe-driven setup, but the explicit guard is cheap and catches species-label leaks. (Kibble R1.)

### Integration tests — modify, do not multiply

| Test | Change |
|---|---|
| `tests/integration/test_purr_loop_soak.gd` | Setup switches to `EntityDefRegistry.spawn(&"tcp_cats:cat", db, ...)` rather than hand-building `purr`/`purr_config` components. No behavioral assertions change. |
| `tests/integration/test_cat_in_box_charges_hum.gd` | Same. |
| `tests/integration/test_hum_tick.gd` | Same. |
| `tests/integration/test_tick_loop.gd` | Update `EXPECTED_ORDER` to reference `sensory_emission` instead of `contentment_purr_bridge`. |

**No new integration tests** (Kibble R1: integration test discipline is deliberate; spot-check the wiring, don't multiply).

### Files deleted

- `tests/unit/test_contentment_purr_bridge.gd` (replaced by `test_sensory_emission_system.gd`).
- `tests/unit/test_contentment_purr_bridge_radius.gd` (replaced by `test_sensory_emission_radius.gd`; stale-radius guard ported).

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
- `engine/mod/entity_def_registry.gd` — drop `purr` block (lines 267-275); add `sensory_emissions` materializer (recursive StringName conversion + value-source canonicalization + priority sort).
- `engine/mod/mod_loader.gd` — add defensive assertion in `_validate_phase` that config layering completes before schema validation runs.
- `nodes/game_server.gd` — instantiate `SensoryEmissionSystem` with output config from `ConfigRegistry`; replace step-5 call. **Also (Bramble R1):** swap `_seed_starter_box_stacks` query at line 468 from `db.get_entities_with(&"purr_config")` to `db.get_entities_with(&"sensory_emissions")` — broader, includes future scent/ring entities, fine for "pick first emitter to force-content for the boot demo."
- `tests/unit/test_purr_schema_load.gd` — line 50 reads `purr_config` directly. Either delete the test (the new validator covers schema concerns) or update it to read from `sensory_emissions`. Decide at implementation; spec lists this as a known modification.
- `mods/tcp_cats/species/cat.jsonc` — migrate per the diff above.
- `tests/integration/test_purr_loop_soak.gd`, `tests/integration/test_cat_in_box_charges_hum.gd`, `tests/integration/test_hum_tick.gd` — switch setup to recipe-driven spawn.
- `tests/integration/test_tick_loop.gd` — update `EXPECTED_ORDER`.
- `tests/unit/test_entity_def_registry_*.gd` — extend with the materialization-invariant assertions listed under Tests.
- `.claude/rules/hum-cable-system.md` — replace `purr_config` row in components table with `sensory_emissions`; rename "contentment→purr bridge" references to `SensoryEmissionSystem`.
- `.claude/rules/contentment.md` — bridge is now `SensoryEmissionSystem`; tick step 5 reference updates.
- `.claude/rules/tick-architecture.md` — step 5 reference and load-bearing constraints update.
- `.claude/rules/modding.md` — capability components table replaces `purr_config` row with `sensory_emissions`. **Also add a new "Sensory Emission vocabulary" section** (Patches R1) listing op names, falloff names, value-source forms, modifier shape, and a worked `base_intensity` ref-form example for modders.
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
