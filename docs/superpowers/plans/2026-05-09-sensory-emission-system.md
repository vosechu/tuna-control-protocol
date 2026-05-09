# SensoryEmissionSystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `engine/core/contentment_purr_bridge.gd` with a data-driven, mod-extensible `SensoryEmissionSystem` whose modifiers, channels, and propagation parameters are recipe-declared and config-patchable.

**Architecture:** Recipes declare `sensory_emissions.<output_name>` (trigger + base_intensity + modifiers + base_radius_ru). Global config maps output_name → channel and channel → falloff curve. Engine has a small bounded vocabulary of named ops (`factor`, `inverse_factor`) and falloff curves; modders draw from it but can't extend it via JSON. Materialization canonicalizes value sources to `{kind: "literal"|"ref", ...}` so the runtime hot path has no `Variant`. Each commit leaves `script/validate` green; the bridge and the new system coexist briefly during cutover.

**Tech Stack:** GDScript (Godot 4.6), GameStateDB column store, GUT test framework, JSONC config files via ConfigRegistry, ModLoader phase ordering.

**Spec:** `docs/superpowers/specs/2026-05-09-sensory-emission-system-design.md`. Read it before starting. Every task references back to the spec for code that's already specified.

---

## Pre-flight

- [ ] **Read the spec end-to-end.** All ~510 lines. Note especially: the canonicalized value-source shape (§Engine code), the modifier `id`/`priority` requirement (§Modifier shape), the load-order pin (§Validator), and the universal `intensity`+`radius_px` contract (§Engine code).
- [ ] **Verify clean working tree:** `git status` shows no in-flight changes you don't recognize. Per CLAUDE.md, "unexpected state is not damage to fix" — investigate before clobbering.
- [ ] **Verify baseline green:** `script/validate`. Must be 14/14 before starting.

---

## Task 1: Create global config + ConfigRegistry loading

The runner and validator both depend on the channel/output registry. Create it first as a standalone, testable artifact.

**Files:**
- Create: `config/balance/sensory_outputs.jsonc`
- Modify: wherever `ConfigRegistry` discovers `config/balance/*.jsonc` files (likely `engine/mod/config_registry.gd` — verify path)
- Test: extend the relevant `tests/unit/test_config_registry*.gd` if a config-loading test pattern exists; otherwise this task has no new test (config is a static data file consumed by Task 2's validator).

- [ ] **Step 1.1: Create the config file.**

```jsonc
// config/balance/sensory_outputs.jsonc
{
  "schema_version": 1,
  "channels": {
    "acoustic": { "falloff": "quadratic" }
  },
  "outputs": {
    "purr": { "channel": "acoustic" }
  }
}
```

- [ ] **Step 1.2: Verify ConfigRegistry picks it up.** Run the game's headless boot or a config-loading test. The registry should expose the `sensory_outputs` config without errors.

```bash
/Applications/Godot.app/Contents/MacOS/godot --headless --import 2>&1 | tail -20
```

Expected: no errors mentioning `sensory_outputs.jsonc`.

- [ ] **Step 1.3: Run `script/validate`.**

```bash
script/validate
```

Expected: 14/14 passed.

- [ ] **Step 1.4: Commit.**

```bash
git add config/balance/sensory_outputs.jsonc
git commit -m "$(cat <<'EOF'
feat(config): add sensory_outputs.jsonc registry for SensoryEmissionSystem

Channel→falloff and output→channel mappings the new system reads.
Forward-compat: no consumer reads channel today; HUM still reads
purr.intensity directly. The config exists so the validator can
reject recipes declaring outputs not in the registry.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: SensoryEmissionsSchemaValidator + tests

Validator runs at mod load. Standalone — no production recipe declares `sensory_emissions` yet, so no recipe gets validated against it.

**Files:**
- Create: `engine/mod/sensory_emissions_schema_validator.gd`
- Create: `tests/unit/test_sensory_emissions_schema_validator.gd`
- Modify: `engine/mod/mod_loader.gd` — wire the validator into the mod-load phase **after** config layering completes (the load-order pin from spec §Validator). Also add the defensive assertion that prevents future refactors from reordering this silently.

The validator's per-entry rules and rejection paths are spelled out in spec §Validator. Implement every rule; one assertion per rule in the test file.

- [ ] **Step 2.1: Write the validator test file (red).**

```gdscript
# tests/unit/test_sensory_emissions_schema_validator.gd
extends GutTest

# AI-DEV: One assertion per push_error rejection path. Each rule in
# spec §Validator must have a test here. If you add a rule, add a test.

var _validator: SensoryEmissionsSchemaValidator

func before_each() -> void:
    var output_config: Dictionary = {
        &"channels": {&"acoustic": {&"falloff": &"quadratic"}},
        &"outputs": {&"purr": {&"channel": &"acoustic"}},
    }
    _validator = SensoryEmissionsSchemaValidator.new(output_config)


func _valid_emission() -> Dictionary:
    return {
        "trigger": {"component": "contentment", "field": "is_satisfied", "equals": 1},
        "base_intensity": 1000,
        "modifiers": [],
        "base_radius_ru": 6,
    }


func test_valid_emission_passes() -> void:
    var ok: bool = _validator.validate({"purr": _valid_emission()})
    assert_true(ok)


func test_missing_base_intensity_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    entry.erase("base_intensity")
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("base_intensity")


func test_missing_base_radius_ru_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    entry.erase("base_radius_ru")
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("base_radius_ru")


func test_missing_modifiers_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    entry.erase("modifiers")
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("modifiers")


func test_trigger_missing_field_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    (entry["trigger"] as Dictionary).erase("field")
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("trigger")


func test_trigger_missing_equals_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    (entry["trigger"] as Dictionary).erase("equals")
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("trigger")


func test_trigger_non_int_equals_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    (entry["trigger"] as Dictionary)["equals"] = "yes"
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("equals")


func test_modifier_missing_id_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    entry["modifiers"] = [{"component": "stress", "field": "level", "op": "factor"}]
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("id")


func test_modifier_missing_component_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    entry["modifiers"] = [{"id": "test:m", "field": "level", "op": "factor"}]
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("component")


func test_modifier_unknown_op_rejected_with_known_set_listed() -> void:
    var entry: Dictionary = _valid_emission()
    entry["modifiers"] = [{"id": "test:m", "component": "stress",
        "field": "level", "op": "multiply"}]
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("multiply")
    assert_push_error("factor")        # error message lists known ops


func test_modifier_non_int_priority_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    entry["modifiers"] = [{"id": "test:m", "component": "stress",
        "field": "level", "op": "factor", "priority": "high"}]
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("priority")


func test_duplicate_modifier_ids_within_emission_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    entry["modifiers"] = [
        {"id": "test:m", "component": "a", "field": "x", "op": "factor"},
        {"id": "test:m", "component": "b", "field": "y", "op": "factor"},
    ]
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("duplicate")


func test_unknown_output_name_rejected() -> void:
    var ok: bool = _validator.validate({"unknown_output": _valid_emission()})
    assert_false(ok)
    assert_push_error("unknown_output")


func test_ref_form_with_non_string_component_rejected() -> void:
    var entry: Dictionary = _valid_emission()
    entry["base_intensity"] = {"component": 123, "field": "rate"}
    var ok: bool = _validator.validate({"purr": entry})
    assert_false(ok)
    assert_push_error("component")


func test_unresolved_component_ref_emits_warning_not_error() -> void:
    var entry: Dictionary = _valid_emission()
    entry["modifiers"] = [
        {"id": "test:typo", "component": "strss", "field": "level", "op": "factor"}
    ]
    # known-component set passed alongside the validate call (or the
    # validator collects them from a different source — see step 2.2).
    var ok: bool = _validator.validate({"purr": entry}, ["contentment"])
    assert_true(ok, "typo'd component is a warning, not a rejection")
    # Note: GUT currently has no assert_push_warning helper. Verify the
    # warning path manually if needed; the assertion above proves the
    # validator does not reject.
```

Run:

```bash
script/checks/gut_tests -f tests/unit/test_sensory_emissions_schema_validator.gd
```

Expected: every test fails with "SensoryEmissionsSchemaValidator not defined" (the class doesn't exist yet).

- [ ] **Step 2.2: Implement the validator (green).**

Create `engine/mod/sensory_emissions_schema_validator.gd`. Implementation skeleton — guard clauses per rule, each `push_error` matched by a test in the file above:

```gdscript
class_name SensoryEmissionsSchemaValidator extends RefCounted

const _KNOWN_OPS: Array[StringName] = [&"factor", &"inverse_factor"]
const _KNOWN_FALLOFFS: Array[StringName] = [
    &"quadratic", &"linear", &"step", &"inverse_square",
]

var _output_config: Dictionary

func _init(output_config: Dictionary) -> void:
    _output_config = output_config


func validate(emissions: Dictionary,
        known_components: Array[String] = []) -> bool:
    var all_ok: bool = true
    var outputs: Dictionary = _output_config.get(&"outputs", {})
    for output_name in emissions:
        var entry: Variant = emissions[output_name]
        if not (entry is Dictionary):
            push_error("SensoryEmissions: %s entry is not a Dictionary" % output_name)
            all_ok = false
            continue
        if not _validate_entry(output_name, entry, outputs, known_components):
            all_ok = false
    _validate_channels()
    return all_ok


func _validate_entry(name: Variant, entry: Dictionary, outputs: Dictionary,
        known_comps: Array[String]) -> bool:
    var ok: bool = true

    # Rule 9: output_name must exist in global outputs registry.
    if not outputs.has(String(name)) and not outputs.has(StringName(name)):
        push_error("SensoryEmissions: unknown output_name '%s' (not in outputs config)" % name)
        ok = false

    # Rule 4: modifiers must be present (may be empty).
    if not entry.has("modifiers"):
        push_error("SensoryEmissions[%s]: missing required field 'modifiers'" % name)
        ok = false
    elif not (entry["modifiers"] is Array):
        push_error("SensoryEmissions[%s]: 'modifiers' must be an Array" % name)
        ok = false

    # Rule 1: base_intensity required, int OR {component, field} dict.
    if not entry.has("base_intensity"):
        push_error("SensoryEmissions[%s]: missing required field 'base_intensity'" % name)
        ok = false
    elif not _is_valid_value_source(entry["base_intensity"], "%s.base_intensity" % name):
        ok = false

    # Rule 2: base_radius_ru required, int OR {component, field} dict.
    if not entry.has("base_radius_ru"):
        push_error("SensoryEmissions[%s]: missing required field 'base_radius_ru'" % name)
        ok = false
    elif not _is_valid_value_source(entry["base_radius_ru"], "%s.base_radius_ru" % name):
        ok = false

    # Rule 3: trigger (optional) shape check.
    if entry.has("trigger"):
        if not _is_valid_trigger(entry["trigger"], name):
            ok = false

    # Rules 5-8: each modifier shape; rule 8: ids unique within emission.
    if entry.has("modifiers") and entry["modifiers"] is Array:
        var seen_ids: Dictionary = {}
        for mod in entry["modifiers"]:
            if not _is_valid_modifier(mod, name, seen_ids):
                ok = false

    # Warning: unresolved component refs (typo guard, not a rejection).
    if not known_comps.is_empty():
        _warn_unresolved_components(entry, name, known_comps)

    return ok


func _is_valid_value_source(source: Variant, ctx: String) -> bool:
    if source is int:
        return true
    if source is Dictionary:
        var d: Dictionary = source
        if not d.has("component") or not (d["component"] is String):
            push_error("SensoryEmissions[%s]: ref-form 'component' must be string" % ctx)
            return false
        if not d.has("field") or not (d["field"] is String):
            push_error("SensoryEmissions[%s]: ref-form 'field' must be string" % ctx)
            return false
        return true
    push_error("SensoryEmissions[%s]: value source must be int or {component, field}" % ctx)
    return false


func _is_valid_trigger(trigger: Variant, ctx: Variant) -> bool:
    if not (trigger is Dictionary):
        push_error("SensoryEmissions[%s]: trigger must be a Dictionary" % ctx)
        return false
    var t: Dictionary = trigger
    var ok: bool = true
    if not t.has("component") or not (t["component"] is String):
        push_error("SensoryEmissions[%s]: trigger missing/non-string 'component'" % ctx)
        ok = false
    if not t.has("field") or not (t["field"] is String):
        push_error("SensoryEmissions[%s]: trigger missing/non-string 'field'" % ctx)
        ok = false
    if not t.has("equals"):
        push_error("SensoryEmissions[%s]: trigger missing 'equals'" % ctx)
        ok = false
    elif not (t["equals"] is int):
        push_error("SensoryEmissions[%s]: trigger 'equals' must be int" % ctx)
        ok = false
    return ok


func _is_valid_modifier(mod: Variant, emission_name: Variant,
        seen_ids: Dictionary) -> bool:
    if not (mod is Dictionary):
        push_error("SensoryEmissions[%s]: modifier must be a Dictionary" % emission_name)
        return false
    var m: Dictionary = mod
    var ok: bool = true

    if not m.has("id") or not (m["id"] is String):
        push_error("SensoryEmissions[%s]: modifier missing/non-string 'id'" % emission_name)
        ok = false
    else:
        var mid: String = m["id"]
        if seen_ids.has(mid):
            push_error("SensoryEmissions[%s]: duplicate modifier id '%s'" % [emission_name, mid])
            ok = false
        seen_ids[mid] = true

    for required in ["component", "field", "op"]:
        if not m.has(required) or not (m[required] is String):
            push_error("SensoryEmissions[%s]: modifier missing/non-string '%s'" % [emission_name, required])
            ok = false

    if m.has("op") and m["op"] is String:
        var op_sn: StringName = StringName(m["op"])
        if not _KNOWN_OPS.has(op_sn):
            push_error(
                "SensoryEmissions[%s]: unknown op '%s' — known ops: %s"
                % [emission_name, m["op"], ", ".join(_KNOWN_OPS.map(func(s): return String(s)))]
            )
            ok = false

    if m.has("priority") and not (m["priority"] is int):
        push_error("SensoryEmissions[%s]: modifier 'priority' must be int" % emission_name)
        ok = false

    return ok


func _validate_channels() -> void:
    var channels: Dictionary = _output_config.get(&"channels", {})
    var outputs: Dictionary = _output_config.get(&"outputs", {})
    for output_name in outputs:
        var output: Dictionary = outputs[output_name]
        var ch: Variant = output.get("channel", output.get(&"channel", null))
        if ch == null:
            continue   # missing-channel error caught elsewhere if relevant
        if not channels.has(String(ch)) and not channels.has(StringName(ch)):
            push_error(
                "SensoryEmissions: output '%s' references unknown channel '%s'"
                % [output_name, ch]
            )
    for ch_name in channels:
        var ch_def: Dictionary = channels[ch_name]
        var f: Variant = ch_def.get("falloff", ch_def.get(&"falloff", null))
        if f == null:
            push_error("SensoryEmissions: channel '%s' missing 'falloff'" % ch_name)
            continue
        var f_sn: StringName = StringName(f)
        if not _KNOWN_FALLOFFS.has(f_sn):
            push_error(
                "SensoryEmissions: channel '%s' unknown falloff '%s' — known: %s"
                % [ch_name, f, ", ".join(_KNOWN_FALLOFFS.map(func(s): return String(s)))]
            )


func _warn_unresolved_components(entry: Dictionary, name: Variant,
        known_comps: Array[String]) -> void:
    var refs: Array[String] = []
    if entry.has("trigger") and entry["trigger"] is Dictionary:
        var t: Dictionary = entry["trigger"]
        if t.has("component") and t["component"] is String:
            refs.append(t["component"])
    for vs in [entry.get("base_intensity"), entry.get("base_radius_ru")]:
        if vs is Dictionary and (vs as Dictionary).has("component"):
            refs.append((vs as Dictionary)["component"])
    if entry.has("modifiers") and entry["modifiers"] is Array:
        for mod in entry["modifiers"]:
            if mod is Dictionary and (mod as Dictionary).has("component"):
                refs.append((mod as Dictionary)["component"])
    for ref_name in refs:
        if not known_comps.has(ref_name):
            push_warning(
                "SensoryEmissions[%s]: component '%s' not declared by this recipe or engine; "
                "may be a typo or a forward reference to another mod's component"
                % [name, ref_name]
            )
```

Run tests:

```bash
script/checks/gut_tests -f tests/unit/test_sensory_emissions_schema_validator.gd
```

Expected: all pass.

- [ ] **Step 2.3: Wire into ModLoader.**

Modify `engine/mod/mod_loader.gd`. After config layering completes and before species recipes are validated, instantiate `SensoryEmissionsSchemaValidator` with the layered output config and call its `validate` for every recipe that declares `sensory_emissions`.

Add a defensive assertion in `_validate_phase` (or whichever method orchestrates load phases) that config layering has completed:

```gdscript
# AI-DEV: Schema validators (incl. SensoryEmissionsSchemaValidator)
# must run AFTER config layering completes. Cross-mod scenarios where
# mod A declares an output that mod B's patch defines depend on this
# ordering. Don't move this assertion or the schema phase.
assert(_config_layering_complete,
    "Schema validation runs before config layering — load-order regression")
```

- [ ] **Step 2.4: Stamp the test.**

```bash
script/stamp_tests tests/unit/test_sensory_emissions_schema_validator.gd
```

- [ ] **Step 2.5: Run `script/validate`.**

Expected: 14/14 passed.

- [ ] **Step 2.6: Commit.**

```bash
git add engine/mod/sensory_emissions_schema_validator.gd \
        engine/mod/sensory_emissions_schema_validator.gd.uid \
        engine/mod/mod_loader.gd \
        tests/unit/test_sensory_emissions_schema_validator.gd \
        tests/unit/test_sensory_emissions_schema_validator.gd.uid \
        tests/unit/test_sensory_emissions_schema_validator.gd.stamp
git commit -m "$(cat <<'EOF'
feat(mod): SensoryEmissionsSchemaValidator + load-order assertion

Validator covers every push_error rejection path from the spec
(missing base_intensity/base_radius_ru/modifiers, trigger field
errors, modifier id/component/field/op errors, unknown ops with the
known-set listed in the message, duplicate ids within an emission,
unknown output_name, non-string ref components, unknown channel,
unknown falloff). Unresolved component refs emit push_warning not
push_error (typos surface, conditional-present pattern preserved).

mod_loader.gd asserts config layering precedes schema validation so
cross-mod scenarios boot deterministically across alphabetical
mod-load order.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: SensoryEmissionSystem runner + tests

The runner is standalone — instantiated against synthetic test data, not yet wired into game_server.gd.

**Files:**
- Create: `engine/core/sensory_emission_system.gd`
- Create: `tests/unit/test_sensory_emission_system.gd`
- Create: `tests/unit/test_sensory_emission_modifiers.gd`
- Create: `tests/unit/test_sensory_emission_radius.gd`

Three test files mirror the three coverage areas from spec §Tests. The exact assertions are listed there; this task implements them.

- [ ] **Step 3.1: Write `test_sensory_emission_system.gd` (red).**

Cover the runner's outer iteration, trigger gating, value-source canonicalization, intensity clamping, and `_read_value` runtime guard. Exact assertions per spec §Tests `tests/unit/test_sensory_emission_system.gd` bullet list. Use synthetic recipes (no cat dependency).

Helper for setup, parallel to the bridge's `_make_db_with_purrer`:

```gdscript
extends GutTest

var _db: GameStateDB
var _system: SensoryEmissionSystem


func before_each() -> void:
    _db = GameStateDB.new()
    _system = SensoryEmissionSystem.new(_db, _output_config())


func _output_config() -> Dictionary:
    return {
        &"channels": {&"acoustic": {&"falloff": &"quadratic"}},
        &"outputs": {&"purr": {&"channel": &"acoustic"}},
    }


# Materializer canonicalized form: {kind: "literal"|"ref", ...}.
# Tests construct this directly because we're testing the runtime, not
# the materializer (which Task 4 covers).
func _emission_def_literal(base_intensity: int, base_radius_ru: int) -> Dictionary:
    return {
        &"trigger": {&"component": &"contentment", &"field": &"is_satisfied",
            &"equals": 1},
        &"base_intensity": {&"kind": &"literal", &"value": base_intensity},
        &"modifiers": [] as Array[Dictionary],
        &"base_radius_ru": {&"kind": &"literal", &"value": base_radius_ru},
    }


func _spawn_purrer(satisfied: int, base_intensity: int, base_radius_ru: int) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": satisfied})
    _db.set_component(id, &"sensory_emissions",
        {&"purr": _emission_def_literal(base_intensity, base_radius_ru)})
    _db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    return id


func test_tick_no_op_when_no_entities() -> void:
    _system.tick()  # must not crash


func test_satisfied_writes_full_intensity() -> void:
    var id: int = _spawn_purrer(1, 1000, 6)
    _system.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 1000)


func test_unsatisfied_writes_both_intensity_and_radius_zero() -> void:
    # AI-DEV: regression guard. Bridge's original test asserted both
    # fields go to 0; if the runner returns early before writing
    # radius_px on trigger fail, a stale radius from a previous tick
    # charges the wrong HUM. Both assertions required.
    var id: int = _spawn_purrer(0, 1000, 6)
    _db.set_field(id, &"purr", &"intensity", 999)   # prior value
    _db.set_field(id, &"purr", &"radius_px", 48)    # prior value
    _system.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 0)
    assert_eq(_db.get_field(id, &"purr", &"radius_px"), 0)


func test_trigger_component_absent_writes_zero() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"sensory_emissions",
        {&"purr": _emission_def_literal(1000, 6)})
    _db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    # No contentment component
    _system.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 0)


func test_one_entity_two_outputs_writes_both_without_clobber() -> void:
    # Synthetic second output to verify inner-loop iteration.
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 1})
    _db.set_component(id, &"sensory_emissions", {
        &"purr": _emission_def_literal(800, 6),
        &"test_pulse": _emission_def_literal(400, 4),
    })
    _db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    _db.set_component(id, &"test_pulse", {&"intensity": 0, &"radius_px": 0})

    var cfg: Dictionary = _output_config()
    (cfg[&"outputs"] as Dictionary)[&"test_pulse"] = {&"channel": &"acoustic"}
    var system := SensoryEmissionSystem.new(_db, cfg)
    system.tick()

    assert_eq(_db.get_field(id, &"purr", &"intensity"), 800)
    assert_eq(_db.get_field(id, &"test_pulse", &"intensity"), 400)


func test_multiple_entities_one_output_each() -> void:
    var id_a: int = _spawn_purrer(1, 100, 6)
    var id_b: int = _spawn_purrer(1, 200, 6)
    _system.tick()
    assert_eq(_db.get_field(id_a, &"purr", &"intensity"), 100)
    assert_eq(_db.get_field(id_b, &"purr", &"intensity"), 200)


func test_ref_form_base_intensity() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 1})
    _db.set_component(id, &"purr_quality", {&"rate": 1500})
    var def: Dictionary = _emission_def_literal(0, 6)
    def[&"base_intensity"] = {&"kind": &"ref",
        &"component": &"purr_quality", &"field": &"rate"}
    _db.set_component(id, &"sensory_emissions", {&"purr": def})
    _db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    _system.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 1500)


func test_unknown_value_kind_pushes_error() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 1})
    var def: Dictionary = _emission_def_literal(0, 6)
    def[&"base_intensity"] = {&"kind": &"bogus", &"value": 0}
    _db.set_component(id, &"sensory_emissions", {&"purr": def})
    _db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    _system.tick()
    assert_push_error("unknown value source kind")


func test_system_does_not_read_species() -> void:
    # AI-DEV: regression guard, ported from the bridge. Recipe-driven
    # spawn would catch this implicitly, but the explicit test is cheap.
    var id: int = _spawn_purrer(1, 7, 0)
    _system.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 7)
```

Run:

```bash
script/checks/gut_tests -f tests/unit/test_sensory_emission_system.gd
```

Expected: all fail (`SensoryEmissionSystem` not defined).

- [ ] **Step 3.2: Write `test_sensory_emission_modifiers.gd` (red).**

Cover modifier composition. Use a synthetic `test_dampener` component so cat is not involved.

```gdscript
extends GutTest

var _db: GameStateDB
var _system: SensoryEmissionSystem


func before_each() -> void:
    _db = GameStateDB.new()
    _system = SensoryEmissionSystem.new(_db, {
        &"channels": {&"acoustic": {&"falloff": &"quadratic"}},
        &"outputs": {&"purr": {&"channel": &"acoustic"}},
    })


func _spawn_with_modifier(modifier: Dictionary,
        modifier_value: int, base_intensity: int = 1000) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 1})
    _db.set_component(id, &"test_dampener", {&"value": modifier_value})
    _db.set_component(id, &"sensory_emissions", {&"purr": {
        &"trigger": {&"component": &"contentment",
            &"field": &"is_satisfied", &"equals": 1},
        &"base_intensity": {&"kind": &"literal", &"value": base_intensity},
        &"modifiers": [modifier] as Array[Dictionary],
        &"base_radius_ru": {&"kind": &"literal", &"value": 6},
    }})
    _db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    return id


func test_factor_op() -> void:
    var id: int = _spawn_with_modifier(
        {&"id": &"test:m", &"component": &"test_dampener",
            &"field": &"value", &"op": &"factor"}, 500)
    _system.tick()
    # 1000 * 500 / 1000 = 500
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 500)


func test_inverse_factor_op() -> void:
    var id: int = _spawn_with_modifier(
        {&"id": &"test:m", &"component": &"test_dampener",
            &"field": &"value", &"op": &"inverse_factor"}, 250)
    _system.tick()
    # 1000 * (1000 - 250) / 1000 = 750
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 750)


func test_modifier_component_absent_is_identity() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 1})
    # No test_dampener component
    _db.set_component(id, &"sensory_emissions", {&"purr": {
        &"trigger": {&"component": &"contentment",
            &"field": &"is_satisfied", &"equals": 1},
        &"base_intensity": {&"kind": &"literal", &"value": 1000},
        &"modifiers": [{&"id": &"test:m", &"component": &"test_dampener",
            &"field": &"value", &"op": &"factor"}] as Array[Dictionary],
        &"base_radius_ru": {&"kind": &"literal", &"value": 6},
    }})
    _db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    _system.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 1000)


func test_unknown_op_pushes_error_and_is_identity() -> void:
    var id: int = _spawn_with_modifier(
        {&"id": &"test:m", &"component": &"test_dampener",
            &"field": &"value", &"op": &"bogus"}, 500)
    _system.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 1000)
    assert_push_error("unknown modifier op")


func test_modifiers_compose_in_list_order() -> void:
    # Runtime iterates modifiers in the (already priority-sorted) list
    # order. Multiplicative ops are commutative, so this test asserts
    # the chained result against a manually-computed reference rather
    # than swapping orders. When non-commutative ops land, add a
    # follow-up test that flips the order and asserts the diff.
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 1})
    _db.set_component(id, &"test_dampener", {&"value": 500})
    _db.set_component(id, &"test_other", {&"value": 200})
    _db.set_component(id, &"sensory_emissions", {&"purr": {
        &"trigger": {&"component": &"contentment",
            &"field": &"is_satisfied", &"equals": 1},
        &"base_intensity": {&"kind": &"literal", &"value": 1000},
        &"modifiers": [
            {&"id": &"test:a", &"component": &"test_dampener",
                &"field": &"value", &"op": &"factor"},
            {&"id": &"test:b", &"component": &"test_other",
                &"field": &"value", &"op": &"inverse_factor"},
        ] as Array[Dictionary],
        &"base_radius_ru": {&"kind": &"literal", &"value": 6},
    }})
    _db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    _system.tick()
    # factor 500 first: 1000 * 500 / 1000 = 500
    # inverse_factor 200 next: 500 * (1000 - 200) / 1000 = 400
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 400)


func test_integer_truncation_rounds_toward_zero() -> void:
    # AI-DEV: pin the rounding contract. intensity * value / UNIT
    # truncates toward zero in GDScript int division. A future "fix" to
    # round() would change HUM charge rates measurably across thousands
    # of cats. Don't change unless deliberately altering balance.
    var id: int = _spawn_with_modifier(
        {&"id": &"test:m", &"component": &"test_dampener",
            &"field": &"value", &"op": &"factor"}, 999, 999)
    _system.tick()
    # 999 * 999 / 1000 = 998 (not 999; truncates)
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 998)
```

Run: same gut_tests command. Expected: all fail.

- [ ] **Step 3.3: Write `test_sensory_emission_radius.gd` (red).**

Migrate from `test_contentment_purr_bridge_radius.gd`. **Port the stale-radius regression guard verbatim** (it has the AI-DEV note about charging the wrong HUM).

```gdscript
extends GutTest

# AI-DEV: Pins the runner's two-field contract. Each tick the system
# writes BOTH purr.intensity AND purr.radius_px. A regression that
# updates only intensity (the obvious one) leaves a stale radius from
# a previous tick — the disk shrinks or grows based on yesterday's
# intensity and charges the wrong HUMs. radius_px formula is exactly
# `base_radius_ru * SLOT_HEIGHT_PX * intensity / UNIT`; don't shortcut
# it (dropping the intensity scaling makes a half-purring cat charge
# at full radius).

func _make_db(satisfied: int, base_radius_ru: int, base_intensity: int) -> GameStateDB:
    var db := GameStateDB.new()
    var id: int = db.create_entity()
    db.set_component(id, &"contentment", {&"is_satisfied": satisfied})
    db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
    db.set_component(id, &"sensory_emissions", {&"purr": {
        &"trigger": {&"component": &"contentment",
            &"field": &"is_satisfied", &"equals": 1},
        &"base_intensity": {&"kind": &"literal", &"value": base_intensity},
        &"modifiers": [] as Array[Dictionary],
        &"base_radius_ru": {&"kind": &"literal", &"value": base_radius_ru},
    }})
    return db


func _output_config() -> Dictionary:
    return {
        &"channels": {&"acoustic": {&"falloff": &"quadratic"}},
        &"outputs": {&"purr": {&"channel": &"acoustic"}},
    }


func test_radius_px_zero_when_not_satisfied() -> void:
    var db := _make_db(0, 6, 1000)
    var system := SensoryEmissionSystem.new(db, _output_config())
    system.tick()
    var ids: Array[int] = db.get_entities_with(&"purr")
    assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 0)


func test_radius_px_full_when_satisfied_at_full_intensity() -> void:
    var db := _make_db(1, 6, Constants.UNIT)
    var system := SensoryEmissionSystem.new(db, _output_config())
    system.tick()
    var ids: Array[int] = db.get_entities_with(&"purr")
    assert_eq(db.get_field(ids[0], &"purr", &"radius_px"),
        6 * Constants.SLOT_HEIGHT_PX)


func test_radius_px_scales_linearly_with_intensity() -> void:
    var db := _make_db(1, 6, 500)
    var system := SensoryEmissionSystem.new(db, _output_config())
    system.tick()
    var ids: Array[int] = db.get_entities_with(&"purr")
    # 6 * 8 * 500 / 1000 = 24
    assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 24)


func test_stale_radius_zeroed_after_trigger_fails() -> void:
    # AI-DEV: regression guard, ported from
    # test_contentment_purr_bridge_radius.gd. Tick once at full intensity
    # to seed radius_px. Tick again with trigger failing. radius_px
    # MUST be zero (not the previous tick's value). A regression that
    # returns early before writing radius_px on trigger fail leaves
    # stale data charging wrong HUMs.
    var db := _make_db(1, 6, Constants.UNIT)
    var system := SensoryEmissionSystem.new(db, _output_config())
    system.tick()
    var ids: Array[int] = db.get_entities_with(&"purr")
    assert_gt(db.get_field(ids[0], &"purr", &"radius_px"), 0,
        "Setup: radius should be non-zero after first tick")

    # Trigger now fails
    db.set_field(ids[0], &"contentment", &"is_satisfied", 0)
    system.tick()
    assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 0,
        "Trigger fail must zero radius_px (not leave stale value)")
```

Run: gut_tests. Expected: all fail.

- [ ] **Step 3.4: Implement `engine/core/sensory_emission_system.gd` (green).**

Use the code from spec §Engine — `SensoryEmissionSystem` verbatim. Includes the AI-DEV note from spec, `tick`, `_emit_one`, `_evaluate_intensity`, `_trigger_passes`, `_apply_modifier`, `_read_value`. Class signature uses `Array[Dictionary]` for modifiers.

Run all three test files:

```bash
script/checks/gut_tests \
    -f tests/unit/test_sensory_emission_system.gd \
    -f tests/unit/test_sensory_emission_modifiers.gd \
    -f tests/unit/test_sensory_emission_radius.gd
```

**WARNING:** `feedback_gut_multi_f_flag` — passing multiple `-f` flags silently drops all but the last. Run them as separate invocations:

```bash
script/checks/gut_tests -f tests/unit/test_sensory_emission_system.gd
script/checks/gut_tests -f tests/unit/test_sensory_emission_modifiers.gd
script/checks/gut_tests -f tests/unit/test_sensory_emission_radius.gd
```

Expected: all pass.

- [ ] **Step 3.5: Stamp the tests.**

```bash
script/stamp_tests tests/unit/test_sensory_emission_system.gd
script/stamp_tests tests/unit/test_sensory_emission_modifiers.gd
script/stamp_tests tests/unit/test_sensory_emission_radius.gd
```

- [ ] **Step 3.6: Run `script/validate`.** Expected: 14/14 passed.

- [ ] **Step 3.7: Commit.**

```bash
git add engine/core/sensory_emission_system.gd \
        engine/core/sensory_emission_system.gd.uid \
        tests/unit/test_sensory_emission_system.gd \
        tests/unit/test_sensory_emission_system.gd.uid \
        tests/unit/test_sensory_emission_system.gd.stamp \
        tests/unit/test_sensory_emission_modifiers.gd \
        tests/unit/test_sensory_emission_modifiers.gd.uid \
        tests/unit/test_sensory_emission_modifiers.gd.stamp \
        tests/unit/test_sensory_emission_radius.gd \
        tests/unit/test_sensory_emission_radius.gd.uid \
        tests/unit/test_sensory_emission_radius.gd.stamp
git commit -m "$(cat <<'EOF'
feat(core): SensoryEmissionSystem runner + comprehensive unit tests

Data-driven per-tick translation from animal interior state to
broadcast emission components. Reads sensory_emissions component
(materialized from recipe), evaluates trigger → base → modifiers →
clamp at 0. Writes intensity and radius_px on the per-output
component. No Variant in hot path — value sources canonicalized to
{kind: literal|ref, ...} dict at materialization (Task 4).

Test coverage: outer iteration (no-op, multi-output, multi-entity),
trigger gating (pass/fail/component-absent), value-source kinds
(literal, ref, unknown→push_error), intensity clamp at 0, modifier
ops (factor, inverse_factor, unknown→push_error+identity, absent→
identity), priority-sorted modifier composition, integer-truncation
rounding contract, stale-radius regression guard ported from bridge.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Extend EntityDefRegistry materializer

Add the `sensory_emissions` materialization path **alongside** the existing `purr` block handling. Both materializers run; existing recipes hit the `purr` path, future recipes hit the new path. Once cat migrates (Task 6), the old path becomes dead code; Task 8 removes it.

**Files:**
- Modify: `engine/mod/entity_def_registry.gd`
- Modify (extend): `tests/unit/test_entity_def_registry.gd` or add `tests/unit/test_entity_def_registry_sensory_emissions.gd` (match existing convention — there's already `test_entity_def_registry_desire_decay.gd` and `test_entity_def_registry_special_states.gd`, so a new sibling file fits).

- [ ] **Step 4.1: Write `test_entity_def_registry_sensory_emissions.gd` (red).**

Cover the materialization invariants from spec §Materialization:
- Recursive StringName conversion (nested keys in `trigger`, `modifiers[]`, value-source refs).
- Value-source canonicalization (int literal → `{kind: literal, value}`; dict ref → `{kind: ref, ...}`).
- Modifier priority sort.
- Per-output component initialization (`{intensity: 0, radius_px: 0}`).

```gdscript
extends GutTest

var _db: GameStateDB
var _registry: EntityDefRegistry


func before_each() -> void:
    _db = GameStateDB.new()
    _registry = EntityDefRegistry.new()


func _register_minimal_species(emissions: Dictionary) -> StringName:
    var def: Dictionary = {
        "id": "test:species",
        "name": "Test",
        "schema_version": 4,
        "senses": {"sight": 100, "hearing": 100, "smell": 100, "touch": 100},
        "desires": {"warmth": {"weight": 500, "decay": 0}},
        "ambient_states": {"warm": [], "cold": []},
        "special_states": {},
        "body_capabilities": {"walks": {"speed_px_per_tick": 2}},
        "body_geometry": {"size_ru": 2},
        "sprite_config": {},
        "hud_color": [1.0, 1.0, 1.0],
        "sensory_emissions": emissions,
    }
    _registry.register(&"test:species", def)
    return &"test:species"


func test_string_keys_become_stringname_recursively() -> void:
    var emissions: Dictionary = {
        "purr": {
            "trigger": {"component": "contentment", "field": "is_satisfied", "equals": 1},
            "base_intensity": 1000,
            "modifiers": [],
            "base_radius_ru": 6,
        },
    }
    _register_minimal_species(emissions)
    var id: int = _registry.spawn(&"test:species", _db)
    var component: Dictionary = _db.get_component(id, &"sensory_emissions")
    assert_true(component.has(&"purr"), "output_name key is StringName")
    var purr: Dictionary = component[&"purr"]
    assert_true(purr.has(&"trigger"), "trigger key is StringName")
    var trigger: Dictionary = purr[&"trigger"]
    assert_true(trigger.has(&"component"), "nested trigger.component key is StringName")
    assert_eq(trigger[&"component"], &"contentment",
        "trigger.component value is StringName")


func test_int_literal_base_intensity_canonicalized() -> void:
    var emissions: Dictionary = {
        "purr": {
            "trigger": {"component": "contentment", "field": "is_satisfied", "equals": 1},
            "base_intensity": 1000,
            "modifiers": [],
            "base_radius_ru": 6,
        },
    }
    _register_minimal_species(emissions)
    var id: int = _registry.spawn(&"test:species", _db)
    var component: Dictionary = _db.get_component(id, &"sensory_emissions")
    var bi: Dictionary = component[&"purr"][&"base_intensity"]
    assert_eq(bi[&"kind"], &"literal")
    assert_eq(bi[&"value"], 1000)


func test_ref_form_base_intensity_canonicalized() -> void:
    var emissions: Dictionary = {
        "purr": {
            "trigger": {"component": "contentment", "field": "is_satisfied", "equals": 1},
            "base_intensity": {"component": "purr_quality", "field": "rate"},
            "modifiers": [],
            "base_radius_ru": 6,
        },
    }
    _register_minimal_species(emissions)
    var id: int = _registry.spawn(&"test:species", _db)
    var component: Dictionary = _db.get_component(id, &"sensory_emissions")
    var bi: Dictionary = component[&"purr"][&"base_intensity"]
    assert_eq(bi[&"kind"], &"ref")
    assert_eq(bi[&"component"], &"purr_quality")
    assert_eq(bi[&"field"], &"rate")


func test_modifiers_sorted_by_priority_ascending() -> void:
    var emissions: Dictionary = {
        "purr": {
            "trigger": {"component": "contentment", "field": "is_satisfied", "equals": 1},
            "base_intensity": 1000,
            "modifiers": [
                {"id": "test:hi", "component": "a", "field": "x",
                    "op": "factor", "priority": 10},
                {"id": "test:lo", "component": "b", "field": "y",
                    "op": "factor", "priority": 0},
            ],
            "base_radius_ru": 6,
        },
    }
    _register_minimal_species(emissions)
    var id: int = _registry.spawn(&"test:species", _db)
    var component: Dictionary = _db.get_component(id, &"sensory_emissions")
    var modifiers: Array = component[&"purr"][&"modifiers"]
    assert_eq(modifiers.size(), 2)
    assert_eq((modifiers[0] as Dictionary)[&"id"], &"test:lo",
        "priority 0 sorts before priority 10")
    assert_eq((modifiers[1] as Dictionary)[&"id"], &"test:hi")


func test_modifiers_with_tied_priority_preserve_list_order() -> void:
    var emissions: Dictionary = {
        "purr": {
            "trigger": {"component": "contentment", "field": "is_satisfied", "equals": 1},
            "base_intensity": 1000,
            "modifiers": [
                {"id": "test:first", "component": "a", "field": "x", "op": "factor"},
                {"id": "test:second", "component": "b", "field": "y", "op": "factor"},
            ],
            "base_radius_ru": 6,
        },
    }
    _register_minimal_species(emissions)
    var id: int = _registry.spawn(&"test:species", _db)
    var component: Dictionary = _db.get_component(id, &"sensory_emissions")
    var modifiers: Array = component[&"purr"][&"modifiers"]
    assert_eq((modifiers[0] as Dictionary)[&"id"], &"test:first")
    assert_eq((modifiers[1] as Dictionary)[&"id"], &"test:second")


func test_per_output_component_initialized_to_zero() -> void:
    var emissions: Dictionary = {
        "purr": {
            "trigger": {"component": "contentment", "field": "is_satisfied", "equals": 1},
            "base_intensity": 1000,
            "modifiers": [],
            "base_radius_ru": 6,
        },
    }
    _register_minimal_species(emissions)
    var id: int = _registry.spawn(&"test:species", _db)
    assert_true(_db.has_component(id, &"purr"))
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 0)
    assert_eq(_db.get_field(id, &"purr", &"radius_px"), 0)
```

Run:

```bash
script/checks/gut_tests -f tests/unit/test_entity_def_registry_sensory_emissions.gd
```

Expected: all fail (the new materializer path doesn't exist yet).

- [ ] **Step 4.2: Implement the materializer (green).**

In `engine/mod/entity_def_registry.gd`, **after** the existing `purr` block (lines 267-275), add the new `sensory_emissions` materialization. Do NOT remove the old block — both must coexist until Task 6 migrates cat.jsonc.

```gdscript
# After the existing `if def.has("purr"):` block, add:

if def.has("sensory_emissions"):
    var emissions: Dictionary = _materialize_sensory_emissions(
        def["sensory_emissions"])
    db.set_component(id, &"sensory_emissions", emissions)
    for output_name: StringName in emissions:
        db.set_component(id, output_name,
            {&"intensity": 0, &"radius_px": 0})
```

Add the helper near the bottom of the file, alongside `_to_stringname_keys`:

```gdscript
# Materializes the recipe's sensory_emissions block:
#   - Recursively converts String keys to StringName at every nesting level.
#   - Canonicalizes value sources (base_intensity, base_radius_ru):
#       int literal → {kind: &"literal", value: int}
#       {component, field} → {kind: &"ref", component, field}
#   - Sorts each modifiers list by priority ascending; ties preserve list order.
func _materialize_sensory_emissions(raw: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for output_name in raw:
        var entry: Dictionary = raw[output_name]
        out[StringName(output_name)] = _materialize_emission_entry(entry)
    return out


func _materialize_emission_entry(raw: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    if raw.has("trigger"):
        out[&"trigger"] = _to_stringname_keys_recursive(raw["trigger"])
    out[&"base_intensity"] = _canonicalize_value_source(raw["base_intensity"])
    out[&"base_radius_ru"] = _canonicalize_value_source(raw["base_radius_ru"])

    var raw_mods: Array = raw.get("modifiers", [])
    var typed_mods: Array[Dictionary] = []
    for m: Dictionary in raw_mods:
        typed_mods.append(_to_stringname_keys_recursive(m))
    typed_mods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var pa: int = int(a.get(&"priority", 0))
        var pb: int = int(b.get(&"priority", 0))
        return pa < pb
    )
    out[&"modifiers"] = typed_mods
    return out


func _canonicalize_value_source(raw) -> Dictionary:
    if raw is int:
        return {&"kind": &"literal", &"value": raw}
    if raw is Dictionary:
        return {
            &"kind": &"ref",
            &"component": StringName((raw as Dictionary)["component"]),
            &"field": StringName((raw as Dictionary)["field"]),
        }
    push_error("EntityDefRegistry: bad value source: %s" % raw)
    return {&"kind": &"literal", &"value": 0}


func _to_stringname_keys_recursive(d: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for key in d:
        var v: Variant = d[key]
        var sn_key: StringName = StringName(key)
        if v is Dictionary:
            out[sn_key] = _to_stringname_keys_recursive(v)
        elif v is String:
            out[sn_key] = StringName(v)
        else:
            out[sn_key] = v
    return out
```

Run the test file:

```bash
script/checks/gut_tests -f tests/unit/test_entity_def_registry_sensory_emissions.gd
```

Expected: all pass.

- [ ] **Step 4.3: Stamp the test, run validate, commit.**

```bash
script/stamp_tests tests/unit/test_entity_def_registry_sensory_emissions.gd
script/validate
git add engine/mod/entity_def_registry.gd \
        tests/unit/test_entity_def_registry_sensory_emissions.gd \
        tests/unit/test_entity_def_registry_sensory_emissions.gd.uid \
        tests/unit/test_entity_def_registry_sensory_emissions.gd.stamp
git commit -m "$(cat <<'EOF'
feat(mod): EntityDefRegistry materializer for sensory_emissions

Adds the new materializer alongside the existing purr block handler.
Both paths run; legacy recipes (cat.jsonc still uses `purr` block at
this commit) hit the old path; future recipes use the new
sensory_emissions block. cat migrates in a later commit; the old
path is removed once it has no consumers.

Materialization invariants:
- Recursive StringName key conversion (nested trigger, modifiers,
  value-source refs).
- Value-source canonicalization to {kind: literal|ref, ...}: runtime
  has no Variant.
- Modifier priority sort (ascending; ties preserve list order).
- Per-output {intensity: 0, radius_px: 0} component initialization.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire SensoryEmissionSystem into game_server.gd alongside bridge

Both systems run in the tick. The new system iterates `sensory_emissions`-bearing entities (zero today). The bridge iterates `purr_config`-bearing entities (every cat). No behavior change.

**Files:**
- Modify: `nodes/game_server.gd` — instantiate `SensoryEmissionSystem`, add `sensory_emission.tick()` call AFTER `contentment_purr_bridge.tick()` in step 5.
- Modify: `tests/integration/test_tick_loop.gd` — add `sensory_emission` to `EXPECTED_ORDER` (between `contentment_purr_bridge` and `hum_system.tick_charge`).

- [ ] **Step 5.1: Update `EXPECTED_ORDER` (red).**

Open `tests/integration/test_tick_loop.gd`. Find `EXPECTED_ORDER` (likely a constant array). Add `&"sensory_emission.tick"` (or whatever exact match string the test uses — verify by reading the file) immediately after `&"contentment_purr_bridge.tick"`.

Run:

```bash
script/checks/gut_tests -f tests/integration/test_tick_loop.gd
```

Expected: fails — game_server.gd's actual tick doesn't call `sensory_emission.tick()` yet.

- [ ] **Step 5.2: Wire into `nodes/game_server.gd` (green).**

Add at the top of the class alongside `contentment_purr_bridge`:

```gdscript
var sensory_emission: SensoryEmissionSystem
```

In `_ready` (or wherever `contentment_purr_bridge` is instantiated):

```gdscript
var output_config: Dictionary = ConfigRegistry.get_config(&"sensory_outputs")
sensory_emission = SensoryEmissionSystem.new(db, output_config)
```

(Verify `ConfigRegistry`'s actual API — adapt the lookup to match.)

In `_physics_process`, immediately after `contentment_purr_bridge.tick()`:

```gdscript
contentment_purr_bridge.tick()                          # 5
sensory_emission.tick()                                 # 5b — coexists during cutover
```

The "5b" comment is intentional: this is a transitional state. Task 7 removes the bridge call.

Run:

```bash
script/checks/gut_tests -f tests/integration/test_tick_loop.gd
```

Expected: passes.

- [ ] **Step 5.3: Run full validate.**

```bash
script/validate
```

Expected: 14/14. The full suite must pass — bridge still produces purr.intensity for cats; HUM still charges; nothing breaks.

- [ ] **Step 5.4: Commit.**

```bash
git add nodes/game_server.gd tests/integration/test_tick_loop.gd
git commit -m "$(cat <<'EOF'
feat(server): wire SensoryEmissionSystem into tick alongside bridge

Both systems run; new one is no-op until cat.jsonc migrates (next
commit). Tick step ordering: contentment → bridge → sensory_emission
→ hum_system.tick_charge. EXPECTED_ORDER updated.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Atomic behavioral cutover — migrate cat.jsonc + dependent consumers

Single commit. Cat's `purr` block becomes `sensory_emissions.purr`. The line-468 query in `game_server.gd` swaps from `&"purr_config"` to `&"sensory_emissions"`. Three integration tests switch from hand-built `purr_config` setup to `EntityDefRegistry.spawn()`. `test_purr_schema_load.gd` updates or deletes.

After this commit: bridge runs but processes 0 entities (cats no longer have `purr_config`); SensoryEmissionSystem processes cat purr correctly. HUM intake unchanged. Game behavior preserved.

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc`
- Modify: `nodes/game_server.gd` (line 468 query swap)
- Modify: `tests/integration/test_purr_loop_soak.gd`
- Modify: `tests/integration/test_cat_in_box_charges_hum.gd`
- Modify: `tests/integration/test_hum_tick.gd`
- Modify or delete: `tests/unit/test_purr_schema_load.gd`

- [ ] **Step 6.1: Migrate `mods/tcp_cats/species/cat.jsonc`.**

Replace:

```jsonc
"purr": {
  "rate_when_satisfied": 1000,
  "base_radius_ru": 6
},
```

with:

```jsonc
"sensory_emissions": {
  "purr": {
    "trigger":         { "component": "contentment", "field": "is_satisfied", "equals": 1 },
    "base_intensity":  1000,
    "modifiers":       [],
    "base_radius_ru":  6
  }
},
```

Per spec §"cat.jsonc migration": no `stress` component is added.

- [ ] **Step 6.2: Swap line 468 query in `nodes/game_server.gd`.**

Find the `_seed_starter_box_stacks` method. It contains `db.get_entities_with(&"purr_config")`. Replace with `db.get_entities_with(&"sensory_emissions")`.

The semantic change: this query now finds ANY emitter (future scent/ring entities included), not just purr-capable ones. Per Bramble R1, that's fine for "pick first emitter for the boot demo." If the seed routine needs purr specifically, narrow with `_db.has_component(id, &"purr")` after the query.

- [ ] **Step 6.3: Migrate three integration tests to recipe-driven spawn.**

For each of `tests/integration/test_purr_loop_soak.gd`, `test_cat_in_box_charges_hum.gd`, `test_hum_tick.gd`:

Find the setup that hand-builds `contentment` + `purr` + `purr_config` components. Replace with:

```gdscript
var registry: EntityDefRegistry = ...  # however the test gets it; may need to load tcp_cats
var id: int = registry.spawn(&"tcp_cats:cat", db, {&"position": {&"x": x, &"y": y}})
db.set_field(id, &"contentment", &"is_satisfied", 1)  # if test needs it
```

The tests' behavioral assertions don't change — only the setup. The exact setup helpers in each file vary; read each test before editing.

- [ ] **Step 6.4: Update or delete `tests/unit/test_purr_schema_load.gd`.**

Read the file first. Line 50 reads `purr_config` directly. Decide:
- If the test verifies the cat recipe loads correctly: update to read `sensory_emissions.purr.base_intensity` instead.
- If the test verifies bridge-specific component shape: delete it (the new validator covers schema concerns).

Default: update to read `sensory_emissions`. Delete only if the test is purely bridge-internal.

- [ ] **Step 6.5: Run all tests.**

```bash
script/checks/gut_tests
```

Expected: all pass. The bridge runs but has 0 entities to process; SensoryEmissionSystem processes cats; HUM charges identically.

- [ ] **Step 6.6: Run validate.**

```bash
script/validate
```

Expected: 14/14.

- [ ] **Step 6.7: Boot the game (smoke test).**

```bash
/Applications/Godot.app/Contents/MacOS/godot --path . 2>&1 | head -30
```

Watch for: cats spawn, scenarios load, no errors mentioning `purr_config` or `sensory_emissions`. Quit after a few ticks.

- [ ] **Step 6.8: Re-stamp any tests that changed.**

```bash
script/stamp_tests tests/integration/test_purr_loop_soak.gd
script/stamp_tests tests/integration/test_cat_in_box_charges_hum.gd
script/stamp_tests tests/integration/test_hum_tick.gd
# If test_purr_schema_load.gd was kept:
script/stamp_tests tests/unit/test_purr_schema_load.gd
```

- [ ] **Step 6.9: Commit.**

```bash
git add mods/tcp_cats/species/cat.jsonc \
        nodes/game_server.gd \
        tests/integration/test_purr_loop_soak.gd \
        tests/integration/test_purr_loop_soak.gd.stamp \
        tests/integration/test_cat_in_box_charges_hum.gd \
        tests/integration/test_cat_in_box_charges_hum.gd.stamp \
        tests/integration/test_hum_tick.gd \
        tests/integration/test_hum_tick.gd.stamp \
        tests/unit/test_purr_schema_load.gd \
        tests/unit/test_purr_schema_load.gd.stamp 2>/dev/null   # if kept
# If test_purr_schema_load.gd was deleted:
git rm tests/unit/test_purr_schema_load.gd \
       tests/unit/test_purr_schema_load.gd.uid \
       tests/unit/test_purr_schema_load.gd.stamp 2>/dev/null

git commit -m "$(cat <<'EOF'
feat(cats): migrate cat.jsonc to sensory_emissions recipe shape

cat.jsonc now declares sensory_emissions.purr instead of the legacy
purr block. The bridge runs on 0 entities post-migration;
SensoryEmissionSystem processes cat purr. HUM intake unchanged.

Other consumer sites updated atomically:
- game_server.gd:_seed_starter_box_stacks query swap
  (purr_config → sensory_emissions; broader, fine for boot seed).
- Three integration tests switch to EntityDefRegistry.spawn for
  recipe-driven setup; behavioral assertions unchanged.
- test_purr_schema_load.gd updated/deleted depending on intent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Demolish ContentmentPurrBridge

Remove instantiation and tick call. Delete the file and its tests. Remove from `EXPECTED_ORDER`. Before this task, the bridge runs against 0 entities; after, it doesn't run at all.

**Files:**
- Modify: `nodes/game_server.gd`
- Modify: `tests/integration/test_tick_loop.gd`
- Delete: `engine/core/contentment_purr_bridge.gd` (+ `.gd.uid`)
- Delete: `tests/unit/test_contentment_purr_bridge.gd` (+ `.gd.uid`, `.gd.stamp`)
- Delete: `tests/unit/test_contentment_purr_bridge_radius.gd` (+ `.gd.uid`, `.gd.stamp`)

- [ ] **Step 7.1: Remove from `EXPECTED_ORDER` (red).**

Open `tests/integration/test_tick_loop.gd`. Remove the `&"contentment_purr_bridge.tick"` entry. Keep `&"sensory_emission.tick"`.

Run:

```bash
script/checks/gut_tests -f tests/integration/test_tick_loop.gd
```

Expected: fails — game_server.gd still calls bridge.

- [ ] **Step 7.2: Remove bridge instantiation + tick call (green).**

In `nodes/game_server.gd`:
- Delete the `var contentment_purr_bridge: ContentmentPurrBridge` declaration.
- Delete the `contentment_purr_bridge = ContentmentPurrBridge.new(db)` line.
- Delete the `contentment_purr_bridge.tick()` line in `_physics_process`. Keep `sensory_emission.tick()`. Renumber the comment from `5b` back to `5`.

Run the test file:

```bash
script/checks/gut_tests -f tests/integration/test_tick_loop.gd
```

Expected: passes.

- [ ] **Step 7.3: Delete the bridge file and its tests.**

```bash
git rm engine/core/contentment_purr_bridge.gd \
       engine/core/contentment_purr_bridge.gd.uid \
       tests/unit/test_contentment_purr_bridge.gd \
       tests/unit/test_contentment_purr_bridge.gd.uid \
       tests/unit/test_contentment_purr_bridge.gd.stamp \
       tests/unit/test_contentment_purr_bridge_radius.gd \
       tests/unit/test_contentment_purr_bridge_radius.gd.uid \
       tests/unit/test_contentment_purr_bridge_radius.gd.stamp
```

- [ ] **Step 7.4: Run validate.**

```bash
script/validate
```

Expected: 14/14. Watch carefully — if any check fails, the most likely cause is a remaining reference to `ContentmentPurrBridge` in code or a rule file. `grep -r "ContentmentPurrBridge\|contentment_purr_bridge" --include="*.gd" --include="*.md"` to find leftovers.

- [ ] **Step 7.5: Commit.**

```bash
git add nodes/game_server.gd tests/integration/test_tick_loop.gd
git commit -m "$(cat <<'EOF'
refactor(core): remove ContentmentPurrBridge, replaced by SensoryEmissionSystem

The bridge has zero entities to process after Task 6's cat migration.
Remove instantiation, tick call, and EXPECTED_ORDER entry. Delete
the file and its test suite (stale-radius regression guard ported to
test_sensory_emission_radius.gd in Task 3).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Drop legacy `purr` block from materializer

Cat is migrated. No recipe declares the legacy `purr` block. The dual-path materializer can shed the old path. Also drop the `purr_config` component from any remaining setup.

**Files:**
- Modify: `engine/mod/entity_def_registry.gd`

- [ ] **Step 8.1: Verify no consumers remain.**

```bash
grep -rn "purr_config\|\\.has(\"purr\")\\|def\\[\"purr\"\\]" \
    --include="*.gd" --include="*.jsonc" --include="*.md" \
    /Users/chucklauervose/github/tuna-control-protocol/
```

Expected: only references in rule docs (Task 9 updates them). No code references. If any code references remain, fix them in this task before deleting the materializer block.

- [ ] **Step 8.2: Delete the legacy `purr` block from `entity_def_registry.gd`.**

Find lines 267-275 (the `if def.has("purr"):` block that creates `purr` and `purr_config` components). Delete the block. The `sensory_emissions` materializer added in Task 4 already initializes the per-output `purr` component.

- [ ] **Step 8.3: Run all tests + validate.**

```bash
script/checks/gut_tests
script/validate
```

Expected: 14/14. If a test fails, check for any test still hand-building `purr_config` — they should all be using recipe-driven spawn now.

- [ ] **Step 8.4: Commit.**

```bash
git add engine/mod/entity_def_registry.gd
git commit -m "$(cat <<'EOF'
refactor(mod): remove legacy purr block from EntityDefRegistry

cat.jsonc is migrated; no recipe declares the legacy purr block. The
dual-path materializer collapses to the sensory_emissions path only.

The purr_config component vanishes from the data model entirely.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Update rule docs

The rule files reference `ContentmentPurrBridge`, `purr_config`, and old tick step naming. Bring them current.

**Files:**
- Modify: `.claude/rules/hum-cable-system.md`
- Modify: `.claude/rules/contentment.md`
- Modify: `.claude/rules/tick-architecture.md`
- Modify: `.claude/rules/modding.md`
- Modify: `.claude/rules/animal-ai.md`

- [ ] **Step 9.1: `hum-cable-system.md`.**

Find the components table. Replace the `purr_config` row with:

```markdown
| `sensory_emissions` | `{<output_name>: {trigger?, base_intensity, modifiers, base_radius_ru}}` | recipe-declared emitters | Server — saved, materialized from recipe at spawn |
```

Find any `ContentmentPurrBridge` or "contentment→purr bridge" reference. Replace with `SensoryEmissionSystem` and "sensory emission system."

- [ ] **Step 9.2: `contentment.md`.**

Replace bridge name references. Update tick step 5 reference to `sensory_emission.tick()`.

- [ ] **Step 9.3: `tick-architecture.md`.**

Update step 5: `contentment_purr_bridge.tick()` → `sensory_emission.tick()`. Update load-bearing constraints (`contentment_purr_bridge before hum_system.tick_charge` → `sensory_emission before hum_system.tick_charge`). Update the integration test reference if mentioned.

- [ ] **Step 9.4: `modding.md`.**

Replace the `purr_config` row in the capability components table with the `sensory_emissions` row (same shape as Step 9.1).

Add a new section "## Sensory Emission vocabulary" after the existing capability table. Per Patches R1:

```markdown
## Sensory Emission vocabulary

The `SensoryEmissionSystem` reads recipe-declared emissions and writes
per-output components. Modders pick from a bounded engine-defined
vocabulary; you cannot add new ops or falloff curves via JSON.

### Modifier ops

| Op | Effect on intensity |
|---|---|
| `factor` | `intensity * value / 1000` (multiplicative) |
| `inverse_factor` | `intensity * (1000 - value) / 1000` (dampener) |

Both ops are commutative against each other; order doesn't matter for
mixed `factor`/`inverse_factor` modifiers. When non-commutative ops
land (forecast: `additive`, `subtractive`), set explicit `priority`
to control composition order.

### Falloff curves (channel-level, forward-compat metadata today)

| Falloff | Shape |
|---|---|
| `quadratic` | `(1 - dist/radius)²` |
| `linear` | `1 - dist/radius` |
| `step` | `1` inside radius, `0` outside |
| `inverse_square` | `1 / (1 + (dist/radius)²)` |

These match `DesireScatter._apply_falloff`. No consumer reads channel
falloff for sensory emissions today; HUM reads `purr.intensity`
directly.

### Value-source forms

`base_intensity` and `base_radius_ru` accept either form:

```jsonc
// Int literal (typical):
"base_intensity": 1000

// Component-field ref (forward-compat, for per-instance variation):
"base_intensity": { "component": "purr_quality", "field": "rate" }
```

A "loud purr" trait mod would declare a `purr_quality: {rate: int}`
component on its species recipe and use the ref form.

### Modifier shape

Each entry in the `modifiers` array:

```jsonc
{
  "id": "tcp_stress_writer:dampening",  // mod-namespaced; required for _remove targetability
  "component": "stress",
  "field": "level",
  "op": "inverse_factor",
  "priority": 0                          // optional; default 0; lower applies first
}
```
```

- [ ] **Step 9.5: `animal-ai.md`.**

Search for `purr_config`, `ContentmentPurrBridge`, `contentment_purr_bridge`. Update each occurrence as appropriate. If no references exist, no edit needed.

- [ ] **Step 9.6: Run validate.**

```bash
script/validate
```

Expected: 14/14. (Doc-only changes shouldn't affect validation, but confirm.)

- [ ] **Step 9.7: Commit.**

```bash
git add .claude/rules/hum-cable-system.md \
        .claude/rules/contentment.md \
        .claude/rules/tick-architecture.md \
        .claude/rules/modding.md \
        .claude/rules/animal-ai.md
git commit -m "$(cat <<'EOF'
docs(rules): update for SensoryEmissionSystem rename

- hum-cable-system: components table swap (purr_config → sensory_emissions),
  bridge name references updated.
- contentment: bridge name references, tick step 5 ref.
- tick-architecture: step 5 swap, load-bearing constraints.
- modding: capability components table + new "Sensory Emission vocabulary"
  section with op/falloff/modifier vocabulary for modders.
- animal-ai: any stale references.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Post-flight

- [ ] **Verify final state:** `git log --oneline -10` shows the 9 task commits in order.
- [ ] **Run full validation one more time:** `script/validate` → 14/14.
- [ ] **Boot the game and watch for ~30 seconds:** cats spawn, settle, purr; HUM charges; lights stay on. No `push_error` in console.
- [ ] **Confirm no stragglers:** `grep -rn "ContentmentPurrBridge\|contentment_purr_bridge\|purr_config" --include="*.gd" --include="*.md" --include="*.jsonc"` returns nothing in `engine/`, `nodes/`, `tests/`, `mods/`, or `.claude/rules/`. Hits in `docs/superpowers/specs/` (the spec itself) and `docs/superpowers/plans/` (this plan) are fine — those are historical artifacts.

---

## What this plan deliberately doesn't do (per spec §Non-goals)

- No stress writer.
- No mood, kitten amplifier, thermal, or scent modifiers/emissions.
- No new modifier ops beyond `factor` and `inverse_factor`.
- No channel-based propagation refactor (HUM still reads `purr.intensity` directly).
- No unification with `advertisements`.
- No dB or physically-correct units.

When those features ship, each is its own spec + plan.
